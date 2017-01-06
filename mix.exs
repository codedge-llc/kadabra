defmodule Kadabra.Mixfile do
  use Mix.Project

  def project do
    [
      app: :kadabra,
      version: "0.1.2",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps,
      package: package,
      name: "Kadabra",
      description: description,
      source_url: "https://github.com/codedge-llc/kadabra",
      docs: [main: "readme",
             extras: ["README.md"]]
    ]
  end

  def application do
    [applications: [:logger]]
  end

  defp description do
    """
      HTTP/2 client for Elixir 
    """
  end

  defp deps do
    [
      {:ex_doc, "~> 0.14", only: :dev},
      {:dogma, "~> 0.1", only: :dev},
      {:hpack, "~> 1.0.0"}
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
