# MachineGun

HTTP client for Elixir. Based on [Gun](https://github.com/ninenines/gun) and [Poolboy](https://github.com/devinus/poolboy). Supports HTTP/1 and HTTP/2 with automatic detection. Maintains separate connection pool for each host:port combination. Drop-in replacement for [HTTPoison](https://github.com/edgurgel/httpoison).