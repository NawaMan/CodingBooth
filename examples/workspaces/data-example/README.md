# Data Example — a whole data workbench, with GUIs

This example is a single CodingBooth container that stands up an entire graphical data-analysis workbench at once. It seeds a Postgres `demo` database with a ~50-row `sales` table and exposes that one dataset through four lenses: a DBeaver SQL client pre-wired on an XFCE browser desktop, a JupyterLab notebook that charts it with matplotlib, and a Node/Express "Sales Explorer" dashboard with Chart.js filters. It showcases just how much a single booth can bundle: a whole analysis stack — Postgres, DBeaver, JupyterLab, a web dashboard, and Python — comes up together and is driven from a desktop inside your browser. It is the graphical sibling of the [`kind-app`](../kind-app-example) example: where that one hands you a full Kubernetes stack on the command line, this one hands you a full data stack with GUIs. Everything is pre-installed, pinned, and thrown away when you stop the booth — no PostgreSQL, no DBeaver, no Python packages, and no Node ever touch your host.

## What's inside

| Tool | Role | How you use it |
|------|------|----------------|
| **PostgreSQL** | The database — a `demo` DB seeded with a `sales` table (~50 rows, 5 categories, a year of dates). | Queried by everything below. |
| **DBeaver** *(GUI)* | A full graphical SQL client, **pre-wired** to the `demo` database. | Opens on the desktop with the "Demo PostgreSQL" connection already there — just expand and browse. |
| **JupyterLab** | Python notebook, auto-started and exposed. | `Sales-Explorer.ipynb` connects with `psycopg2` and charts the data with matplotlib. |
| **Python 3.12** | With `matplotlib` and `psycopg2-binary` pinned. | The notebook's kernel. |
| **Sales Explorer** *(web GUI)* | A small Node + Express dashboard (`sales-explorer/`) that charts the same data with Chart.js and lets you filter by category / region / product / date. | Started on demand from its **desktop icon**, which builds it, runs it, and opens it at `http://localhost:13000`. |

One dataset, four lenses: raw SQL (DBeaver), notebook analysis (Jupyter + matplotlib),
and an interactive web dashboard (Sales Explorer) — plus the database itself.

## Run

```bash
./booth
```

The first run pulls the `desktop-xfce` base image and layers the tools on top, then opens
an **XFCE desktop in your browser** on the booth's port. From there:

- **DBeaver** is on the desktop — its "Demo PostgreSQL" connection is already configured
  (`localhost:5432`, database `demo`, user `coder`, no password). Expand it to browse the
  `sales` table.
- **JupyterLab** is running — its **Jupyter Notebook** desktop icon opens it; then open
  `Sales-Explorer.ipynb` and *Run All* to see the charts (the notebook ships with its
  outputs cleared). It is also published to the host at the booth port **+ 8888**.
- **Sales Explorer dashboard** — click the **Sales Explorer** desktop icon. Nothing is
  running until you do: the icon installs the dashboard's npm dependencies if they are
  missing (a second or two on the first click), starts the server, and opens
  `http://localhost:13000` in a browser window.
  It is also published to the host at the booth port **+ 3000**.

From a shell inside the booth, `start-sales-explorer` does the same build-and-start
(logs in `~/.sales-explorer.log`, PID in `~/.sales-explorer.pid`).

## How it works

- `.booth/Boothfile` — installs Python (+ pip packages), Node.js, PostgreSQL, DBeaver and
  JupyterLab on the `xfce` variant.
- `.booth/config.toml` — persists the PostgreSQL data volume and publishes the notebook
  (`+8888`) and dashboard (`+3000:13000`) ports, booth-relative so multiple booths don't
  collide.
- `.booth/startup.sh` — on boot, waits for PostgreSQL and creates + seeds the `demo`
  database (idempotent). It does *not* start the dashboard.
- `.booth/setups/sales-explorer-icon--setup.sh` — a workspace-local setup that registers
  the "Sales Explorer" desktop icon via `cb-web-icon.sh`, the same helper JupyterLab uses.
  The icon's descriptor carries a start command, so `cb-web-open` builds and starts the
  server on click when nothing is listening on port 13000.
- `.booth/templates/project/sales-explorer/` — a project-local template that makes that
  setup *selectable*, so its `setup` line is generated rather than hand-typed. It shows up
  in `booth config` (TUI and `--select`) under "This project", which keeps the Boothfile
  fully generated and reconfigurable.
- `.booth/startups/65-notebook-autostart--startup.sh` — auto-starts JupyterLab.
- `.booth/home-seed/…/data-sources.json` — the DBeaver connection, seeded into the home
  directory so it is present the moment the desktop opens.

## Cleanup

Stop the booth and the whole workbench — database, notebook server, dashboard, GUIs — is
gone. Your host is exactly as clean as it started.

```bash
./booth stop
```

> Demo only — the database has no password and nothing here is production-hardened.
