defmodule Kadabra.Mixfile do
  use Mix.Project

  @version "0.5.0"

  def project do
    [
      app: :kadabra,
      build_embedded: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      dialyzer: [
        plt_add_deps: true,
        plt_add_apps: [:ssl],
        ignore_warnings: "config/dialyzer.ignore-warnings"
      ],
      docs: [
        main: "Kadabra",
        extras: [
          "CHANGELOG.md"
        ]
      ],
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

  defp description do
    """
    HTTP2 client for Elixir
    """
  end

  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.19", only: :dev},
      {:excoveralls, "~> 0.7", only: :test},
      {:hpack, "~> 0.2.3", hex: :hpack_erl}
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
