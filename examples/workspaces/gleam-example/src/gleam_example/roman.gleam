//// Roman numerals, both ways. Pure functions — the router and the tests both
//// call these directly.

import gleam/int
import gleam/result
import gleam/string

pub type RomanError {
  /// Roman numerals (without the overline extension) only cover 1..3999.
  OutOfRange(value: Int)
  /// Not a numeral at all, or not written the standard way ("IIII", "IC", "VX").
  NotRoman(text: String)
}

const numerals = [
  #(1000, "M"),
  #(900, "CM"),
  #(500, "D"),
  #(400, "CD"),
  #(100, "C"),
  #(90, "XC"),
  #(50, "L"),
  #(40, "XL"),
  #(10, "X"),
  #(9, "IX"),
  #(5, "V"),
  #(4, "IV"),
  #(1, "I"),
]

pub fn to_roman(value: Int) -> Result(String, RomanError) {
  case value >= 1 && value <= 3999 {
    False -> Error(OutOfRange(value))
    True -> Ok(encode(value, numerals, ""))
  }
}

fn encode(value: Int, table: List(#(Int, String)), acc: String) -> String {
  case table {
    [] -> acc
    [#(n, symbol), ..] if value >= n -> encode(value - n, table, acc <> symbol)
    [_, ..rest] -> encode(value, rest, acc)
  }
}

/// Case-insensitive. Only the standard (canonical) spelling is accepted: the
/// text is decoded greedily, then re-encoded, and the two must match.
pub fn from_roman(text: String) -> Result(Int, RomanError) {
  let upper = string.uppercase(string.trim(text))
  let value = decode(upper, numerals, 0)
  case value > 0 && to_roman(value) == Ok(upper) {
    True -> Ok(value)
    False -> Error(NotRoman(text))
  }
}

fn decode(text: String, table: List(#(Int, String)), acc: Int) -> Int {
  case text, table {
    "", _ -> acc
    _, [] -> -1
    _, [#(n, symbol), ..rest] ->
      case string.starts_with(text, symbol) {
        True ->
          decode(string.drop_start(text, string.length(symbol)), table, acc + n)
        False -> decode(text, rest, acc)
      }
  }
}

/// What the /roman/:value route does: a number converts to Roman, anything
/// else is read as a Roman numeral. Returns #(arabic, roman).
pub fn convert(input: String) -> Result(#(Int, String), RomanError) {
  case int.parse(string.trim(input)) {
    Ok(n) -> to_roman(n) |> result.map(fn(roman) { #(n, roman) })
    Error(_) -> {
      use n <- result.map(from_roman(input))
      #(n, string.uppercase(string.trim(input)))
    }
  }
}

pub fn describe_error(error: RomanError) -> String {
  case error {
    OutOfRange(n) ->
      int.to_string(n) <> " is out of range: Roman numerals cover 1 to 3999"
    NotRoman(text) ->
      "'" <> text <> "' is neither a whole number nor a standard Roman numeral"
  }
}
