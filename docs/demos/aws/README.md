# AWS in a Booth

The AWS CLI needs two things: an access key, and a region. On your host they usually sit in
`~/.aws/credentials` and `~/.aws/config`, readable by every process you run. A booth lets you
decide how much of that reaches the code you run in it, and where the keys come from.

There are three ways to hand AWS credentials to a booth. They differ in where the keys live and
who can read them:

| Way | Keys live in | Select | Example |
| --- | --- | --- | --- |
| **Files** | your host `~/.aws/` | `aws-cli` (the `credential` extension is on by default) | [aws-example](../../../examples/booths/aws-example/) |
| **Environment variables** | the shell that starts the booth | `aws-cli+env~credential` | [aws-env-example](../../../examples/booths/aws-env-example/) |
| **EnvFolio** | an encrypted EnvFolio store, unlocked for one command | `aws-cli+env~credential` | [aws-env-example](../../../examples/booths/aws-env-example/) |

All three end the same way: inside the booth, `aws sts get-caller-identity` answers with who you
are, and no key is ever written into the project.

## 1. Files: reuse your `~/.aws`

The default. If `aws` already works on your host, a booth set up with

```bash
booth config --select aws-cli
```

works too. The `credential` extension mounts `~/.aws/config`, `~/.aws/credentials` and the SSO
token cache read-only, and copies them into the booth's home at start. The booth works on the copy,
so nothing in it can change your host files.

This is the simplest route on your own machine. It brings in **every** profile in those files.

## 2. Environment variables: nothing on disk

Select the `env` extension and switch the files off:

```bash
booth config --select 'aws-cli+env~credential'
```

The booth now gets these variables from the shell that starts it, **by name**:

| Variable | Needed |
| --- | --- |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | yes |
| `AWS_REGION` or `AWS_DEFAULT_REGION` | one of them |
| `AWS_SESSION_TOKEN` | only with temporary keys (SSO, `assume-role`, CI's OIDC) |

`.booth/config.toml` holds only the names (`"-e", "AWS_ACCESS_KEY_ID"`), never a value, and a
variable your shell has not set is left out instead of being passed empty. So the project can be
committed and shared as it is.

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
booth -- aws s3 ls
```

**Your keys are in `~/.aws` already?** Let the CLI hand them over for one command, so the secret
is never typed or kept in your shell history:

```bash
( eval "$(aws configure export-credentials --format env)"
  export AWS_REGION=$(aws configure get region)
  booth -- aws s3 ls )
```

`aws configure export-credentials` (AWS CLI v2) prints the active profile's keys as `export`
lines, `AWS_SESSION_TOKEN` included when the profile uses SSO or a role. Add
`--profile <name>` to pick another profile.

This is also the route for **CI**. A GitHub Actions job that sets the three variables from
repository secrets, or better from `aws-actions/configure-aws-credentials` with OIDC (temporary
keys, no stored secret at all), runs the same booth unchanged.

Selecting `aws-cli+env` *without* `~credential` gives you both: the files are seeded and the
variables are passed. The AWS CLI takes each setting from the environment first and falls back to
the files, so one booth works on a laptop with `~/.aws` and on a CI runner without it.

## 3. EnvFolio: keys encrypted at rest, unlocked per command

The environment route has one weak spot: the keys still have to come from somewhere. Kept in a
dotfile or a shell profile, they are as exposed as `~/.aws/credentials`.
[EnvFolio](https://github.com/NawaMan/EnvFolio) (`folio`, in every booth and easy to put on the
host) keeps them in a GPG-encrypted store and hands them to a single command as environment
variables. That is exactly what `aws-cli+env` reads.

Store them once, on the host:

```bash
folio insert secret aws/access-key-id        # asks for the value
folio insert secret aws/secret-access-key
folio insert text   aws/region               # a region is not secret: a plain text
```

An entry's path becomes its variable name: `aws/access-key-id` is `AWS_ACCESS_KEY_ID`. Check the
mapping before anything is unlocked:

```bash
folio exec -s -n aws -- true
# AWS_ACCESS_KEY_ID     <- aws/access-key-id(S)
# AWS_REGION            <- aws/region
# AWS_SECRET_ACCESS_KEY <- aws/secret-access-key(S)
```

Then run the booth through `folio exec`. `-s` loads secrets as well as texts, and `aws` takes every
entry under that folder:

```bash
folio exec -s aws -- booth -- aws s3 ls
```

`folio` asks for the store's passphrase (gpg-agent remembers it for a while), starts the booth
with the three variables set, and they are gone when the command ends. Nothing is left in your
shell, your history, or a file.

Several tools at once: name more folders. With `gh+token` selected too,

```bash
folio exec -s aws gh -- booth -- aws s3 ls
```

also logs `gh` in from a `gh/token` entry (`GH_TOKEN`). A `just` recipe works the same way:
`folio exec -s aws -- just check`.

> **The variables arrive when the booth starts.** `booth -- …` starts a fresh booth each time, so
> it always gets them. A `just` recipe (`booth exec --run`) reuses a booth of this project that is
> already running, and that one keeps the environment it was started with. If `just check` says
> `FAILED` while `booth -- aws sts get-caller-identity` works, stop the running booth and try
> again.

## 4. Give the booth a key you can afford to lose

However they arrive, the keys end up inside the booth. In route 2 and 3 they are in the container's
environment, where `docker inspect` shows them and every process (a script, a dependency, an AI
agent) can read them. So pick *which* key carefully:

- **Not root keys, and not an admin user.** Create a separate IAM user, or better a role, that can
  do only what this project does, in one region.
- **Prefer temporary keys** (`aws sts get-session-token`, SSO, OIDC in CI). They come with an
  `AWS_SESSION_TOKEN` and stop working within hours.
- **Rotate** a long-term key (`AKIA...`) yearly, and delete keys you no longer use. `aws iam
  list-access-keys` and `aws iam get-access-key-last-used` show which ones are stale.
- **Set a billing alarm.** A leaked key is most often used to launch instances, which shows up on
  the bill first.

## Try it

```bash
cd examples/booths/aws-env-example
folio exec -s aws -- just check          # or, from ~/.aws: see route 2
folio exec -s aws -- just config         # the TYPE column says "env"
```

```bash
cd examples/booths/aws-example       # the files route, with a Jupyter notebook
./booth -- aws sts get-caller-identity
```

Both examples have tests: `examples/booths/run-example-tests.sh --example aws-env-example`
runs the env one when your shell has the variables, and reports it **skipped** when it does not.
