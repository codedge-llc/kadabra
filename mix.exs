defmodule Kadabra.Mixfile do
  use Mix.Project

  def project do
    [
      app: :kadabra,
      version: "0.3.0",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      package: package(),
      name: "Kadabra",
      description: description(),
      source_url: "https://github.com/codedge-llc/kadabra",
      docs: [main: "readme",
             extras: ["README.md"]],
      dialyzer: [plt_add_deps: true, plt_add_apps: [:ssl]]
    ]
  end

  def application do
    [
      applications: [:logger, :hpack],
      mod: {Kadabra.Application, []}
    ]
  end

  defp description do
    """
    HTTP/2 client for Elixir
    """
  end

  defp deps do
    [
      {:hpack, "~> 0.2.3", hex: :hpack_erl},
      {:scribe, "~> 0.4"},
      {:ex_doc, "~> 0.14", only: :dev},
      {:dogma, "~> 0.1", only: :dev},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
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
