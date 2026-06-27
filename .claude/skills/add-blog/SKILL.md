---
name: add-blog
description: Add a new post to the CodingBooth blog and feature it on the front page. Use when the user wants to publish/add a blog post, write a blog article, or update the "latest post" highlight on codingbooth.io. The blog is the GeekPresent project under geekpresent/, served at codingbooth.io/blog/.
---

# add-blog — publish a CodingBooth blog post

The CodingBooth blog is a GeekPresent static site under `geekpresent/`, served at
**codingbooth.io/blog/**. Each post is its own route folder (a click-through slide deck,
and/or a long-form Text). The marketing front page (`site/index.html`) features the
**latest** post by hand.

Your job when this skill runs: create the post, list it on the blog index, and update the
front-page highlight to point at it. **Keep it simple.** Where doing something automatically
would be complicated (writing the actual article prose, generating images, building a
manifest/feed), do it semi-manually instead — scaffold with the user's content or clear
placeholders and ask, rather than building machinery. Do **not** add a posts.json, RSS feed,
or any build pipeline; the front page is updated by editing HTML.

## Before you start — gather (ask if not given)
- **Title** of the post.
- **Slug** — kebab-case, becomes the route folder (`geekpresent/src/routes/<slug>/`). Avoid `home`, `welcome` if taken; check existing route folders.
- **One-line teaser** for the index + front page.
- **Date** (today, `YYYY-MM-DD`).
- **Content** — the actual points/sections. If the user hasn't supplied them, ask for an outline or write a short draft and confirm before finishing. Don't invent technical claims about CodingBooth; pull from the repo (CODINGBOOTH.md, docs/) or ask.

## Steps

### 1. Create the post (a deck)
Mirror the existing `geekpresent/src/routes/welcome/` post — it's the canonical example.
Read `geekpresent/AGENTS.md` for the slide mechanics. Each post folder needs:
- `pages.ts` — the slide list (`{ path, title }[]`).
- `+layout.svelte` — copy `welcome/+layout.svelte` (it does `setPages(pages)` and wraps `<SlideDeck>`); update the `title`/`description` props. Do **not** re-add a per-deck favicon import — the site default (CodingBooth icon) is used and resolves under the `/blog/` subpath.
- `+layout.js` — exactly `export const prerender = true; export const trailingSlash = "never";`
- `+page.svelte` — the index redirect (copy `welcome/+page.svelte` verbatim; it's slug-agnostic).
- One folder per slide: `<name>.html/` with `+page.svelte` (start from `$lib/templates/TitlePage` or `ContentPage`) and the standard `+layout.js`. List every slide in `pages.ts`.

A long-form **Text** version is optional — only add one if the user asks. Pattern: a `<slug>.html/` route wrapping `$lib/components/TextPage.svelte` (see `geekpresent/AGENTS.md` → "Two kinds of artifact").

### 2. List it on the blog index
Edit `geekpresent/src/routes/(home)/+page.svelte` — add an `<li>` to `<ul class="posts">`, newest first:
```html
<li>
    <a href="<slug>/title.html"><Post title></a>
    <span class="meta"> — <one-line teaser>.</span>
</li>
```

### 3. Feature it on the front page (the highlight)
Edit `site/index.html`. Find the **From the Blog** section by its marker comment
`<!-- FROM-THE-BLOG -->`. 

- **If it exists:** replace the featured title, teaser, date, and `/blog/<slug>/title.html` link with the new post.
- **If it does NOT exist yet (first run):** add it as a new `<section>` immediately **before**
  `<section id="learn-more">`. Reuse the page's existing classes (`section-light`, `container`,
  `h2`, `lead`, `ctas`, `btn`) so no new CSS is needed:
```html
<!-- FROM-THE-BLOG: latest post, hand-maintained by the add-blog skill. -->
<section id="from-the-blog">
    <div class="container">
        <h2>From the Blog</h2>
        <p class="lead">Deep dives into the pieces that make CodingBooth tick.</p>
        <p class="blog-featured">
            <span class="blog-date"><YYYY-MM-DD></span>
            <a href="/blog/<slug>/title.html"><strong><Post title></strong></a><br>
            <Post title> — <one-line teaser>.
        </p>
        <div class="ctas">
            <a class="btn btn-primary" href="/blog/<slug>/title.html">Read the post</a>
            <a class="btn" href="/blog/">All posts</a>
        </div>
    </div>
</section>
```
The nav "Blog" link and the hero "Blog" button already exist in `site/index.html` — don't
duplicate them. If the same post needs a matching highlight on `site/more.html`, mirror it the
same way; otherwise leave `more.html` alone.

### 4. Verify, then hand off the deploy
- Build the blog to confirm it prerenders (catches broken imports / orphan slides):
  ```bash
  cd geekpresent
  GEEKPRESENT_SITE_URL=https://codingbooth.io/blog ./build-static.sh /tmp/blog-check
  ```
  Sanity-check: the new `welcome`-style slides land under `/tmp/blog-check/<slug>/`, and the
  index lists the post. (`node_modules` missing? `pnpm install` first.)
- **Deploying is external** — codingbooth.io is published outside this repo, and the blog is its
  own static build dropped into the site's `/blog/` folder. Don't try to deploy; tell the user
  the build command above is what their publish step should run, and remind them to rebuild both
  the blog and the front page.

## Rules
- Keep every slide folder's `pages.ts` entry in sync — a slide folder with no entry is an orphan and breaks the build.
- Reference assets with `import`, colocate per-post images in the post's folder (see `geekpresent/AGENTS.md`).
- The blog is **static** — no `+server.js` / `load()` / form actions (they won't run on the static host).
- Don't over-build. No feeds, manifests, or generators — featuring the latest post is a hand-edit, on purpose.
