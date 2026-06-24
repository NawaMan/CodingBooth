# AGENT.md — CodingBooth "tour" deck (built with GeekPresent)

Guidance for an AI agent helping author CodingBooth's promotional slide deck. The deck is built
with **GeekPresent** (a copy-and-own SvelteKit slide engine that lives in this `geekpresent/`
folder) and published **under the existing hand-written site**.

> **Two manuals, don't confuse them.** This file (`AGENT.md`) is the *operations* guide for this
> specific setup — where things live, how to build and deploy. The slide/component *authoring*
> mechanics are in **`./AGENTS.md`** (the GeekPresent engine manual). Read that for how to write
> slides; read this for where the result goes and how it ships.

---

## What this is

- `geekpresent/` produces the **`tour` deck**, served at **https://codingbooth.io/tour/**.
- The hand-written site (`../site/index.html`, `../site/more.html`, `../site/media/…`) is
  **separate and must NOT be touched** — do not edit any file under `../site/` except the
  generated `../site/tour/` output folder.

## Where things live

| Thing | Path |
| --- | --- |
| Author slides here | `src/routes/tour/` — one folder per slide (`<name>.html/+page.svelte`) |
| Slide order | `src/routes/tour/pages.ts` (`{ path, title }` array) |
| Reference examples | `.samples-ref/` — other GeekPresent decks; **gitignored, not built**; read for patterns |
| Build output (intermediate) | `dist/` — **gitignored**, rebuilt each time |
| Published output | `../site/tour/` — **committed**; this is what goes live |

The `tour` deck currently holds GeekPresent's own showcase slides as a starting template —
**replace that content** with CodingBooth's tour as you author.

## Authoring slides (how to help)

- Add a slide: create `src/routes/tour/<name>.html/+page.svelte` plus a `+layout.js` containing
  exactly `export const prerender = true; export const trailingSlash = "never";`, then add a
  `{ path, title }` entry to `src/routes/tour/pages.ts`. Details + components in `./AGENTS.md`.
- House conventions: **style in components, not pages**; prefer **`CodeBox`/`Code`** over
  `JavaCodeBox`/`JavaCode`; design against the fixed **1920×1080** canvas.
- Look in `.samples-ref/` for working examples of every component before inventing markup.

## Build — manual, local, through booth

The build is **NOT automated in CI**. You build it **yourself, locally, through booth** —
CodingBooth's containerized env carries Node 22 + pnpm, so the host needs nothing installed:

```bash
cd geekpresent
./booth -- ./build-static.sh ./dist tour --force   # build in-container → geekpresent/dist
rm -rf ../site/tour && cp -a dist ../site/tour      # publish to the committed site folder (host-side)
```

Why two steps: `booth` only mounts `geekpresent/`, so a container **cannot** write to `../site/`.
Build into `dist/` (inside the mount), then copy to `../site/tour/` on the host (no toolchain
needed for a copy). An agent may run the build, but flag that it spins a container.

## Deploy — commit, then manual pull

```bash
git add geekpresent site/tour && git commit -m "Update tour deck"
```

Deployment is **manual**: a human ssh's into the server and runs `git pull`; the host is
configured to serve the repo's `site/`. **Whatever is committed ships** — there is no build on
the server.

## After deploy — refer to it

The deck is live at **https://codingbooth.io/tour/** (the `/tour/` index auto-redirects to the
first slide). Use that URL to review the result after a deploy.

## Constraints (read before changing anything)

- **Never touch `../site/` hand-written files** — only the generated `../site/tour/` folder.
- **Static only.** No `+server.js` (runtime), `+page.server.js`, `load()`, or form `actions` —
  the host serves static files; those won't run.
- **Custom-domain root** (`codingbooth.io`), so **no base path** — do not set `kit.paths.base`
  (it would break prerender via the SEO/sitemap wiring).
