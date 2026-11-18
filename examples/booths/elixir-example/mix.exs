defmodule Palindrome.MixProject do
  use Mix.Project

  def project do
    [
      app: :palindrome,
      version: "0.1.0",
      elixir: "~> 1.14",
      escript: [main_module: Palindrome.CLI]
    ]
  end
end
