# Examples Expansion Plan

> **Status:** Stages 1–3 implemented (15 examples + apache/nginx setups). Build & full automated test suite not yet rerun against the new content.
>
> Goal: grow `examples/workspaces/` beyond language-only examples to cover popular frameworks, hard-to-install stacks, and domains where booth replaces a multi-hour setup with a one-liner. Work proceeds in coherent stages of ~5 examples; each stage ships independently.

---

## Conventions (apply to every example)

- **Booth-version-independent.** Commit only `.booth/Boothfile` and `.booth/config.toml`. The `booth` wrapper and `.booth/tools/codingbooth.lock` are gitignored and added at release time by `examples/update-booth.sh`.
- **Pin language/tool versions in the Boothfile** via `arg X_VERSION=...` (e.g. `JDK_VERSION=25`).
- **Pin framework/library versions in the framework's own manifest** (`pom.xml`, `package.json`, `requirements.txt`, `Gemfile`, `composer.json`) — *not* in the Boothfile.
- **Keep the language examples lean.** `java-example`, `nodejs-example`, `python-example`, `php-example` stay as basic toolchain demos; framework workspaces are siblings, not extensions.
- **Optional:** `.cb-tests/test001-…-on-host.sh` to verify the example actually runs (mirror `java-example` and `python-example`).
- **README.md** for every example — what it is, how to run, what to try.
- **Excluded:** OCaml. Setup was parked in `variants/base/setups/future/`; do not propose OCaml-based examples.
- **Parking policy.** If an example resists (toolchain bug, broken upstream tarball, incompatible base image, fragile native deps), park it under "Deferred / parked" and move on. Don't burn the stage on one stubborn item. The OCaml setup is the precedent: it failed, was moved to `variants/base/setups/future/`, and the example was dropped. That's the model.

---

## Stage 1 — Web framework starters ✅

The frameworks most users explicitly ask for. Broad appeal, low novelty cost; useful as social-proof examples.

1. **flask-example** ✅ — Python + Flask, single-file `app.py` + `requirements.txt`.
2. **fastapi-example** ✅ — Python + FastAPI + uvicorn; async demo with one route.
3. **spring-boot-example** ✅ — Java + Spring Boot via Maven; one REST controller.
4. **react-example** ✅ — Vite + React; pays off the existing `react-code-extension` setup.
5. **wordpress-example** ✅ — PHP + MySQL multi-service via workspace-local `wp-init` setup.

---

## Stage 2 — Canonical multi-tier stacks ✅

The acronym stacks every web tutorial since 2005 has used. Easy individually but the value is the glue: a single Boothfile that wires DB + app + frontend + reverse proxy with one hello-world page reading from the DB. Pairs naturally with Stage 1.

Foundation work for this stage: new `apache--setup.sh` and `nginx--setup.sh` (with `/usr/share/startup.d/` auto-start, `--with-php` / `--with-php-fpm` flags, matching templates, and complex tests).

1. **lamp-example** ✅ — Linux + Apache + MySQL + PHP; classic dynamic page from a DB row.
2. **lemp-example** ✅ — nginx + MySQL + PHP-FPM; same demo, modern reverse proxy.
3. **mean-example** ✅ — MongoDB + Express + Angular + Node; SPA hitting an Express API.
4. **mern-example** ✅ — MongoDB + Express + React + Node; React variant.
5. **pern-example** ✅ — Postgres + Express + React + Node; the relational-DB modern variant.

---

## Stage 3 — Web framework round-2 ✅

Round-2 of the user's original list plus adjacent frameworks. Coherent with Stage 1 but narrower audiences, so deferred.

1. **django-example** ✅ — Python + Django + sqlite.
2. **nextjs-example** ✅ — Node + Next.js 15 App Router with a Route Handler.
3. **angular-example** ✅ — Node + Angular 19 standalone component (Signals API).
4. **vaadin-example** ✅ — Java + Vaadin Flow on Spring Boot starter.
5. **rails-example** ✅ — Ruby + Rails (Boothfile + Gemfile-less; README walks through `rails new .`).

---

## Stage 4 — Multi-service / DB showcase

Each pairs a database with a web admin UI to put the **proxy pane** feature front-and-center. Every example here = "open the iframe, click around".

1. **postgres-adminer-example** — Postgres + Adminer.
2. **mongo-mongoexpress-example** — MongoDB + mongo-express.
3. **redis-insight-example** — Redis + RedisInsight.
4. **kafka-ui-example** — Kafka + provectus/kafka-ui.
5. **minio-example** — MinIO (S3-compat) with built-in console.

---

## Stage 5 — Modern data stack (CPU-only)

Cashes in on the new DuckDB setup; introduces "AI without GPU" without committing to GPU passthrough infra.

1. **dbt-duckdb-example** — dbt + DuckDB; modern-data-stack starter.
2. **jupyter-ml-example** — sklearn + pandas + matplotlib in a notebook.
3. **streamlit-example** — Python data app behind the proxy pane.
4. **ollama-cpu-example** — local LLM, small model (1–3B), CPU mode.
5. **airflow-example** — Apache Airflow standalone; the historically-painful install reduced to `booth run`.

---

## Stage 6 — Hard-to-install native deps

Booth's killer use case: stacks people give up installing on their host machine. Each one is a single example carrying weeks of would-be setup pain.

1. **ros2-example** — ROS 2 robotics; Ubuntu/version pinning notoriously fragile.
2. **esp32-example** — ESP-IDF toolchain + xtensa + esptool.
3. **kicad-example** — Electronics CAD on the xfce variant.
4. **latex-example** — TeX Live + Pandoc + Zathura, multi-GB.
5. **bevy-example** — Rust + ALSA/udev/X11 system libs (Rust game engine).

---

## Stage 7 — Niche languages

Pays off recently-added language templates and shows breadth. Each example: a tiny HTTP server or TUI to prove the toolchain works end-to-end.

1. **crystal-lucky-example** — uses new Crystal setup; Lucky web framework.
2. **nim-example** — uses new Nim setup; small HTTP server with `jester` or std `httpserver`.
3. **lean4-example** — Lean 4 theorem prover; a verified-sort demo.
4. **prolog-example** — SWI-Prolog; classic "I'd love to try it but…" language.
5. **gleam-example** — BEAM with friendly typing; Wisp web demo.

---

## Stage 8 — Specialized domains

Domains where booth uniquely beats host installation. Lower-frequency than web frameworks but each is a high-impact "I literally couldn't do this without booth" win.

1. **bioinformatics-example** — samtools + bcftools + bowtie2; the canonical Conda-hell workflow.
2. **gis-example** — PostGIS + GDAL + QGIS (xfce variant).
3. **godot-example** — Godot game engine on xfce.
4. **web3-example** — Foundry + Anvil local chain + a tiny contract.
5. **audio-dsp-example** — SuperCollider or Pure Data on xfce.

---

## Stage 9 — Distributed / observability

Multi-service infra demos. Heaviest stage by image footprint; ship before the k8s/data-pipeline stages so the foundational pieces (Prom, Loki, NATS) exist as building blocks.

1. **observability-example** — Prometheus + Grafana + Loki + Tempo.
2. **mosquitto-mqtt-example** — broker + sub/pub demo.
3. **localstack-example** — AWS emulation; pairs with the existing aws-example.
4. **temporal-example** — Temporal workflow engine + worker.
5. **nats-example** — NATS messaging + CLI demo.

---

## Stage 10 — Local k8s playgrounds

Compose can host a static cluster; it can't host the cluster *plus* the kubectl/helm/argocd workflow loop. Several entries also need privileged + eBPF (Cilium), which compose flatly can't do.

1. **k3d-argocd-example** — k3d + ArgoCD + GitOps app-of-apps walkthrough.
2. **kind-cilium-example** — kind + Cilium + network-policy demo (eBPF).
3. **kind-linkerd-example** — kind + Linkerd + traffic-split canary.
4. **k3d-knative-example** — k3d + Knative serving + scale-to-zero.
5. **kind-crossplane-localstack-example** — kind + Crossplane provisioning fake AWS via LocalStack.

---

## Stage 11 — Data pipelines (multi-step ELT/streaming)

Each example's value is the 6–10 manual commands you run *after* startup: configure a connector, kick a job, query both ends, watch it reconcile. Compose can't drive that flow.

1. **kafka-cdc-example** — Kafka + Kafka Connect + Debezium + Postgres → ClickHouse.
2. **iceberg-trino-example** — MinIO + Iceberg REST catalog + Spark ingest + Trino query.
3. **dagster-dbt-duckdb-example** — Dagster + dbt + DuckDB orchestrated stack.
4. **mlflow-example** — MLflow + Postgres + experiment runs + model registry.
5. **rag-cpu-example** — Ollama + Chroma + LangChain RAG over a sample PDF, CPU only.

---

## Stage 12 — Self-hosted platform stacks

Each is dominated by post-up admin work — realms, dynamic credentials, runner registration, workflow design. Compose can stand up the boxes; it can't drive the configuration. These are guided exercises, not deployments.

1. **keycloak-example** — Keycloak + Postgres + sample app SSO walkthrough.
2. **vault-example** — Vault + dynamic Postgres credentials + sample app.
3. **gitea-actions-example** — Gitea + Forgejo Actions runner + build-and-deploy.
4. **n8n-example** — n8n + Postgres + a sample workflow.
5. **hasura-example** — Hasura + Postgres + auto-generated GraphQL API.

---

## Cross-cutting follow-ups (not a stage)

- Update `examples/workspaces/run-example-tests.sh` (and any release-test job) to recognize each new example after the stage that introduces it.
- Each new framework example should add at least one `.cb-tests/test001-*-on-host.sh` so the release workflow validates it.
- After Stage 1 ships, audit the `examples/recipes/` directory for overlap and consolidate or cross-link.

---

## Deferred / parked

- **GPU-bearing AI examples** (CUDA, large LLMs, vLLM) — defer until host-side GPU passthrough is a first-class booth feature; CPU-only Stage 4 unlocks the AI surface without that dependency.
- **OCaml-based examples** — excluded; setup was parked in `variants/base/setups/future/`.
