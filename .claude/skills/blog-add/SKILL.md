---
name: blog-add
description: Start a new CodingBooth blog post as an UNPUBLISHED draft — creates its route folder so the post is reachable at its exact URL once deployed, but is listed nowhere, linked from nothing, and kept out of search. Use when the user wants to start, draft, or write a blog post. Making it live is a separate skill (blog-publish).
---

# blog-add — start an unpublished blog post

The CodingBooth blog is a GeekPresent static site under `blog/`, served at **codingbooth.io/blog/**.
**Each post is a long-form Text article** — one scrollable page (GeekPresent's "Text" artifact),
*not* a slide deck.

This skill does **half** the job: it creates the post and stops there, deliberately. Turning the
draft into the latest published post is the **`blog-publish`** skill. Never do publish's work here —
a draft that gets linked or listed is no longer a draft.

## What "unpublished" means here

A draft is a **normal route that nothing points at**. SvelteKit prerenders every static route
whether or not anything links to it (`prerender.entries` defaults to `['*']`), so the draft builds,
ships in `site/blog/`, and answers at its exact URL — you can send someone the link for review. It
is invisible in every *other* sense:

| | draft | published |
| --- | --- | --- |
| Route folder | `<slug>.html/` | `<YYYY-MM-DD>.html/` |
| Reachable at its URL | **yes** | yes |
| `TEXT_ROUTES` / `sitemap.xml` | **absent** | listed |
| Blog index (`(home)/+page.svelte`) | **absent** | latest synopsis + Posts list |
| Front page (`site/index.html`) | **absent** | featured |
| Footer nav (prev/next) on it and its neighbour | **both slots empty** | wired both ways |
| `<meta name="robots">` | **`noindex`** | none |

The folder is named by **slug**, not date, because the publish date isn't known yet — `blog-publish`
renames it to `<publish-date>.html/`. So a draft's URL is `/blog/<slug>.html` and its final URL will
be `/blog/<date>.html`. Say this to the user when you hand them the draft link: **the review URL is
temporary.**

## Before you start — gather (ask if not given)
- **Title** of the post.
- **Slug** — kebab-case. It names the draft folder, becomes the `id` on the article's `<h1>`, and
  survives the rename as the `#<slug>` anchor. Check `blog/src/routes/` so it doesn't collide.
- **Subtitle** — the one-line italic line under the title.
- **Description** — ~1–2 sentences for the SEO/social card (`TextPage`'s `description`).
- **Content** — the actual prose/sections. If the user hasn't supplied them, ask for an outline or
  write a short draft and confirm before finishing. Don't invent technical claims about
  CodingBooth; pull from the repo (`CODINGBOOTH.md`, `docs/`) or ask.

Do **not** ask for a publish date. That's `blog-publish`'s question.

## Steps

### 1. Create the route folder
`blog/src/routes/<slug>.html/` — mirror an existing article
(`blog/src/routes/2026-06-18.html/` is the cleanest example) with three files.

**`+layout.js`** — exactly:
```js
export const prerender = true;
export const trailingSlash = "never";
```

**`+layout.svelte`** — wraps `<slot/>` in `TextPage`, **with `noindex`**:
```svelte
<!--
  Blog article (Text artifact): "<Title>" — UNPUBLISHED DRAFT.
  Reachable at its exact URL, but unlisted and noindexed until blog-publish runs.
-->
<script lang="ts">
	import TextPage from '$lib/components/TextPage.svelte';
	import ViewCount from '$lib/components/ViewCount.svelte';
	import FirebaseComments from '$lib/components/FirebaseComments.svelte';
</script>

<TextPage title="<Title>" description="<Description>" type="article" noindex>
	<slot />
	<ViewCount />
	<FirebaseComments />
</TextPage>
```
`noindex` is a `TextPage` prop that forwards to `Seo`; it emits
`<meta name="robots" content="noindex">` into the prerendered HTML. `blog-publish` removes it.

**`+page.svelte`** — the article: a `<script>` that `import`s any colocated images, then plain
markup, then a scoped `<style>` block copied from an existing article (headings, links `#7fd9ff`,
figures, `.video-aside`, `pre`, `.post-nav`) so typography stays consistent.

- The **dateline is a placeholder** — there is no publish date yet:
  ```html
  <p class="dateline">Unpublished draft · Nawa Man</p>
  ```
- The **`<h1>` must carry `id="<slug>"`** — that's the `#<slug>` anchor target.
- Then `subtitle` / `p` / `h2` / `figure`+`figcaption` / `ul` / `pre><code`, ending with a
  "Learn More" list.
- **Colocate images** in the folder and `import` them (`import img from './pic.png'`); never
  hardcode `/…` paths. Use `<pre><code>` for code (escape `<`/`>`/`&`); avoid Monaco `Code`/`CodeBox`
  unless you want a CDN dependency.
- End with the footer nav, **both side slots empty** — a draft has no place in the chain yet:
  ```html
  <nav class="post-nav">
      <span class="nav-prev"></span>
      <a class="nav-home" href="./">↑ back to the blog</a>
      <span class="nav-next"></span>
  </nav>
  ```

### 2. Touch nothing else
This list *is* the unpublished state. Leave every one of these alone:
- `blog/src/lib/seo/routes.ts` — **don't** add the route to `TEXT_ROUTES` (that's what keeps it out
  of `sitemap.xml`).
- `blog/src/routes/(home)/+page.svelte` — no latest synopsis, no Posts entry.
- `site/index.html` — no change to the `<!-- FROM-THE-BLOG -->` section.
- The current newest post — its `<span class="nav-next"></span>` stays empty.

### 3. Verify
Build and stage, then check the draft is reachable *and* invisible:
```bash
build/build-blog.sh
```
- `site/blog/<slug>.html` exists — the draft prerendered.
- `grep -c 'robots" content="noindex' site/blog/<slug>.html` → 1.
- `grep -c '<slug>' site/blog/sitemap.xml` → 0.
- `grep -c '<slug>' site/blog/index.html` → 0.

If the draft *didn't* build, the usual cause is a broken image `import` or a syntax error — the
prerender fails loudly; read the build output.

### 4. Hand off
Tell the user:
- the review URL — `codingbooth.io/blog/<slug>.html` once deployed — and that it **changes to
  `/blog/<date>.html` when published**;
- that `site/blog/` is **committed** (it's part of the published site, not gitignored), so the
  regenerated output goes in with the source change;
- that going live is `blog-publish`, whenever they're ready.

Deploying is external — codingbooth.io is published outside this repo. Don't try to deploy.

## Rules
- **Never** list, link, or feature the draft. If the user wants it live now, that's `blog-publish` —
  run this skill first, then that one.
- The folder is named by **slug**, not date. Don't guess a publish date into the folder name.
- **Comments and view counts are automatic** — the layout renders `<ViewCount />` and
  `<FirebaseComments />`; both are configured once in `src/lib/firebase.ts` (+ `blog/firestore.rules`),
  nothing per post. Keep them on a draft: the thread is keyed by page path, and the path changes at
  publish anyway.
- Reference assets with `import`, colocate per-post images in the post's folder (see `blog/AGENTS.md`).
- The blog is **static** — no `+server.js` / `load()` / form actions (they won't run on the static host).
- Don't over-build. No drafts manifest, no feed, no generator — a draft is just an unlinked folder.
