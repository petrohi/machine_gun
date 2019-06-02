defmodule MachineGun.Supervisor do
  @moduledoc ""

  alias MachineGun.{Worker}

  use Supervisor

  def start_link([]) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Supervisor.init(
      [
        Supervisor.child_spec(%{start: {:poolboy, :start_link, []}}, restart: :permanent, id: nil)
      ],
      strategy: :simple_one_for_one,
      max_restarts: 10
    )
  end

  def start(name, host, port, size, max_overflow, strategy, conn_opts) do
    Supervisor.start_child(MachineGun.Supervisor, [
      [
        name: {:local, name},
        worker_module: Worker,
        size: size,
        max_overflow: max_overflow,
        strategy: strategy
      ],
      [
        host |> String.to_charlist(),
        port,
        conn_opts
      ]
    ])
  end
end
