defmodule Kadabra.Mixfile do
  use Mix.Project

  @source_url "https://github.com/codedge-llc/kadabra"
  @version "0.6.0"

  def project do
    [
      app: :kadabra,
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      version: @version,
      elixir: "~> 1.6",
      name: "Kadabra",
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env(),
      elixirc_options: [warnings_as_errors: true]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {Kadabra.Application, []}
    ]
  end

  defp deps do
    [
      {:certifi, "~> 2.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.7", only: :test, runtime: false},
      {:hpack, "~> 0.2.3", hex: :hpack_erl}
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
      description: "HTTP2 client for Elixir.",
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE.md"
      ],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/kadabra/changelog.html",
        "GitHub" => @source_url
      },
      maintainers: ["Henry Popp"]
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md",
        "CONTRIBUTING.md": [title: "Contributing"],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp preferred_cli_env do
    [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  end
end
