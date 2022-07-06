defmodule DCache.MixProject do
	use Mix.Project

	@version "0.0.1"

	def project do
		[
			app: :dcache,
			deps: deps(),
			version: @version,
			elixir: "~> 1.13",
			start_permanent: Mix.env() == :prod,
			elixirc_paths: elixirc_paths(Mix.env())
			description: "A simple caching library",
			package: [
				licenses: ["MIT"],
				links: %{
					"git" => "https://github.com/karlseguin/dcache"
				},
				maintainers: ["Karl Seguin"],
			],
		]
	end

	def application do
		[
			extra_applications: [:logger]
		]
	end

	defp elixirc_paths(:test), do: ["lib", "test"]
	defp elixirc_paths(_), do: ["lib"]

	defp deps do
		[
			{:ex_doc, "~> 0.28.4", only: :dev, runtime: false}
		]
	end
end
