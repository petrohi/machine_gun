[![Hex.pm version](https://img.shields.io/hexpm/v/machine_gun.svg)](https://hex.pm/packages/machine_gun)
[![Hex.pm downloads](https://img.shields.io/hexpm/dt/machine_gun.svg)](https://hex.pm/packages/machine_gun)
[![Build Status](https://travis-ci.org/petrohi/machine_gun.svg?branch=master)](https://travis-ci.org/petrohi/machine_gun)

# MachineGun

HTTP client for Elixir. Based on [Gun](https://github.com/ninenines/gun) and [Poolboy](https://github.com/devinus/poolboy).

* Supports HTTP/1 and HTTP/2 with automatic detection;
* Maintains separate connection pool for each pool_group:host:port combination;
* Allows per-pool configuration;
* Drop-in replacement for [HTTPoison](https://github.com/edgurgel/httpoison).

## Example

```
%MachineGun.Response{body: body, status_code: 200} =
  MachineGun.post!(
    "https://httpbin.org/anything",
    "{\"hello\":\"world!\"}",
    [{"content-type", "application/json"}, {"accept", "application/json"}],
    %{pool_queue: true, pool_timeout: 1000, request_timeout: 5000, pool_group: :default})
```

Options are included to show defaults and can be omitted. `pool_queue`, `pool_timeout` and `request_timeout` default to values specified in pool group configuration. If not specified in pool group configuration they default to the values in the example.

## Configuration

```
config :machine_gun,
  # Default pool group
  default: %{
    pool_size: 4,         # Poolboy size
    pool_max_overflow: 4, # Poolboy max_overflow
    pool_queue: true,     # Queue requests if no workers are available in the pool. If `false` request will fail immediately if all workers are busy
    pool_timeout: 1000,
    request_timeout: 5000,
    conn_opts: %{}        # Gun connection options
  }
```

Configuration example shows defaults and can be omitted. See [Poolboy options](https://github.com/devinus/poolboy#options) documentation for explanation of  `pool_size` and `pool_max_overflow`. See [Gun manual](https://ninenines.eu/docs/en/gun/1.3/manual/gun/) for explanation of `conn_opts`.

## Notes

* When using MachineGun in a long-living process (for example genserver) make sure to handle messages in the form of `{ref, _}` tuples, which may be produced by pool [timeouts](https://hexdocs.pm/elixir/GenServer.html#call/3-timeouts).
* When using MachineGun with HTTP/2 and modern HTTP/1 servers we recommend using lowercase header names. For example `content-type`.
* MachineGun may timeout when request with empty body contains `content-type` header and does not contain `content-length` header. See [this issue](https://github.com/ninenines/gun/issues/141) for details.
