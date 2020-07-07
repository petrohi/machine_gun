defmodule MachineGun.Application do
  @moduledoc ""

  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [{DynamicSupervisor, strategy: :one_for_one, name: MachineGun.Supervisor}],
      strategy: :one_for_one
    )
  end
end
