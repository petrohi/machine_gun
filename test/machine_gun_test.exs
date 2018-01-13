defmodule MachineGunTest do
  use ExUnit.Case
  doctest MachineGun

  test "greets the world" do
    assert MachineGun.hello() == :world
  end
end
