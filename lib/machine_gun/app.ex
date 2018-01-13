defmodule MachineGun.Application do
  @moduledoc ""

  alias MachineGun.Supervisor

  use Application

  def start(_type, _args) do
    Supervisor.start_link([])
  end
end
