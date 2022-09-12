defmodule Eidfs.MixProject do
  use Mix.Project

  @app :eidfs
  @version "0.1.0"
  @in_production Mix.env() == :prod

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: @in_production,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      releases: [
        eidfs: [
          overwrite: true,
          include_executables_for: [:unix],
          steps: [:assemble, :tar],
          strip_beams: @in_production
        ]
      ],
      dialyzer: [
        plt_core_path: "priv/plts",
        plt_local_path: "priv/plts",
        ignore_warnings: "config/.dialyzer_ignore.exs",
        list_unused_filters: true
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Eidfs.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.6.11"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.17.5"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.6"},
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:pest, "~> 0.9.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.19", only: [:dev, :test]},
      {:excoveralls, "~> 0.14.6", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      "assets.deploy": ["esbuild default --minify", "phx.digest"],
      "app.name": [
        ~s/run -e "Mix.Project.get().project() |> Keyword.get(:app) |> IO.puts()" --no-compile --no-start/
      ],
      "app.version": [
        ~s/run -e "Application.loaded_applications() |> Enum.find({nil, nil, ''}, &match?({_, '#{@app}', _}, &1)) |> elem(2) |> IO.puts()" --no-compile --no-start/
      ],
      "elixir.version": [
        ~s/run -e 'IO.puts(System.version())' --no-compile --no-mix-exs --no-start --no-elixir-version-check/
      ],
      "erlang.version": [
        ~s/run -e ':file.read_file(:filename.join([:code.root_dir(), "releases", :erlang.system_info(:otp_release), "OTP_VERSION"])) |> elem(1) |> String.trim_trailing("\n") |> IO.puts()' --no-compile --no-mix-exs --no-start --no-elixir-version-check/
      ],
      "erts.version": [
        ~s/run -e ':erlang.system_info(:version) |> IO.puts()' --no-compile --no-mix-exs --no-start --no-elixir-version-check/
      ]
    ]
  end
end
