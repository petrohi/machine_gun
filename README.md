# MachineGun

HTTP client for Elixir. Based on [Gun](https://github.com/ninenines/gun) and [Poolboy](https://github.com/devinus/poolboy). Supports HTTP/1 and HTTP/2 with automatic detection. Maintains separate connection pool for each host:port combination. Drop-in replacement for [HTTPoison](https://github.com/edgurgel/httpoison).

## Example

```
%MachineGun.Response{body: body, status_code: 200} =
  MachineGun.get!(
    "http://icanhazip.com", [{"accept", "text/plain"}],
    %{request_timeout: 5000, pool_group: :default})
```

## Configuration

```
config :machine_gun,
  default: %{
    pool_size: 4,         # Poolboy size [1]
    pool_max_overflow: 4, # Poolboy max_overflow [1]
    pool_timeout: 1000,
    conn_opts: %{}        # Gun connection options [2]
  }
```

 1. https://github.com/devinus/poolboy#options
 2. https://ninenines.eu/docs/en/gun/1.0/manual/gun/
