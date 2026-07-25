# Data Example — a whole data workbench, with GUIs

This example is a single CodingBooth container that stands up an entire graphical data-analysis workbench at once. It seeds a Postgres `demo` database with a ~50-row `sales` table and exposes that one dataset through four lenses: a DBeaver SQL client pre-wired on an XFCE browser desktop, a JupyterLab notebook that charts it with matplotlib, and a Node/Express "Sales Explorer" dashboard with Chart.js filters. It showcases just how much a single booth can bundle: a whole analysis stack — Postgres, DBeaver, JupyterLab, a web dashboard, and Python — comes up together and is driven from a desktop inside your browser. It is the graphical sibling of the [`kind-app`](../kind-app-example) example: where that one hands you a full Kubernetes stack on the command line, this one hands you a full data stack with GUIs. Everything is pre-installed, pinned, and thrown away when you stop the booth — no PostgreSQL, no DBeaver, no Python packages, and no Node ever touch your host.

## What's inside

| Tool | Role | How you use it |
|------|------|----------------|
| **PostgreSQL** | The database — a `demo` DB seeded with a `sales` table (~50 rows, 5 categories, a year of dates). | Queried by everything below. |
| **DBeaver** *(GUI)* | A full graphical SQL client, **pre-wired** to the `demo` database. | Opens on the desktop with the "Demo PostgreSQL" connection already there — just expand and browse. |
| **JupyterLab** | Python notebook, auto-started and exposed. | `Sales-Explorer.ipynb` connects with `psycopg2` and charts the data with matplotlib. |
| **Python 3.12** | With `matplotlib` and `psycopg2-binary` pinned. | The notebook's kernel. |
| **Sales Explorer** *(web GUI)* | A small Node + Express dashboard (`sales-explorer/`) that charts the same data with Chart.js and lets you filter by category / region / product / date. | Opens at `http://localhost:13000` inside the desktop's browser. |

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
- **JupyterLab** is running — open `Sales-Explorer.ipynb` and *Run All* to see the charts.
  It is also published to the host at the booth port **+ 8888**.
- **Sales Explorer dashboard** — open the desktop's browser at `http://localhost:13000`.
  It is also published to the host at the booth port **+ 3000**.

## How it works

- `.booth/Boothfile` — installs Python (+ pip packages), Node.js, PostgreSQL, DBeaver and
  JupyterLab on the `xfce` variant.
- `.booth/config.toml` — persists the PostgreSQL data volume and publishes the notebook
  (`+8888`) and dashboard (`+3000:13000`) ports, booth-relative so multiple booths don't
  collide.
- `.booth/startup.sh` — on boot, waits for PostgreSQL, creates + seeds the `demo` database
  (idempotent), then starts the Sales Explorer dashboard.
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
