//// Entry point: serve the router on 0.0.0.0:8000 until the process is stopped.

import gleam/erlang/process
import gleam_example/router
import mist
import wisp
import wisp/wisp_mist

pub const port = 8000

pub fn main() -> Nil {
  wisp.configure_logger()

  // Only signs cookies, which this service never sets — a per-run value is enough.
  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request, secret_key_base)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(port)
    |> mist.start

  process.sleep_forever()
}
