defmodule MachineGun.Worker do
  @moduledoc ""

  alias MachineGun.{Request, Response, Worker, Error}

  use GenServer
  require Logger

  defstruct [
    :host,
    :port,
    :conn_opts,
    :gun_pid,
    :gun_ref,
    :m_mod,
    :m_state,
    streams: %{},
    cancels: %{}
  ]

  def request(worker, request, request_timeout, m_mod, m_state) do
    m_state = if m_state != nil, do: m_mod.requested(m_state)
    cancel_ref = :erlang.make_ref()

    try do
      case GenServer.call(
             worker,
             {:request, request, cancel_ref},
             request_timeout
           ) do
        {:ok, _} = r ->
          if m_state != nil, do: m_mod.request_success(m_state)
          r

        error ->
          if m_state != nil, do: m_mod.request_error(m_state)
          error
      end
    catch
      :exit, {:timeout, _} ->
        :ok = GenServer.cast(worker, {:cancel, cancel_ref})
        if m_state != nil, do: m_mod.request_timeout(m_state)
        {:error, %Error{reason: :request_timeout}}
    end
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init([host, port, conn_opts]) do
    m_mod = Application.get_env(:machine_gun, :metrics_mod)
    {:ok, %Worker{host: host, port: port, conn_opts: conn_opts, m_mod: m_mod}}
  end

  def handle_info(
        {:gun_up, gun_pid, protocol},
        %Worker{host: host, port: port, m_mod: m_mod, gun_pid: gun_pid} = worker
      ) do
    m_state = if m_mod != nil, do: m_mod.up(host, port, protocol)
    {:noreply, %{worker | m_state: m_state}}
  end

  def handle_info(
        {:gun_down, gun_pid, _protocol, reason, _killed_streams, unprocessed_streams},
        %Worker{streams: streams, gun_pid: gun_pid, m_mod: m_mod, m_state: m_state} = worker
      ) do
    m_state = if m_state != nil, do: m_mod.down(m_state)

    streams =
      streams
      |> Map.drop(unprocessed_streams)

    {:noreply,
     reply_error(
       %{worker | streams: streams, m_state: m_state},
       reason
     )}
  end

  def handle_info(
        {:gun_error, gun_pid, stream_ref, reason},
        %Worker{streams: streams, gun_pid: gun_pid} = worker
      ) do
    case streams |> Map.get(stream_ref) do
      nil ->
        {:noreply, worker}

      {from, _, cancel_ref} ->
        {:noreply,
         reply_error(
           worker,
           stream_ref,
           reason,
           from,
           cancel_ref
         )}
    end
  end

  def handle_info(
        {:gun_error, gun_pid, reason},
        %Worker{gun_pid: gun_pid} = worker
      ) do
    {:noreply, reply_error(worker, reason)}
  end

  def handle_info(
        {:gun_response, gun_pid, stream_ref, is_fin, status, headers},
        %Worker{
          gun_pid: gun_pid,
          streams: streams
        } = worker
      ) do
    case streams |> Map.get(stream_ref) do
      nil ->
        {:noreply, worker}

      {from, %Response{} = response, cancel_ref} ->
        response = %Response{response | status_code: status, headers: headers, body: ""}

        {:noreply,
         reply_or_continue(
           worker,
           stream_ref,
           is_fin,
           from,
           response,
           cancel_ref
         )}
    end
  end

  def handle_info(
        {:gun_data, gun_pid, stream_ref, is_fin, data},
        %Worker{
          gun_pid: gun_pid,
          streams: streams
        } = worker
      ) do
    case streams |> Map.get(stream_ref) do
      nil ->
        {:noreply, worker}

      {from, %Response{body: body} = response, cancel_ref} ->
        response = %Response{response | body: <<body::binary, data::binary>>}

        {:noreply,
         reply_or_continue(
           worker,
           stream_ref,
           is_fin,
           from,
           response,
           cancel_ref
         )}
    end
  end

  def handle_info(
        {:gun_trailers, gun_pid, stream_ref, trailers},
        %Worker{
          gun_pid: gun_pid,
          streams: streams
        } = worker
      ) do
    case streams |> Map.get(stream_ref) do
      nil ->
        {:noreply, worker}

      {from, %Response{} = response, cancel_ref} ->
        response = %Response{response | trailers: trailers}

        {:noreply,
         reply_or_continue(
           worker,
           stream_ref,
           :fin,
           from,
           response,
           cancel_ref
         )}
    end
  end

  def handle_info(
        {:DOWN, gun_ref, :process, gun_pid, reason},
        %Worker{
          gun_pid: gun_pid,
          gun_ref: gun_ref
        } = worker
      ) do
    {:noreply,
     reply_error(
       %{worker | gun_pid: nil, gun_ref: nil},
       reason
     )}
  end

  def handle_info(_, worker) do
    {:noreply, worker}
  end

  def handle_cast(
        {:cancel, cancel_ref},
        %Worker{gun_pid: gun_pid, gun_ref: gun_ref, cancels: cancels} = worker
      ) do
    case cancels |> Map.get(cancel_ref) do
      nil ->
        {:noreply, worker}

      stream_ref ->
        worker = clean_refs(worker, stream_ref, cancel_ref)
        :ok = :gun.close(gun_pid)
        true = :erlang.demonitor(gun_ref, [:flush])
        {:noreply, %{worker | gun_pid: nil, gun_ref: nil}}
    end
  end

  def handle_call(
        {:request,
         %Request{
           method: method,
           path: path,
           headers: headers,
           body: body
         }, cancel_ref},
        from,
        %Worker{
          streams: streams,
          cancels: cancels
        } = worker
      ) do
    %Worker{gun_pid: gun_pid} =
      worker =
      case worker do
        %Worker{host: host, port: port, conn_opts: conn_opts, gun_pid: nil} = worker ->
          {:ok, gun_pid} = :gun.open(host, port, conn_opts)
          gun_ref = :erlang.monitor(:process, gun_pid)
          %{worker | gun_pid: gun_pid, gun_ref: gun_ref}

        worker ->
          worker
      end

    stream_ref = :gun.request(gun_pid, method, path, headers, body, %{})

    {:noreply,
     %{
       worker
       | streams: streams |> Map.put(stream_ref, {from, %Response{}, cancel_ref}),
         cancels: cancels |> Map.put(cancel_ref, stream_ref)
     }}
  end

  defp reply_error(%Worker{streams: streams} = worker, reason) do
    streams
    |> Map.values()
    |> Enum.each(fn {from, %Response{headers: headers} = response, _} ->
      case is_last_request(headers) do
        true -> :ok = GenServer.reply(from, {:ok, response})
        _ -> :ok = GenServer.reply(from, {:error, parse_reason(reason)})
      end
    end)

    %{worker | streams: %{}, cancels: %{}}
  end

  defp reply_error(
         worker,
         stream_ref,
         reason,
         from,
         cancel_ref
       ) do
    :ok = GenServer.reply(from, {:error, parse_reason(reason)})
    clean_refs(worker, stream_ref, cancel_ref)
  end

  defp reply_or_continue(
         %Worker{streams: streams} = worker,
         stream_ref,
         is_fin,
         from,
         %Response{headers: headers} = response,
         cancel_ref
       ) do
    if is_fin == :fin && !is_last_request(headers) do
      :ok = GenServer.reply(from, {:ok, response})
      clean_refs(worker, stream_ref, cancel_ref)
    else
      %{worker | streams: streams |> Map.put(stream_ref, {from, response, cancel_ref})}
    end
  end

  defp clean_refs(
         %Worker{streams: streams, cancels: cancels} = worker,
         stream_ref,
         cancel_ref
       ) do
    %{
      worker
      | streams: streams |> Map.delete(stream_ref),
        cancels: cancels |> Map.delete(cancel_ref)
    }
  end

  def parse_reason({:shutdown, reason}), do: %Error{reason: reason}
  def parse_reason(reason), do: %Error{reason: reason}

  defp is_last_request(headers) do
    Enum.any?(headers, fn
      {"connection", v} -> v == "close"
      _ -> false
    end)
  end
end
