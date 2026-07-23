# Data Example — a whole data workbench, with GUIs

A single CodingBooth container that stands up an entire **data-analysis workbench** at
once — a database, a notebook, and two GUIs — all wired to the *same* seeded dataset.
It is the graphical sibling of the [`kind-app`](../kind-app-example) example: where that one
gives you a whole Kubernetes stack on the command line, this one gives you a whole data
stack you drive from a **desktop in your browser**.

Everything below is pre-installed, pinned, and thrown away when you stop the booth. Nothing
lands on your host — no PostgreSQL, no DBeaver, no Python packages, no Node.

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
