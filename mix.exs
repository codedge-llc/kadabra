defmodule Kadabra.Mixfile do
  use Mix.Project

  @version "0.6.2"
  @source_url "https://github.com/codedge-llc/kadabra"

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
      source_url: @source_url,
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl]
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
      plt_add_apps: [:ssl],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Henry Popp"]
    ]
  end
end
