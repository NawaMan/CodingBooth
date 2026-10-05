import gleam/http.{Get, Post}
import gleam_example/client
import gleam_example/roman
import gleam_example/router
import gleeunit
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn greeting_test() {
  assert router.greeting("booth") == "Hello, booth!"
  assert router.greeting("  ") == "Hello, stranger!"
}

pub fn home_test() {
  let response = router.handle_request(simulate.browser_request(Get, "/"))
  assert response.status == 200
}

pub fn greet_test() {
  let response =
    router.handle_request(simulate.browser_request(Get, "/greet/gleam"))
  assert response.status == 200
  assert simulate.read_body(response) == "{\"greeting\":\"Hello, gleam!\"}"
}

pub fn reverse_test() {
  let response =
    simulate.browser_request(Post, "/reverse")
    |> simulate.string_body("gleam")
    |> router.handle_request
  assert response.status == 200
  assert simulate.read_body(response) == "maelg"
}

pub fn not_found_test() {
  let response = router.handle_request(simulate.browser_request(Get, "/nope"))
  assert response.status == 404
}

// --- Roman numerals: the pure module ----------------------------------------

pub fn to_roman_test() {
  assert roman.to_roman(2026) == Ok("MMXXVI")
  assert roman.to_roman(1994) == Ok("MCMXCIV")
  assert roman.to_roman(3999) == Ok("MMMCMXCIX")
  assert roman.to_roman(0) == Error(roman.OutOfRange(0))
  assert roman.to_roman(4000) == Error(roman.OutOfRange(4000))
}

pub fn from_roman_test() {
  assert roman.from_roman("MMXXVI") == Ok(2026)
  assert roman.from_roman("xiv") == Ok(14)
  // Non-standard spellings are rejected, not guessed at.
  assert roman.from_roman("IIII") == Error(roman.NotRoman("IIII"))
  assert roman.from_roman("IC") == Error(roman.NotRoman("IC"))
  assert roman.from_roman("hello") == Error(roman.NotRoman("hello"))
}

// --- Roman numerals: the route ----------------------------------------------

pub fn roman_route_number_test() {
  let response =
    router.handle_request(simulate.browser_request(Get, "/roman/2026"))
  assert response.status == 200
  assert simulate.read_body(response)
    == "{\"input\":\"2026\",\"arabic\":2026,\"roman\":\"MMXXVI\"}"
}

pub fn roman_route_numeral_test() {
  let response =
    router.handle_request(simulate.browser_request(Get, "/roman/mcmxciv"))
  assert response.status == 200
  assert simulate.read_body(response)
    == "{\"input\":\"mcmxciv\",\"arabic\":1994,\"roman\":\"MCMXCIV\"}"
}

pub fn roman_route_rejects_test() {
  let response =
    router.handle_request(simulate.browser_request(Get, "/roman/4000"))
  assert response.status == 400
}

// --- The CLI client: decoding and formatting (no network) --------------------

pub fn client_decodes_both_shapes_test() {
  assert client.decode_outcome(
      "{\"input\":\"14\",\"arabic\":14,\"roman\":\"XIV\"}",
    )
    == Ok(client.Converted(14, "XIV"))
  assert client.decode_outcome("{\"input\":\"x\",\"error\":\"nope\"}")
    == Ok(client.Rejected("nope"))
  assert client.decode_outcome("<html>") == Error(Nil)
}

pub fn client_formats_lines_test() {
  // A number shows its numeral, a numeral shows its number.
  assert client.format_line("2026", client.Converted(2026, "MMXXVI"), 6)
    == "  2026    →  MMXXVI"
  assert client.format_line("MMXXVI", client.Converted(2026, "MMXXVI"), 6)
    == "  MMXXVI  →  2026"
  assert client.format_line("0", client.Rejected("out of range"), 1)
    == "  0  ✗  out of range"
}
