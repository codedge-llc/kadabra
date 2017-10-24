defmodule Kadabra.Mixfile do
  use Mix.Project

  def project do
    [
      app: :kadabra,
      version: "0.3.2",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      consolidate_protocols: Mix.env != :test,
      deps: deps(),
      package: package(),
      name: "Kadabra",
      description: description(),
      source_url: "https://github.com/codedge-llc/kadabra",
      docs: [main: "readme",
             extras: ["README.md"]],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "coveralls": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_deps: true,
        plt_add_apps: [:ssl],
        ignore_warnings: "config/dialyzer.ignore-warnings"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
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
      {:hpack, "~> 0.2.3", hex: :hpack_erl},
      {:scribe, "~> 0.4", optional: true},
      {:ex_doc, "~> 0.14", only: :dev},
      {:dogma, "~> 0.1", only: :dev},
      {:excoveralls, "~> 0.7", only: :test},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
       files: ["lib", "mix.exs", "README*", "LICENSE*"],
       maintainers: ["Henry Popp"],
       licenses: ["MIT"],
       links: %{"GitHub" => "https://github.com/codedge-llc/kadabra"}
    ]
  end
end
