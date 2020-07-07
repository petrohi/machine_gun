defmodule MachineGun.Supervisor do
  @moduledoc ""

  alias MachineGun.{Worker}

  use DynamicSupervisor

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 10)
  end

  def start(name, host, port, size, max_overflow, strategy, conn_opts) do
    DynamicSupervisor.start_child(
      MachineGun.Supervisor,
      Supervisor.child_spec(
        %{
          start:
            {:poolboy, :start_link,
             [
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
             ]}
        },
        restart: :permanent,
        id: nil
      )
    )
  end
end
