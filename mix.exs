defmodule Automator.MixProject do
  use Mix.Project

  def project do
    [
      app: :automator,
      version: "0.1.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: "Chrome DevTools Protocol scraper for Elixir",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:websockex, "~> 0.5"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:typed_struct, "~> 0.3"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/lambdachad/automator"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: "https://github.com/lambdachad/automator",
      groups_for_modules: [
        "High-Level API": [
          Automator.Scraper
        ],
        "Low-Level API": [
          Automator.Chromium,
          Automator.Client
        ],
        Entrypoint: [
          Automator
        ]
      ]
    ]
  end
end
