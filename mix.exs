defmodule StatsAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :stats_agent,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_gen_socket_client, "~> 2.1.1"},
      {:websocket_client, "~> 1.2"},
      {:poison, "~> 2.0"},
      {:recon, "~> 2.3.6"},
      {:scribe, "~> 0.8"}
    ]
  end
end
