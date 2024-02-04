defmodule ExMobileDevice.MixProject do
  use Mix.Project

  def project do
    [
      app: :exmobiledevice,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "ExMobileDevice",
      source_url: "https://github.com/ausimian/exmobildevice",
      docs: [
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssl, :tools],
      mod: {ExMobileDevice.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gen_state_machine, "~> 3.0.0"},
      {:plist, "~> 0.0.7"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:typed_struct, "~> 0.3.0", runtime: false},
      {:credo, "~> 1.7.3", only: [:dev], runtime: false}
    ]
  end
end
