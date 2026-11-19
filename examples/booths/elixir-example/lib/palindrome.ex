defmodule Palindrome do
  @moduledoc """
  Palindrome Checker - Check if a word or phrase reads the same forwards and backwards.

  Examples: "racecar", "A man a plan a canal Panama"
  """

  @doc """
  Checks if the given string is a palindrome.
  Ignores case and non-alphanumeric characters.
  """
  def check?(text) when is_binary(text) do
    normalized = normalize(text)
    normalized == String.reverse(normalized)
  end

  @doc """
  Normalizes text by removing non-alphanumeric characters and lowercasing.
  """
  def normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "")
  end

  @doc """
  Returns a formatted result message.
  """
  def format_result(text) do
    is_palindrome = check?(text)
    status = if is_palindrome, do: "IS", else: "is NOT"
    "\"#{text}\" #{status} a palindrome"
  end
end

defmodule Palindrome.CLI do
  def main(args) do
    case args do
      [] ->
        IO.puts("Palindrome Checker")
        IO.puts("")
        IO.puts("Check if a word or phrase reads the same forwards and backwards.")
        IO.puts("Ignores spaces, punctuation, and capitalization.")
        IO.puts("")
        IO.puts("Usage: palindrome <text>")
        IO.puts("")
        IO.puts("Examples:")
        IO.puts("  palindrome racecar")
        IO.puts("  palindrome \"A man a plan a canal Panama\"")
        IO.puts("  palindrome hello")

      _ ->
        text = Enum.join(args, " ")
        IO.puts(Palindrome.format_result(text))
    end
  end
end
