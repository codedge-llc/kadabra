defmodule Kadabra.Mixfile do
  use Mix.Project

  @version "0.6.2"

  def project do
    [
      app: :kadabra,
      build_embedded: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.6",
      elixirc_options: [warnings_as_errors: true],
      name: "Kadabra",
      package: package(),
      source_url: "https://github.com/codedge-llc/kadabra",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      version: @version
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {Kadabra.Application, []}
    ]
  end

  defp description do
    """
    HTTP2 client for Elixir
    """
  end

  defp deps do
    [
      {:certifi, "~> 2.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.7", only: :test, runtime: false},
      {:hpack, "~> 0.3.0", hex: :hpack_erl}
    ]
  end

  defp docs do
    [
      main: "Kadabra",
      extras: [
        "CHANGELOG.md"
      ]
    ]
  end

  defp dialyzer do
    [
      ignore_warnings: "config/dialyzer.ignore-warnings",
      plt_add_deps: true,
      plt_add_apps: [:ssl],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/codedge-llc/kadabra"},
      maintainers: ["Henry Popp"]
    ]
  end
end
