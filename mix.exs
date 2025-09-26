defmodule Kadabra.Mixfile do
  use Mix.Project

  @source_url "https://github.com/codedge-llc/scribe"
  @version "0.6.1"

  def project do
    [
      app: :kadabra,
      build_embedded: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.6",
      elixirc_options: [warnings_as_errors: true],
      name: "Kadabra",
      package: package(),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      source_url: "https://github.com/codedge-llc/kadabra",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      version: @version
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
      {:hpack, "~> 0.3.0", hex: :hpack_erl}
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md",
        LICENSE: [title: "License"]
      ],
      formatters: ["html"],
      main: "Kadabra",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp dialyzer do
    [
      # ignore_warnings: "config/dialyzer.ignore-warnings",
      # plt_add_deps: true,
      # plt_add_apps: [:ssl],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp package do
    [
      description: "HTTP/2 client for Elixir.",
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/kadabra/changelog.html",
        "GitHub" => "https://github.com/codedge-llc/kadabra",
        "Sponsor" => "https://github.com/sponsors/codedge-llc"
      },
      maintainers: ["Henry Popp"]
    ]
  end
end
