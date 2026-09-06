# Floci Example

This example is a booth that runs [Floci](https://floci.io) — a free, MIT-licensed local AWS
emulator — next to the AWS CLI, so `aws s3 mb` talks to `localhost:4566` instead of a real
account. No cloud credentials, no auth token, no LocalStack community-edition sunset. The
emulator starts with the booth (`floci+autostart`, which pulls in Docker-in-Docker because
`floci start` launches the `floci/floci` container), dummy AWS keys are already in the
environment, and `just run` creates a bucket, puts a file, and reads it back. That is the
whole point: a local AWS you can hand to an agent or a teammate without a billing risk.

**Stack:** Floci CLI + AWS CLI + Docker-in-Docker, port 4566

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/floci-example
booth

# 2. Inside the booth — create a bucket and round-trip a file
just --list
just run                 # ./demo.sh
```

From the host, the same endpoint is published on port 4566 (`+expose`), so an SDK on your
laptop can point at `http://localhost:4566` too.

## What to try

Floci is already running and the shell already has dummy AWS keys. Type these yourself — they
are ordinary AWS CLI commands, aimed at the local emulator:

```bash
aws s3 mb s3://my-bucket

echo "hello from floci" > hello.txt
aws s3 cp hello.txt s3://my-bucket/hello.txt

aws s3 ls s3://my-bucket/
aws s3 cp s3://my-bucket/hello.txt -
```

The last line should print `hello from floci`. Change the file, upload it again, and read it
back — the object in the bucket is real state in the emulator, not a mock.

`just run` does the same round-trip as a script (`s3://codingbooth-demo`). Either path is
fine; the typed commands are how you would actually use Floci in a project.

## What's included

| Component     | Details                                              |
|---------------|------------------------------------------------------|
| Emulator      | Floci AWS (port 4566, LocalStack-compatible)         |
| CLI           | `floci` (start/stop/wait/env) and `aws`              |
| Docker        | DinD sidecar, required by `floci start`              |
| Persistence   | Named volume `booth-flocidata` → `~/.floci`          |
| Sample        | `demo.sh` — create a bucket and round-trip a file    |

The dummy keys (`test` / `test`) are exported in every login shell. They are accepted by
Floci and never billed.

Select a different CLI version with `FLOCI_VERSION`, or a different listen port with
`FLOCI_PORT`, via `booth config`.
