defmodule MachineGun.Mixfile do
  use Mix.Project

  def project do
    [
      app: :machine_gun,
      version: "0.1.7",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      lockfile: "mix.lock",
      name: "Machine Gun",
      description: "HTTP/1 and HTTP/2 client for Elixir. Based on Gun and Poolboy.",
      source_url: "https://github.com/petrohi/machine_gun"
    ]
  end

  defp package do
    %{
      licenses: ["ISC License"],
      maintainers: ["Peter Hizalev"],
      links: %{"GitHub" => "https://github.com/petrohi/machine_gun"}
    }
  end

  def application do
    [
      mod: {MachineGun.Application, []}
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:gun, "~> 1.3"},
      {:poolboy, "~> 1.5"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
