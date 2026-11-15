# AWS Env-Credentials Example

This example is a booth that talks to AWS with credentials taken **only from environment
variables**. No `~/.aws` file is mounted or seeded. It is the setup a CI runner usually has (GitHub
Actions secrets, a pipeline's injected keys), and the counterpart of
[aws-example](../aws-example/), which seeds your host's `~/.aws` files instead.

It uses the `aws-cli+env` extension, with the file-based `credential` extension switched off:

```bash
booth config --no-tui --select 'aws-cli+env~credential'
```

For all three ways to give a booth AWS credentials (files, environment, EnvFolio) side by side,
see the [AWS in a Booth](../../../docs/demos/aws/README.md) walkthrough.

## Table of Contents

- [What reaches the booth](#what-reaches-the-booth)
- [Quick Start](#quick-start)
- [Keys from EnvFolio](#keys-from-envfolio)
- [Using it with your ~/.aws files](#using-it-with-your-aws-files)
- [Combining with the file method](#combining-with-the-file-method)
- [Tests](#tests)
- [Security Notes](#security-notes)

## What reaches the booth

`.booth/config.toml` passes these variables through **by name**:

| Variable | Needed | Meaning |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | yes | access key |
| `AWS_SECRET_ACCESS_KEY` | yes | secret key |
| `AWS_REGION` or `AWS_DEFAULT_REGION` | yes (one) | region; `AWS_REGION` wins if both are set |
| `AWS_SESSION_TOKEN` | only for temporary keys | from SSO, `aws sts assume-role`, or an OIDC role in CI |

A variable that is not set on the host is left out, not passed empty. The values are never written
to a file in the project, so nothing secret is committed.

`AWS_PROFILE` is not passed: it names a profile in `~/.aws/config`, and this booth has no such file.

## Quick Start

**Prerequisites:** the variables above exported in the shell you start the booth from.

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1

cd examples/workspaces/aws-env-example
just check               # ./check-connection.sh - OK when the booth can reach AWS
just whoami              # aws sts get-caller-identity
just config              # aws configure list - the TYPE column says "env"
just version             # aws --version - the only recipe that needs no credentials
```

No `just` on the host? `./booth exec --run -- just check` does the same, and plain `./booth` opens
a shell.

A recipe runs in this project's booth if one is already running, and that booth keeps the
variables it was started with. If `just check` fails although your shell has them, stop the
running booth (`./booth stop`) and try again.

## Keys from EnvFolio

[EnvFolio](https://github.com/NawaMan/EnvFolio) keeps the keys in an encrypted store and sets them
as environment variables for one command, which is what this booth reads. Store them once:

```bash
folio insert secret aws/access-key-id        # -> AWS_ACCESS_KEY_ID
folio insert secret aws/secret-access-key    # -> AWS_SECRET_ACCESS_KEY
folio insert text   aws/region               # -> AWS_REGION
```

then run any command through `folio exec` (`-s` includes secrets; `-n` instead shows the
variable names without unlocking anything):

```bash
folio exec -s aws -- just check
folio exec -s aws -- ./booth -- aws s3 ls
```

Already exporting `AWS_REGION` in your shell profile? Then the two secrets are enough.

## Using it with your ~/.aws files

If your keys live in `~/.aws/credentials` (the method [aws-example](../aws-example/) uses), you can
still try this example by lifting them into the environment for one command. AWS CLI v2 prints
them as `export` lines (with `AWS_SESSION_TOKEN` too, for SSO or role profiles):

```bash
( eval "$(aws configure export-credentials --format env)"
  export AWS_REGION=$(aws configure get region)
  just check )
```

## Combining with the file method

The two extensions work together. Select both and the booth works on a machine that has either:

```bash
booth config --no-tui --select 'aws-cli+env'      # credential (the files) stays auto-selected
```

The AWS CLI reads each setting from the environment first and falls back to the files, so where
both are present the environment variables win.

## Tests

`.cb-tests/test001-aws-env--on-host.sh` starts the booth and checks, inside it, that there are no
`~/.aws` files, that `aws configure list` reports the keys and region as coming from `env`, and that
`aws sts get-caller-identity` succeeds.

On a host without the variables it is **skipped**, not failed: `.cb-tests/requires-env.txt` lists
what it needs, and `run-example-tests.sh` reports the example as `SKIPPED`.

```bash
examples/workspaces/run-example-tests.sh --example aws-env-example
```

## Security Notes

| Aspect | Notes |
|---|---|
| Version control | No credential is in any project file |
| Container environment | **Visible.** The values are in the container's environment, so `docker inspect` on the booth shows them, and every process in the booth can read them |
| Scope | Anything running in the booth (you, a script, an agent) acts with the keys' full permissions. Use a narrowly scoped IAM user or role, not admin or root keys |
| Teardown | The container, and the variables with it, is removed when a default run ends |
