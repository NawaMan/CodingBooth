//// A command-line client for the server's /roman/:value route.
////
////   gleam run -m gleam_example/client                 # converts 2026
////   gleam run -m gleam_example/client -- XIV 1999 4000
////
//// The server is http://localhost:8000 unless SERVER_URL says otherwise.
//// Exits 1 if any input was rejected, 2 if the server could not be reached.

import argv
import envoy
import gleam/dynamic/decode
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/uri

pub const default_server = "http://localhost:8000"

pub const default_input = "2026"

/// What the server said about one input.
pub type Outcome {
  Converted(arabic: Int, roman: String)
  Rejected(reason: String)
}

pub fn main() -> Nil {
  let inputs = case argv.load().arguments {
    [] -> [default_input]
    given -> given
  }
  let server = envoy.get("SERVER_URL") |> result.unwrap(default_server)

  io.println("Roman numerals, converted by " <> server)
  let outcomes =
    list.map(inputs, fn(input) {
      case fetch(server, input) {
        Ok(outcome) -> #(input, outcome)
        Error(problem) -> {
          io.println_error("✗ " <> problem)
          io.println_error(case server == default_server {
            True -> "  Is the server running? Start it with: just start"
            False -> "  Is SERVER_URL right, and is a server listening there?"
          })
          halt(2)
          #(input, Rejected(problem))
        }
      }
    })

  let width =
    list.fold(inputs, 0, fn(widest, input) {
      int.max(widest, string.length(input))
    })
  list.each(outcomes, fn(pair) {
    io.println(format_line(pair.0, pair.1, width))
  })

  case list.any(outcomes, fn(pair) { is_rejected(pair.1) }) {
    True -> halt(1)
    False -> Nil
  }
}

/// One output line, with the input column padded to `width`. Pure, so the
/// tests can check the exact text.
pub fn format_line(input: String, outcome: Outcome, width: Int) -> String {
  case outcome {
    Converted(arabic, roman) -> {
      // Show the side the user did not type.
      let answer = case int.parse(string.trim(input)) {
        Ok(_) -> roman
        Error(_) -> int.to_string(arabic)
      }
      "  " <> string.pad_end(input, width, " ") <> "  →  " <> answer
    }
    Rejected(reason) ->
      "  " <> string.pad_end(input, width, " ") <> "  ✗  " <> reason
  }
}

/// Decode the server's JSON body: success and error responses have different shapes.
pub fn decode_outcome(body: String) -> Result(Outcome, Nil) {
  let converted = {
    use arabic <- decode.field("arabic", decode.int)
    use roman <- decode.field("roman", decode.string)
    decode.success(Converted(arabic, roman))
  }
  let rejected = {
    use reason <- decode.field("error", decode.string)
    decode.success(Rejected(reason))
  }
  json.parse(body, decode.one_of(converted, [rejected]))
  |> result.replace_error(Nil)
}

fn fetch(server: String, input: String) -> Result(Outcome, String) {
  let url = server <> "/roman/" <> uri.percent_encode(input)
  use req <- result.try(
    request.to(url) |> result.replace_error("not a valid URL: " <> url),
  )
  use response <- result.try(
    httpc.send(req) |> result.replace_error("could not reach " <> server),
  )
  decode_outcome(response.body)
  |> result.replace_error(
    "unexpected reply from "
    <> url
    <> " (HTTP "
    <> int.to_string(response.status)
    <> ")",
  )
}

fn is_rejected(outcome: Outcome) -> Bool {
  case outcome {
    Rejected(_) -> True
    Converted(..) -> False
  }
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil
