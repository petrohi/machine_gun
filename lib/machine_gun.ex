defmodule MachineGun do
  @moduledoc ""

  alias MachineGun.{Supervisor, Worker}

  @default_request_timeout 5000
  @default_pool_timeout 1000
  @default_pool_size 4
  @default_pool_max_overflow 4
  @default_pool_strategy :lifo

  defmodule Response do
    defstruct [
      :request_url,
      :status_code,
      :headers,
      :body,
      :trailers
    ]
  end

  defmodule Request do
    defstruct [
      :method,
      :path,
      :headers,
      :body
    ]
  end

  defmodule Error do
    defexception reason: nil
    def message(%__MODULE__{reason: reason}), do: inspect(reason)
  end

  def head(url, headers \\ [], opts \\ %{}) do
    request("HEAD", url, "", headers, opts)
  end

  def get(url, headers \\ [], opts \\ %{}) do
    request("GET", url, "", headers, opts)
  end

  def post(url, body, headers \\ [], opts \\ %{}) do
    request("POST", url, body, headers, opts)
  end

  def put(url, body, headers \\ [], opts \\ %{}) do
    request("PUT", url, body, headers, opts)
  end

  def delete(url, headers \\ [], opts \\ %{}) do
    request("DELETE", url, "", headers, opts)
  end

  def head!(url, headers \\ [], opts \\ %{}) do
    request!("HEAD", url, "", headers, opts)
  end

  def get!(url, headers \\ [], opts \\ %{}) do
    request!("GET", url, "", headers, opts)
  end

  def post!(url, body, headers \\ [], opts \\ %{}) do
    request!("POST", url, body, headers, opts)
  end

  def put!(url, body, headers \\ [], opts \\ %{}) do
    request!("PUT", url, body, headers, opts)
  end

  def delete!(url, headers \\ [], opts \\ %{}) do
    request!("DELETE", url, "", headers, opts)
  end

  def request!(method, url, body \\ "", headers \\ [], opts \\ %{}) do
    case request(method, url, body, headers, opts) do
      {:ok, response} -> response
      {:error, %Error{reason: reason}} -> raise Error, reason: reason
    end
  end

  def request(method, url, body \\ "", headers \\ [], opts \\ %{})
      when is_binary(url) and is_list(headers) and is_map(opts) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, path: path, port: port, query: query}
      when is_binary(host) and is_integer(port) and (scheme === "http" or scheme == "https") ->
        pool_group = opts |> Map.get(:pool_group, :default)

        {transport, protocols} =
          case scheme do
            "http" -> {:tcp, [:http]}
            "https" -> {:ssl, [:http2, :http]}
          end

        pool = "#{pool_group}@#{host}:#{port}" |> String.to_atom()

        path =
          if path != nil do
            path
          else
            "/"
          end

        path =
          if query != nil do
            "#{path}?#{query}"
          else
            path
          end

        headers =
          headers
          |> Enum.map(fn
            {name, value} when is_integer(value) ->
              {name, Integer.to_string(value)}

            {name, value} ->
              {name, value}
          end)

        method =
          case method do
            :head -> "HEAD"
            :get -> "GET"
            :post -> "POST"
            :put -> "PUT"
            :delete -> "DELETE"
            s when is_binary(s) -> s
          end

        pool_opts = Application.get_env(:machine_gun, pool_group, %{})

        pool_timeout =
          opts
          |> Map.get(
            :pool_timeout,
            pool_opts
            |> Map.get(:pool_timeout, @default_pool_timeout)
          )

        request_timeout =
          opts
          |> Map.get(
            :request_timeout,
            pool_opts
            |> Map.get(:request_timeout, @default_request_timeout)
          )

        request = %Request{
          method: method,
          path: path,
          headers: headers,
          body: body
        }

        try do
          do_request(pool, url, request, pool_timeout, request_timeout)
        catch
          :exit, {:noproc, _} ->
            size = pool_opts |> Map.get(:pool_size, @default_pool_size)
            max_overflow = pool_opts |> Map.get(:pool_max_overflow, @default_pool_max_overflow)
            strategy = pool_opts |> Map.get(:pool_strategy, @default_pool_strategy)
            conn_opts = pool_opts |> Map.get(:conn_opts, %{})

            conn_opts =
              %{
                retry: 0,
                http_opts: %{keepalive: :infinity},
                protocols: protocols,
                transport: transport
              }
              |> Map.merge(conn_opts)

            case ensure_pool(pool, host, port, size, max_overflow, strategy, conn_opts) do
              :ok ->
                do_request(pool, url, request, pool_timeout, request_timeout)

              {:error, error} ->
                {:error, %Error{reason: error}}
            end
        end

      %URI{} ->
        {:error, %Error{reason: :bad_url_scheme}}

      _ ->
        {:error, %Error{reason: :bad_url}}
    end
  end

  defp ensure_pool(pool, host, port, size, max_overflow, strategy, conn_opts) do
    case Supervisor.start(
           pool,
           host,
           port,
           size,
           max_overflow,
           strategy,
           conn_opts
         ) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      error ->
        error
    end
  end

  defp do_request(
         pool,
         url,
         %Request{method: method, path: path} = request,
         pool_timeout,
         request_timeout
       ) do
    m_mod = Application.get_env(:machine_gun, :metrics_mod)
    m_state = if m_mod != nil, do: m_mod.queued(pool, :poolboy.status(pool), method, path)

    try do
      case :poolboy.transaction(
             pool,
             fn worker ->
               Worker.request(worker, request, request_timeout, m_mod, m_state)
             end,
             pool_timeout
           ) do
        {:ok, response} ->
          {:ok, %Response{response | request_url: url}}

        error ->
          error
      end
    catch
      :exit, {:timeout, _} ->
        if m_state != nil, do: m_mod.queue_timeout(m_state)
        {:error, %Error{reason: :pool_timeout}}

      :exit, {{:shutdown, error}, _} ->
        {:error, %Error{reason: error}}
    end
  end
end
