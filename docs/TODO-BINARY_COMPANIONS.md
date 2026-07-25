# TODO — libraries that need a separate binary companion

Findings from an audit of setups / templates / extensions (2026-07-22, against
`v0.63.0` / commit `715dd3a6`), with urgency re-ranked (2026-07-23) against what
the **config TUI already installs** via package-manager extensions.

The question asked was: *which libraries end up needing a separate tool binary
installation* — not `lib-*` / `*-dev` for C/C++ (those stay on the apt /
build-essential track), but companion CLIs and engines like gRPC codegen
(`protoc`) or parser generators (JACC).

**Urgency rule (owner, 2026-07-23):** if the companion binary can already be
installed through the config TUI’s existing `*-pkg` managers (`apt-pkg`,
`npm-pkg`, `pip-pkg`, `go-pkg`, `cargo-pkg`, …), it is **not urgent** to add a
dedicated setup/template. Dedicated templates remain optional sugar
(discoverability, fresher pins, `requires` edges) — not a capability gap.

Back to [TODO](TODO.md) | See also: [setups](BOOTH_SETUP.md), [customization](BOOTH_CUSTOMIZATION.md),
[booth config package managers](BOOTH_CONFIG.md), [agent setup recipe](AGENT_SETUP.md)

---

## Table of Contents

- [Urgency by TUI installability](#urgency-by-tui-installability)
- [Rule of thumb](#rule-of-thumb)
- [Already handled as dedicated setups](#already-handled-as-dedicated-setups)
- [Priority shortlist (after re-rank)](#priority-shortlist-after-re-rank)
- [1. IDL / codegen](#1-idl--codegen)
- [2. Parser generators](#2-parser-generators)
- [3. Browser automation](#3-browser-automation)
- [4. Media / document tooling](#4-media--document-tooling)
- [5. Schema / ORM CLIs](#5-schema--orm-clis)
- [6. Other common companions](#6-other-common-companions)
- [Suggested implementation shape](#suggested-implementation-shape)
- [Out of scope](#out-of-scope)

---

## Urgency by TUI installability

The config TUI already exposes package installs (see
[BOOTH_CONFIG.md](BOOTH_CONFIG.md) “package manager extensions”):

| Extension | Manager | Example |
|---|---|---|
| `apt-pkg` | apt | `apt-pkg:ffmpeg,graphviz,protobuf-compiler` |
| `nodejs+npm-pkg` | npm | `nodejs+npm-pkg:prisma,@bufbuild/buf` |
| `python+pip-pkg` | pip | `python+pip-pkg:grpcio-tools` |
| `go+go-pkg` | `go install` | `go+go-pkg:…/protoc-gen-go@latest` |
| `rust+cargo-pkg` | cargo | `rust+cargo-pkg:sqlx-cli` |
| `csharp+dotnet-pkg` / `dotnet+dotnet-pkg` | `dotnet tool install --global` | `csharp+dotnet-pkg:dotnet-ef` |
| (+ yarn / bun / uv / conda / gem / …) | | |

**Nuance:** installing the *language library* via pip/npm still does **not** pull
the companion. Example: `python+pip-pkg:grpcio` does not install `protoc`. The
user must also select `apt-pkg:protobuf-compiler` (and any plugins). So the soft
problem for `*-pkg`-reachable items is **discoverability**, not capability.

Rough split of the catalog (~34 items):

| Bucket | Count | Meaning |
|---|---|---|
| Installable via existing `*-pkg` | ~22 | **Not urgent** as dedicated templates |
| Already have a dedicated setup/template | 2+ | Playwright, Mermaid (+ Remotion/VHS/PlantUML bundling companions) |
| Not cleanly reachable via `*-pkg` | ~10 | Only real remaining template/setup candidates |

### Not urgent — companion already installable via TUI `*-pkg`

| Companion | How today (config TUI / CLI) | Caveats |
|---|---|---|
| **protoc** | `apt-pkg:protobuf-compiler` | Ubuntu often ships an older protoc (e.g. 3.21.x) |
| gRPC C++ plugin | `apt-pkg:protobuf-compiler-grpc` | |
| **protoc-gen-go** / go-grpc | `go+go-pkg:google.golang.org/protobuf/cmd/protoc-gen-go@latest`, `…/protoc-gen-go-grpc@latest` | Needs `go` template selected |
| **buf** | `go+go-pkg:github.com/bufbuild/buf/cmd/buf@latest` **or** `nodejs+npm-pkg:@bufbuild/buf` | |
| grpcurl | `go+go-pkg:github.com/fullstorydev/grpcurl/cmd/grpcurl@latest` | |
| thrift / flatc / capnp | `apt-pkg:thrift-compiler`, `flatbuffers-compiler`, `capnproto` | |
| openapi-generator-cli | `nodejs+npm-pkg:@openapitools/openapi-generator-cli` | |
| oapi-codegen | `go+go-pkg:…/oapi-codegen@latest` | |
| graphql-codegen | `nodejs+npm-pkg:@graphql-codegen/cli` | |
| **antlr4** / javacc | `apt-pkg:antlr4`, `javacc` | apt versions can lag (antlr 4.9-class) |
| bison / flex | `apt-pkg:bison,flex` | |
| tree-sitter CLI | `rust+cargo-pkg:tree-sitter-cli` (or npm) | |
| **ffmpeg** | `apt-pkg:ffmpeg` | Standalone template not needed for install |
| **graphviz** | `apt-pkg:graphviz` | Same |
| pandoc | `apt-pkg:pandoc` | |
| prisma CLI | `nodejs+npm-pkg:prisma` | Runtime `@prisma/client` is a project dep |
| diesel_cli / sqlx-cli | `rust+cargo-pkg:diesel_cli`, `sqlx-cli` | diesel may need cargo features |
| wasm-pack | `rust+cargo-pkg:wasm-pack` | |
| Python protoc plugin | `python+pip-pkg:grpcio-tools` | Still needs `protoc` itself via apt |

Example gRPC booth **without** a new template:

```bash
booth config --no-tui \
  --select go+go-pkg:google.golang.org/protobuf/cmd/protoc-gen-go@latest,google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest \
  --select apt-pkg:protobuf-compiler
```

### Already have dedicated setup / template

| Item | Status |
|---|---|
| **Playwright** browsers | ✅ `setup playwright` + `templates/tools/playwright/` |
| **Puppeteer** browsers | ✅ `setup puppeteer` + `templates/tools/puppeteer/` (`PUPPETEER_CACHE_DIR=/opt/puppeteer`) |
| **Cypress** binary | ✅ `setup cypress` + `templates/tools/cypress/` (`CYPRESS_CACHE_FOLDER=/opt/cypress`) |
| **Selenium** drivers | ✅ `setup selenium` + `templates/tools/selenium/` (Chrome for Testing + chromedriver; optional geckodriver) |
| **Mermaid CLI** | ✅ `templates/tools/mermaid/` (also installable via npm) |
| **PlantUML** (+ graphviz) | ✅ product setup installs graphviz |
| **Remotion** / **VHS** (+ ffmpeg) | ✅ product setups install ffmpeg |
| **ffmpeg** (standalone) | ✅ `templates/tools/ffmpeg/` (`install apt ffmpeg`) |
| **Graphviz** (standalone) | ✅ `templates/tools/graphviz/` (`install apt graphviz`) |
| **protoc** / Protocol Buffers | ✅ `templates/tools/protobuf/` (+ `go` extension for plugins) |
| **Buf CLI** | ✅ `setup buf` + `templates/tools/buf/` (GitHub release binary) |

### Still awkward — not cleanly covered by `*-pkg` (only remaining urgency)

| Item | Why `*-pkg` is not enough | Suggested urgency |
|---|---|---|
| **Puppeteer / Cypress browsers** | ✅ dedicated setups (Playwright-shaped shared caches) | done |
| **Selenium drivers** | ✅ Chrome for Testing + chromedriver (not apt snap stubs); optional geckodriver | done |
| **JACC** | not a normal apt/npm/go package — usually a manual jar | medium (named example; rare) |
| **`dotnet ef`** | ✅ `csharp+dotnet-pkg:dotnet-ef` / `install dotnet dotnet-ef` | done |
| **wkhtmltopdf**, **avro-tools** | not reliably in this Ubuntu’s apt | low–medium |
| **GraalVM / native-image**, **Android SDK** | full toolchains | high *if* wanted; big projects |
| **CUDA** | host/device dependent | out of scope for normal templates |

---

## Rule of thumb

A library needs a **separate binary install** (and often an explicit
`install apt` / `*-pkg` / `setup`) when:

1. **Codegen** — `.proto` / `.thrift` / `.fbs` / `.g4` / grammar files need a CLI
   to produce sources.
2. **Runtime embeds an external engine** — browsers, ffmpeg, graphviz, TeX, WASM
   toolchains.
3. **Schema / ORM ops live in a CLI** separate from the runtime package
   (Prisma, `diesel_cli`, `sqlx-cli`, `dotnet ef`).

It does **not** count when:

- the package only needs **`libfoo-dev`** / shared libraries → separate C/C++ track
- the package **vendors** its binary inside `node_modules` / a wheel and works
  after install alone

It is **not urgent to template** when:

- the companion is already a normal **`apt-pkg` / `npm-pkg` / `go-pkg` /
  `cargo-pkg` / `pip-pkg`** name the user can select in the config TUI today

---

## Already handled as dedicated setups

CodingBooth already encodes multi-step companion installs (beyond plain `*-pkg`)
in a few places:

| Package / tool | Separate binary(ies) | How booth handles it today |
|---|---|---|
| **Playwright** | Chromium / Firefox / WebKit browser builds | `playwright--setup.sh` + template (`npx playwright install --with-deps`) |
| **PlantUML** | `dot` (**graphviz**) + Java | setup installs Graphviz automatically |
| **Remotion** | `ffmpeg` + Chromium deps | setup installs both |
| **VHS** | `ffmpeg` | setup installs ffmpeg |
| **gRPC / protobuf** | `protoc` + language plugins | ✅ `templates/tools/protobuf/` (+ `go` extension); also still via `apt-pkg` + `go-pkg` |

Shared companions (ffmpeg, graphviz) are also reachable without those product
templates via `apt-pkg` (see table above).

---

## Priority shortlist (after re-rank)

`*-pkg` still covers install *capability* for protoc/buf/ffmpeg/graphviz, but
**first-class TUI templates are the product aim** (discoverability, `requires`
edges, pin-friendly defaults). The rest of the catalog follows in phases.

| Priority | Item | Status |
|---|---|---|
| **Phase 1** | Convenience templates: `protobuf`, `buf`, `ffmpeg`, `graphviz` + Go protoc plugins | ✅ Done (`templates/tools/{protobuf,buf,ffmpeg,graphviz}/`, `buf--setup.sh`) |
| **Phase 2** | `dotnet tool` / `dotnet-pkg` extension | ✅ Done (`install dotnet` + `csharp`/`dotnet`+`dotnet-pkg`) |
| **Phase 3** | Puppeteer → Cypress → Selenium browser+driver stacks | ✅ Done (`setup puppeteer` / `cypress` / `selenium`) |
| **Phase 4** | Docs catalog: “library X → also select Y” | ✅ Done — [BOOTH_CONFIG.md](BOOTH_CONFIG.md#binary-companions--library-x--also-select-y) |
| **P2** | JACC, avro-tools, wkhtmltopdf | Parked until demand |
| **Parked** | GraalVM, Android SDK, CUDA | Large / host-specific |

Actionable outcomes:

- [x] Phase 1 — dedicated `protobuf` / `buf` / `ffmpeg` / `graphviz` templates
      (apt for protoc/ffmpeg/graphviz; official GitHub binary for buf; Go plugins
      as `protobuf+go`)
- [x] Phase 2 — `dotnet-pkg` generic extension (`install dotnet` /
      `dotnet tool install --global`; e.g. `csharp+dotnet-pkg:dotnet-ef`)
- [x] Phase 3 — Puppeteer / Cypress / Selenium setups (shared browser caches
      + Chrome for Testing / chromedriver; not apt snap stubs)
- [x] Phase 4 — product docs catalog of “library X → also select Y”
      ([BOOTH_CONFIG.md](BOOTH_CONFIG.md#binary-companions--library-x--also-select-y);
      pointer from [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md))
- [ ] Consider more dedicated setups only when install needs **more than a
      package name** (browser downloads, multi-step toolchains, non-registry
      binaries)

---

## 1. IDL / codegen

| Library / ecosystem package | Needs separate binary | TUI path today | Urgent template? |
|---|---|---|---|
| `grpc` / `grpcio` / `@grpc/grpc-js` / `google.golang.org/grpc` | **`protoc`** + plugins | `protobuf` template + `protobuf+go`; also `apt-pkg` + go/npm/pip | Done (Go plugins); others later |
| `protobuf` / … | **`protoc`** | `protobuf` template or `apt-pkg:protobuf-compiler` | Done |
| `buf` / Connect-RPC | **`buf`** CLI | `buf` template; also `go-pkg` / `npm-pkg:@bufbuild/buf` | Done |
| Apache Thrift libs | **`thrift`** | `apt-pkg:thrift-compiler` | No |
| FlatBuffers libs | **`flatc`** | `apt-pkg:flatbuffers-compiler` | No |
| Cap’n Proto libs | **`capnp`** | `apt-pkg:capnproto` | No |
| Avro libs | **`avro-tools`** | usually jar download | Maybe (awkward) |
| OpenAPI generators | generator CLIs | npm/go packages for most | No |
| GraphQL codegen | CLIs | `npm-pkg` | No |
| grpcurl / grpcui | ops CLIs | `go-pkg` for grpcurl | No |

---

## 2. Parser generators

| Library / tool | Needs separate binary | TUI path today | Urgent template? |
|---|---|---|---|
| **JACC** | **`jacc`** binary | none standard | Only if someone needs it |
| JavaCC / JJTree | **`javacc`** | `apt-pkg:javacc` | No |
| ANTLR runtimes | **`antlr4`** | `apt-pkg:antlr4` (may be old) | No (unless pin to latest jar) |
| Tree-sitter bindings | **`tree-sitter` CLI** | cargo/npm | No |
| Bison/Flex stacks | **`bison`**, **`flex`** | `apt-pkg` | No |

---

## 3. Browser automation

| Library | Needs separate binary | Booth / TUI status | Urgent template? |
|---|---|---|---|
| **playwright** | Browser binaries | ✅ dedicated setup | Done |
| **puppeteer** | Chromium download | ✅ `setup puppeteer` + shared `/opt/puppeteer` cache | Done |
| **selenium** | drivers + browser | ✅ `setup selenium` (Chrome for Testing + chromedriver) | Done |
| **cypress** | cached Electron/browser | ✅ `setup cypress` + shared `/opt/cypress` cache | Done |

---

## 4. Media / document tooling

| Library / package | Needs separate binary | TUI path today | Urgent template? |
|---|---|---|---|
| **remotion** / **vhs** | `ffmpeg` (+ Chromium for remotion) | ✅ product setups; also `ffmpeg` template / `apt-pkg:ffmpeg` | Done / No |
| **moviepy** / **pydub** | `ffmpeg` | `ffmpeg` template or `apt-pkg:ffmpeg` | Done (standalone template) |
| **weasyprint** / **pdfkit** / wkhtmltopdf wrappers | **`wkhtmltopdf`** etc. | not reliably in apt | Maybe |
| **pandoc** filters | **`pandoc`** | `apt-pkg:pandoc` | No |
| **mermaid-cli** | Chromium often | ✅ mermaid template; or npm | Done / No |
| **plantuml** | graphviz | ✅ setup; also `graphviz` template / `apt-pkg:graphviz` | Done / No |
| graphviz language bindings | **`dot`** | `graphviz` template or `apt-pkg:graphviz` | Done (standalone template) |

---

## 5. Schema / ORM CLIs

| Library / package | Needs separate binary | TUI path today | Urgent template? |
|---|---|---|---|
| **Prisma** | **`prisma` CLI** | `npm-pkg:prisma` | No |
| **diesel** | **`diesel_cli`** | `cargo-pkg` | No |
| **sqlx** | **`sqlx-cli`** | `cargo-pkg` | No |
| **Entity Framework** | **`dotnet ef`** | `csharp+dotnet-pkg:dotnet-ef` / `install dotnet dotnet-ef` | Done |
| Flyway / Liquibase / goose / dbmate / atlas | their CLIs | mix of go/apt/manual | case-by-case |

---

## 6. Other common companions

| Library / package | Needs separate binary | TUI path today | Urgent template? |
|---|---|---|---|
| **wasm** toolchains | wasm-pack, etc. | cargo for wasm-pack | No for wasm-pack |
| **native-image** (GraalVM) | GraalVM | none | Only if product wants it |
| **Android / mobile** | SDK / emulator | none | Parked |
| **CUDA / GPU ML** | toolkit / drivers | host-dependent | Out of scope |

---

## Suggested implementation shape

When an item **does** need more than `*-pkg` (browser download, non-registry
binary, multi-step toolchain), prefer the pattern already used by playwright /
plantuml / remotion / vhs:

1. **`variants/base/setups/<name>--setup.sh`** — installs the binary (and only
   the real companions it needs), pin-friendly via version args.
2. **`templates/tools/<name>/template.toml`** — selectable from `booth config`,
   with params for version / optional plugins.
3. **Language extensions with `requires`** — optional sugar so selecting a
   language plugin also pulls a shared tool (as sketched in
   `experiments/tui-go/data.go`).
4. **Do not** invent a template solely because `apt-pkg:foo` works — document
   the package name instead.

Checklist for a new companion template (only when `*-pkg` is insufficient):

- [ ] Setup does something a package manager install cannot (extra download,
      drivers, multi-binary orchestration)
- [ ] Version is pin-able; default documented
- [ ] Language plugins (if any) are separate extensions with `requires`
- [ ] At least one config or complex test proves the binary is on `PATH`
- [ ] display-detail states the companion relationship clearly

---

## Out of scope

- **`lib-*` / `*-dev` C/C++ packages** — separate track; not listed as urgent
  binary companions.
- **Vendored binaries** that already ship inside the language package install.
- **Full product coverage** of every row — discovery backlog only.
- **Items already installable via TUI `*-pkg`** — not urgent for dedicated
  templates; see [Urgency by TUI installability](#urgency-by-tui-installability).
)
