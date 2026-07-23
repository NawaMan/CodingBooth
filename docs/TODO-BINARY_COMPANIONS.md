# TODO — libraries that need a separate binary companion

Findings from an audit of setups / templates / extensions (2026-07-22, against
`v0.63.0` / commit `715dd3a6`). The question asked was: *which libraries end up
needing a separate tool binary installation* — not `lib-*` / `*-dev` for C/C++
(those stay on the apt / build-essential track), but companion CLIs and engines
like gRPC codegen (`protoc`) or parser generators (JACC).

Plain `install pip|npm|go|cargo|gem|…` will **not** pull these companions.
There is no automated "package X → needs binary Y" map in the repo today —
only hard-coded setups that already know their own companions (playwright,
plantuml, remotion, vhs).

Back to [TODO](TODO.md) | See also: [setups](BOOTH_SETUP.md), [customization](BOOTH_CUSTOMIZATION.md),
[agent setup recipe](AGENT_SETUP.md)

---

## Table of Contents

- [Rule of thumb](#rule-of-thumb)
- [Already handled in booth](#already-handled-in-booth)
- [Priority shortlist](#priority-shortlist)
- [1. IDL / codegen](#1-idl--codegen)
- [2. Parser generators](#2-parser-generators)
- [3. Browser automation](#3-browser-automation)
- [4. Media / document tooling](#4-media--document-tooling)
- [5. Schema / ORM CLIs](#5-schema--orm-clis)
- [6. Other common companions](#6-other-common-companions)
- [Suggested implementation shape](#suggested-implementation-shape)
- [Out of scope](#out-of-scope)

---

## Rule of thumb

A library needs a **separate binary install** (and often its own setup/template
or an explicit `install apt` / `setup`) when:

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

---

## Already handled in booth

CodingBooth already encodes the companion-binary pattern in a few places:

| Package / tool | Separate binary(ies) | How booth handles it today |
|---|---|---|
| **Playwright** (`npm` / multi-lang) | Chromium / Firefox / WebKit browser builds | `variants/base/setups/playwright--setup.sh` + `templates/tools/playwright/` (`npx playwright install --with-deps`) |
| **PlantUML** | `dot` (**graphviz**) + Java | `plantuml--setup.sh` installs Graphviz automatically |
| **Remotion** | `ffmpeg` + Chromium deps | `remotion--setup.sh` installs both |
| **VHS** | `ffmpeg` | `vhs--setup.sh` installs ffmpeg |
| **gRPC / protobuf** (planned only) | `protoc` + language plugins | Sketched in `experiments/tui-go/data.go` (`protobuf` tool + `go` extension `Requires: ["protobuf"]`) — **no real setup/template yet** |

Shared companions (ffmpeg, graphviz) are only reachable today by selecting the
product that bundles them (Remotion/VHS/PlantUML). A user who only wants
`pip install moviepy` or `pip install graphviz` still has no first-class path.

---

## Priority shortlist

| Priority | Item | Why |
|---|---|---|
| **P0** | **protoc + language plugins** | Classic gRPC case; already sketched in sample TUI data; Go/Python/Java/Node all hit it |
| **P0** | **buf** | Modern replacement path for many protoc workflows |
| **P1** | **antlr4 / javacc / jacc** | Parser-generator case (JACC was a named example); Java-heavy |
| **P1** | **ffmpeg** as a standalone template | Shared by many libs; currently only via remotion/vhs |
| **P1** | **graphviz** as a standalone template | Same; currently only via plantuml |
| **P2** | **prisma**, **grpcurl**, **flatc / thrift** | Common but more niche |
| **P2** | **puppeteer / selenium** driver stacks | Browser automation outside Playwright |

Actionable outcomes for this list:

- [ ] Real **templates/setups** for the P0 set (`protobuf` / `buf`), with
      `requires` edges like the experimental TUI's `go+protobuf → protobuf`
- [ ] Standalone **ffmpeg** and **graphviz** tool templates (P1), so ad-hoc
      media / diagram work does not need Remotion / VHS / PlantUML
- [ ] Optional: a living catalog section in agent docs once P0 exists

---

## 1. IDL / codegen

| Library / ecosystem package | Needs separate binary | Notes |
|---|---|---|
| `grpc` / `grpcio` / `@grpc/grpc-js` / `google.golang.org/grpc` | **`protoc`** + plugins (`protoc-gen-go`, `protoc-gen-go-grpc`, `grpc_tools_node_protoc_plugin`, `protoc-gen-grpc-java`, …) | Classic split: runtime lib vs codegen toolchain |
| `protobuf` / `google.protobuf` / `google.golang.org/protobuf` | **`protoc`** | Same story |
| `buf` clients / Connect-RPC stacks | **`buf`** CLI (often replaces raw protoc) | |
| Apache Thrift language libs | **`thrift`** compiler | |
| FlatBuffers language libs | **`flatc`** | |
| Cap’n Proto language libs | **`capnp`** compiler | |
| Avro language libs | **`avro-tools`** (or language-specific generators) | |
| OpenAPI client/server generators | **`openapi-generator`**, **`swagger-codegen`**, **`oapi-codegen`**, **`openapi-typescript`**, … | Generator is a separate CLI |
| GraphQL codegen stacks | **`graphql-codegen`**, **`apollo` CLI**, **`gqlgen`**, … | |
| gRPC reflection / debug | **`grpcurl`**, **`grpcui`**, **`grpc_cli`** | Ops binaries, not the lib |

**Booth gap:** no `protobuf` / `protoc` / `buf` setup or template (only the
experimental TUI sample in `experiments/tui-go/data.go`).

---

## 2. Parser generators

| Library / tool | Needs separate binary | Notes |
|---|---|---|
| **JACC** (Java LALR) | **`jacc`** binary | Named example: jar/lib usage still needs the generator CLI |
| JavaCC / JJTree | **`javacc`** | |
| ANTLR (Java/Python/… runtimes) | **`antlr4`** / `antlr-4.x-complete.jar` | Runtime jar ≠ grammar compiler |
| Tree-sitter language crates/bindings | **`tree-sitter` CLI** (for grammar codegen) | |
| PEG / packrat tools | language-specific CLIs | Same pattern |
| Bison/Flex-driven stacks | **`bison`**, **`flex`** | *Tools*, not `lib*`; Ruby’s own build already uses bison in `ruby--setup.sh` |

These are almost never satisfied by “install the language package alone.”

---

## 3. Browser automation

| Library | Needs separate binary | Booth status |
|---|---|---|
| **playwright** (JS / Py / .NET / Java) | Browser binaries | ✅ setup + template |
| **puppeteer** / **puppeteer-core** | Chromium (or `PUPPETEER_EXECUTABLE_PATH`) | ❌ no dedicated setup |
| **selenium** | **chromedriver** / **geckodriver** / browser | ❌ |
| **cypress** | Own cached Electron/browser binary | ❌ |

---

## 4. Media / document tooling

| Library / package | Needs separate binary | Booth status |
|---|---|---|
| **remotion** | `ffmpeg` + Chromium | ✅ |
| **vhs** | `ffmpeg` | ✅ |
| **moviepy** / **imageio-ffmpeg** / **pydub** | `ffmpeg` | ❌ if only `pip install moviepy` |
| **weasyprint** / **pdfkit** / **wkhtmltopdf** wrappers | **`wkhtmltopdf`** or similar | ❌ |
| **pandoc** Python/filters | **`pandoc`** (+ often TeX) | ❌ |
| **mermaid-cli** (`@mermaid-js/mermaid-cli`) | Chromium (via puppeteer) | ❌ |
| **plantuml** | **graphviz** (`dot`) | ✅ (bundled in plantuml setup) |
| Python/JS **graphviz** bindings | **`dot`** | ❌ without plantuml |

---

## 5. Schema / ORM CLIs

| Library / package | Needs separate binary | Notes |
|---|---|---|
| **Prisma** (`@prisma/client`) | **`prisma` CLI** | Generate / migrate live outside the runtime package |
| **diesel** (Rust) | **`diesel_cli`** | |
| **sqlx** (Rust) | **`sqlx-cli`** | |
| **Entity Framework** | **`dotnet ef`** | |
| **Flyway / Liquibase / goose / dbmate** | their own CLIs | Migration tools, not runtime libs |
| **atlas** / **golang-migrate** | their own CLIs | |

---

## 6. Other common companions

| Library / package | Needs separate binary | Notes |
|---|---|---|
| **wasm** toolchains | **`wasm-pack`**, **`wasmtime`**, **`wasmer`**, **`wasm-opt`** | Beyond rustc’s wasm32 target alone |
| **protocol simulation / mocks** | **`wiremock`**, **`mockserver`**, **`grpc-wiremock`** | Often separate processes |
| **native image / AOT helpers** | **`native-image`** (GraalVM) | Separate from the JDK |
| **Android / mobile** | **SDK / emulator / platform-tools** | Far beyond a language package |
| **CUDA / GPU ML** | **CUDA toolkit**, drivers | Host/device dependent; not a simple template |

---

## Suggested implementation shape

When turning an item from this list into booth support, prefer the pattern
already used by playwright / plantuml / remotion / vhs:

1. **`variants/base/setups/<name>--setup.sh`** — installs the binary (and only
   the real companions it needs), pin-friendly via version args.
2. **`templates/tools/<name>/template.toml`** — selectable from `booth config`,
   with params for version / optional plugins.
3. **Language extensions with `requires`** — e.g. a Go `protobuf` extension that
   requires the top-level `protobuf` tool (as sketched in
   `experiments/tui-go/data.go`), so selecting the language plugin also pulls
   the shared compiler.
4. **Do not bury shared engines** only inside product setups. If ffmpeg or
   graphviz is a companion for many libraries, give them a **standalone** tool
   template; product setups can still install them for convenience, or
   eventually `require` the standalone tool.

Checklist for a new companion template:

- [ ] Setup script installs the binary under a stable path / `PATH` entry
- [ ] Version is pin-able (arg / template param), default documented
- [ ] Language plugins (if any) are separate extensions with `requires`
- [ ] At least one config or complex test proves the binary is on `PATH`
- [ ] README / display-detail states the companion relationship clearly

---

## Out of scope

- **`lib-*` / `*-dev` C/C++ packages** — handled separately (apt / build-essential
  track); not listed here.
- **Vendored binaries** that already ship inside the language package install
  and work with no extra step.
- **Full product coverage** of every row above — this file is a discovery
  backlog, not a commitment to ship every entry. Start with the [priority
  shortlist](#priority-shortlist).
)
