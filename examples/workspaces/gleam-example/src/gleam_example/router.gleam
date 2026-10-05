//// Every route of the service. Pure request -> response, so the tests can drive
//// it directly with wisp/simulate, no socket involved.

import gleam/http.{Get, Post}
import gleam/json
import gleam/string
import gleam_example/roman
import wisp.{type Request, type Response}

pub fn handle_request(req: Request) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes

  case wisp.path_segments(req) {
    [] -> home(req)
    ["greet", name] -> greet(req, name)
    ["reverse"] -> reverse(req)
    ["roman", value] -> roman_route(req, value)
    _ -> wisp.not_found()
  }
}

fn home(req: Request) -> Response {
  use <- wisp.require_method(req, Get)
  wisp.html_response(
    "<h1>Hello from Gleam!</h1>"
      <> "<p>Try <a href=\"/greet/booth\">/greet/booth</a>, "
      <> "<a href=\"/roman/2026\">/roman/2026</a>, "
      <> "<a href=\"/roman/MMXXVI\">/roman/MMXXVI</a>, "
      <> "or POST some text to <code>/reverse</code>.</p>",
    200,
  )
}

fn greet(req: Request, name: String) -> Response {
  use <- wisp.require_method(req, Get)
  json.object([#("greeting", json.string(greeting(name)))])
  |> json.to_string
  |> wisp.json_response(200)
}

fn reverse(req: Request) -> Response {
  use <- wisp.require_method(req, Post)
  use body <- wisp.require_string_body(req)
  wisp.ok() |> wisp.string_body(string.reverse(body))
}

/// A whole number converts to Roman, anything else is read as a Roman numeral.
/// 200 {"input", "arabic", "roman"} on success, 400 {"input", "error"} otherwise.
fn roman_route(req: Request, value: String) -> Response {
  use <- wisp.require_method(req, Get)
  case roman.convert(value) {
    Ok(#(arabic, numeral)) ->
      json.object([
        #("input", json.string(value)),
        #("arabic", json.int(arabic)),
        #("roman", json.string(numeral)),
      ])
      |> json.to_string
      |> wisp.json_response(200)
    Error(error) ->
      json.object([
        #("input", json.string(value)),
        #("error", json.string(roman.describe_error(error))),
      ])
      |> json.to_string
      |> wisp.json_response(400)
  }
}

/// The one bit of logic worth unit-testing on its own.
pub fn greeting(name: String) -> String {
  case string.trim(name) {
    "" -> "Hello, stranger!"
    trimmed -> "Hello, " <> trimmed <> "!"
  }
}
