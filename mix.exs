defmodule MyMicropub.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_micropub,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MyMicropub.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.5"},
      {:plug_micropub, github: "bismark/plug_micropub"},
      {:cowboy, "~> 2.3"},
      {:jason, "~> 1.1"},
      {:httpoison, "~> 1.2"},
      {:exsync, "~> 0.2.3", only: :dev},
      {:elixir_uuid, "~> 1.2"},
      {:floki, "~> 0.20.3"}
    ]
  end
end
