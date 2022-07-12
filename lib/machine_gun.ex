defmodule MachineGun do
  @moduledoc ""

  alias MachineGun.{Supervisor, Worker, Response, Request}

  @type request_headers() :: [tuple(), ...] | []
  @type request_opts() :: [tuple(), ...] | [] | map
  @type response_or_error :: {:ok, Response.t()} | {:error, any}

  @callback head(String.t(), request_headers(), request_opts()) :: response_or_error()
  @callback get(String.t(), request_headers(), request_opts()) :: response_or_error()
  @callback post(String.t(), String.t(), request_headers(), request_opts()) :: response_or_error()
  @callback put(String.t(), String.t(), request_headers(), request_opts()) :: response_or_error()
  @callback delete(String.t(), request_headers(), request_opts()) :: response_or_error()
  @callback head!(String.t(), request_headers(), request_opts()) :: Response.t()
  @callback get!(String.t(), request_headers(), request_opts()) :: Response.t()
  @callback post!(String.t(), String.t(), request_headers(), request_opts()) :: Response.t()
  @callback put!(String.t(), String.t(), request_headers(), request_opts()) :: Response.t()
  @callback delete!(String.t(), request_headers(), request_opts()) :: Response.t()
  @callback request!(String.t(), String.t(), String.t(), request_headers(), request_opts()) ::
              Response.t()
  @callback request(String.t(), String.t(), String.t(), request_headers(), request_opts()) ::
              response_or_error()

  @default_request_timeout 5000
  @default_pool_queue true
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

    @type t :: %__MODULE__{
            request_url: String.t(),
            status_code: pos_integer(),
            headers: map(),
            body: String.t(),
            trailers: any()
          }
  end

  defmodule Request do
    defstruct [
      :method,
      :path,
      :headers,
      :body
    ]

    @type t :: %__MODULE__{
            method: String.t(),
            path: String.t(),
            headers: map(),
            body: String.t()
          }
  end

  defmodule Error do
    defexception reason: nil
    def message(%__MODULE__{reason: reason}), do: inspect(reason)
  end

  @spec head(String.t(), request_headers(), request_opts()) :: response_or_error()
  def head(url, headers \\ [], opts \\ %{}) do
    request("HEAD", url, "", headers, opts)
  end

  @spec get(String.t(), request_headers(), request_opts()) :: response_or_error()
  def get(url, headers \\ [], opts \\ %{}) do
    request("GET", url, "", headers, opts)
  end

  @spec post(String.t(), String.t(), request_headers(), request_opts()) :: response_or_error()
  def post(url, body, headers \\ [], opts \\ %{}) do
    request("POST", url, body, headers, opts)
  end

  @spec put(String.t(), String.t(), request_headers(), request_opts()) :: response_or_error()
  def put(url, body, headers \\ [], opts \\ %{}) do
    request("PUT", url, body, headers, opts)
  end

  @spec delete(String.t(), request_headers(), request_opts()) :: response_or_error()
  def delete(url, headers \\ [], opts \\ %{}) do
    request("DELETE", url, "", headers, opts)
  end

  @spec head!(String.t(), request_headers(), request_opts()) :: Response.t()
  def head!(url, headers \\ [], opts \\ %{}) do
    request!("HEAD", url, "", headers, opts)
  end

  @spec get!(String.t(), request_headers(), request_opts()) :: Response.t()
  def get!(url, headers \\ [], opts \\ %{}) do
    request!("GET", url, "", headers, opts)
  end

  @spec post!(String.t(), String.t(), request_headers(), request_opts()) :: Response.t()
  def post!(url, body, headers \\ [], opts \\ %{}) do
    request!("POST", url, body, headers, opts)
  end

  @spec put!(String.t(), String.t(), request_headers(), request_opts()) :: Response.t()
  def put!(url, body, headers \\ [], opts \\ %{}) do
    request!("PUT", url, body, headers, opts)
  end

  @spec delete!(String.t(), request_headers(), request_opts()) :: Response.t()
  def delete!(url, headers \\ [], opts \\ %{}) do
    request!("DELETE", url, "", headers, opts)
  end

  @spec request!(String.t(), String.t(), String.t(), request_headers(), request_opts()) ::
          Response.t()
  def request!(method, url, body \\ "", headers \\ [], opts \\ %{}) do
    case request(method, url, body, headers, opts) do
      {:ok, response} -> response
      {:error, %Error{reason: reason}} -> raise Error, reason: reason
    end
  end

  @spec request(String.t(), String.t(), String.t(), request_headers(), request_opts()) ::
          response_or_error()
  def request(method, url, body \\ "", headers \\ [], opts \\ %{})

  def request(method, url, body, headers, opts)
      when is_binary(url) and is_list(headers) and is_list(opts) do
    request(method, url, body, headers, opts |> Map.new())
  end

  def request(method, url, body, headers, opts)
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

        pool_queue = get_opt(opts, :pool_queue, pool_opts, @default_pool_queue)
        pool_timeout = get_opt(opts, :pool_timeout, pool_opts, @default_pool_timeout)
        request_timeout = get_opt(opts, :request_timeout, pool_opts, @default_request_timeout)

        request = %Request{
          method: method,
          path: path,
          headers: headers,
          body: body
        }

        try do
          do_request(pool, url, request, pool_queue, pool_timeout, request_timeout)
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
              |> sanitize_transport_opts()

            case ensure_pool(pool, host, port, size, max_overflow, strategy, conn_opts) do
              :ok ->
                do_request(pool, url, request, pool_queue, pool_timeout, request_timeout)

              {:error, error} ->
                {:error, %Error{reason: error}}
            end
        end

      %URI{scheme: scheme} when is_nil(scheme) or is_binary(scheme) ->
        {:error, %Error{reason: :bad_url_scheme}}

      _ ->
        {:error, %Error{reason: :bad_url}}
    end
  end

  defp get_opt(opts, key, pool_opts, default) do
    pool_default = Map.get(pool_opts, key, default)
    Map.get(opts, key, pool_default)
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
         pool_queue,
         pool_timeout,
         request_timeout
       ) do
    m_mod = Application.get_env(:machine_gun, :metrics_mod)
    m_state = if m_mod != nil, do: m_mod.queued(pool, :poolboy.status(pool), method, path)

    try do
      case :poolboy.checkout(pool, pool_queue, pool_timeout) do
        :full ->
          {:error, %Error{reason: :pool_full}}

        worker ->
          try do
            with {:ok, response} <-
                   Worker.request(worker, request, request_timeout, m_mod, m_state) do
              {:ok, %Response{response | request_url: url}}
            end
          after
            :ok = :poolboy.checkin(pool, worker)
          end
      end
    catch
      :exit, {:timeout, _} ->
        if m_state != nil, do: m_mod.queue_timeout(m_state)
        {:error, %Error{reason: :pool_timeout}}

      :exit, {{:shutdown, error}, _} ->
        {:error, %Error{reason: error}}
    end
  end

  defp sanitize_transport_opts(%{transport: :tcp} = conn_opts) do
    conn_opts
    |> Map.update(:transport_opts, [], fn opts ->
      Keyword.drop(opts, [:verify])
    end)
  end

  defp sanitize_transport_opts(conn_opts) do
    conn_opts
  end
end
