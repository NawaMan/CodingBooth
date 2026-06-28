---
name: add-blog
description: Add a new post to the CodingBooth blog and feature it on the front page. Use when the user wants to publish/add a blog post, write a blog article, or update the "latest post" highlight on codingbooth.io. The blog is the GeekPresent project under geekpresent/, served at codingbooth.io/blog/.
---

# add-blog — publish a CodingBooth blog post

The CodingBooth blog is a GeekPresent static site under `geekpresent/`, served at
**codingbooth.io/blog/**. **Each post is a long-form Text article** — one scrollable page
(GeekPresent's "Text" artifact), *not* a slide deck. A post's route folder is named by its
**publish date** (`<YYYY-MM-DD>.html/` → page `/blog/<YYYY-MM-DD>.html`); the post's kebab-case
**slug** is the `id` on its `<h1>`, so the canonical link is `/blog/<date>.html#<slug>` — the date
addresses the page, the slug is a readable anchor. The marketing front page (`site/index.html`)
features the **latest** post by hand.

The existing posts are the canonical examples to copy:
`geekpresent/src/routes/2026-05-29.html/` (slug `works-on-my-machine`) and
`2026-06-18.html/` (slug `four-promises-of-a-booth`) — prose + colocated images + code.

Your job when this skill runs: create the post, list it on the blog index, and update the
front-page highlight to point at it. **Keep it simple.** Where doing something automatically
would be complicated (writing the actual article prose, generating images, building a
manifest/feed), do it semi-manually instead — scaffold with the user's content or clear
placeholders and ask, rather than building machinery. Do **not** add a posts.json, RSS feed,
or any build pipeline; the front page is updated by editing HTML.

## Before you start — gather (ask if not given)
- **Title** of the post.
- **Date** — `YYYY-MM-DD`; it names the route folder `<date>.html/` (so the page is `/blog/<date>.html`). Check existing folders so two posts don't collide on one date.
- **Slug** — kebab-case; it becomes the `id` on the article's `<h1>` and the `#<slug>` anchor in links.
- **One-line teaser** for the index + front page.
- **Content** — the actual prose/sections. If the user hasn't supplied them, ask for an outline or write a short draft and confirm before finishing. Don't invent technical claims about CodingBooth; pull from the repo (CODINGBOOTH.md, docs/) or ask.

## Steps

### 1. Create the post (a Text article)
Mirror an existing article, e.g. `geekpresent/src/routes/2026-06-18.html/`. A post is a route
folder named by its date, `<date>.html/`, containing:
- `+layout.js` — exactly `export const prerender = true; export const trailingSlash = "never";`
- `+layout.svelte` — wraps `<slot/>` in `$lib/components/TextPage.svelte`; pass `title`,
  `description`, and `type="article"`, and render `<ViewCount />` then `<Comments />` after the
  `<slot/>` (Firebase view counter + giscus comments — both on by default). Copy an existing one
  and edit the props.
- `+page.svelte` — the article itself: a `<script>` that `import`s any colocated images, then
  plain markup — the `<h1>` **must carry `id="<slug>"`** (the `#<slug>` anchor target), followed by
  `subtitle`/`p`/`h2`/`figure`+`figcaption`/`ul`/`pre><code` — and a scoped
  `<style>` block. Copy the style block from an existing article for consistent typography
  (headings, links `#7fd9ff`, figures, `.video-aside`, `pre`, `.post-nav`). End with a "Learn More"
  list and the **footer nav** (below).
- **Colocate images** in the folder and `import` them (`import img from './pic.png'`); never
  hardcode `/…` paths. Use a `<pre><code>` block for code (escape `<`/`>`/`&`); avoid Monaco
  `Code`/`CodeBox` unless you want a CDN dependency.

**Footer nav (prev / back / next).** Each article ends with a three-part nav: the *older* post on
the left, "back to the blog" in the middle, the *newer* post on the right. A new post is the
newest, so its right slot is empty and its left points at the previous newest:
```html
<nav class="post-nav">
    <a class="nav-prev" href="./<prev-date>.html#<prev-slug>">← <Previous post title></a>
    <a class="nav-home" href="./">↑ back to the blog</a>
    <span class="nav-next"></span>
</nav>
```
**Then update the neighbour:** open the *previous* newest article and fill its now-empty
`<span class="nav-next"></span>` with a link to the new post:
`<a class="nav-next" href="./<new-date>.html#<new-slug>"><New post title> →</a>`. (Hand-maintained
on purpose — there's no shared post list.)

Then **register the route for the sitemap**: add `'/<date>.html'` (the page path, **no `#` fragment**)
to `TEXT_ROUTES` in `geekpresent/src/lib/seo/routes.ts` (each article is a standalone Text, so it
must be listed to reach the sitemap).

### 2. Update the blog index
Edit `geekpresent/src/routes/(home)/+page.svelte`. Its layout is, top to bottom: a **fixed intro**
paragraph (about CodingBooth + what the blog covers — leave it as is), then the **latest-post
synopsis**, then the **Posts** list. Make **two** edits for a new post:

**(a) The latest-post synopsis** (marked `<!-- LATEST -->`, just below the intro). The newest post
always gets a short synopsis here — replace the label date, title + link, and synopsis:
```html
<section class="latest" aria-label="Latest post">
    <p class="latest-label">Latest post · <D Mon YYYY></p>
    <h2 class="latest-title"><a href="<date>.html#<slug>"><Post title></a></h2>
    <p class="latest-synopsis"><2–3 sentence synopsis of the post></p>
    <p><a class="read-more" href="<date>.html#<slug>">Read the post →</a></p>
</section>
```

**(b) The Posts list** (`<ul class="posts">`) — **reverse-chronological (newest first)** and each
entry **shows its date**. Add the new post as the first `<li>`:
```html
<li>
    <span class="date"><D Mon YYYY></span>
    <a href="<date>.html#<slug>"><Post title></a>
    <span class="meta"> — <one-line teaser>.</span>
</li>
```

### 3. Feature it on the front page (the highlight)
Edit `site/index.html`. Find the **From the Blog** section by its marker comment
`<!-- FROM-THE-BLOG -->`. 

- **If it exists:** replace the featured title, teaser, date, and `/blog/<date>.html#<slug>` link with the new post.
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
            <a href="/blog/<date>.html#<slug>"><strong><Post title></strong></a><br>
            <Post title> — <one-line teaser>.
        </p>
        <div class="ctas">
            <a class="btn btn-primary" href="/blog/<date>.html#<slug>">Read the post</a>
            <a class="btn" href="/blog/">All posts</a>
        </div>
    </div>
</section>
```
The nav "Blog" link and the hero "Blog" button already exist in `site/index.html` — don't
duplicate them. If the same post needs a matching highlight on `site/more.html`, mirror it the
same way; otherwise leave `more.html` alone.

### 4. Verify, then hand off the deploy
- Build the blog to confirm it prerenders (catches broken imports / unregistered routes) and stage it
  into `site/blog/`:
  ```bash
  build/build-blog.sh
  ```
  This builds the blog (inside the geekpresent booth, with `GEEKPRESENT_SITE_URL=https://codingbooth.io/blog`)
  and copies the result to `site/blog/`. Sanity-check: the new article lands at
  `site/blog/<date>.html` (a file; the `#<slug>` is only an anchor), the index lists it, and
  `/<date>.html` appears in `site/blog/sitemap.xml`.
- **Check the footer nav both ways:** the new post's `← nav-prev` points at the previous newest
  post, and that previous post's `nav-next →` now points at the new one (the neighbour edit from
  step 1). A missing/empty slot on either side means the neighbour wasn't wired up.
- `site/blog/` is **committed** (it's part of the published site, not gitignored) — so after a
  rebuild, `git add site/blog` and commit the regenerated output along with your source changes.
- **Deploying is external** — codingbooth.io is published outside this repo. Don't try to deploy;
  tell the user to run `build/build-blog.sh`, commit the regenerated `site/blog/`, and upload `site/`
  (which now includes `blog/`), and remind them to rebuild both
  the blog and the front page.

## Rules
- Register each new article's route in `TEXT_ROUTES` (`geekpresent/src/lib/seo/routes.ts`) or it won't appear in the sitemap.
- **Comments are automatic** — each article layout renders `<Comments />` (giscus, one thread per post via `pathname`). It's configured **once** in `src/lib/components/Comments.svelte` (repo-id / category-id from giscus.app); nothing to do per post. It shows a setup note until those IDs are filled in.
- **View counts are automatic** — each article layout renders `<ViewCount />` (Firebase/Firestore, one counter per page path). Configured **once** in `src/lib/firebase.ts` (web config from the Firebase console), with rules in `geekpresent/firestore.rules`; nothing per post. Renders nothing until Firebase is configured.
- Reference assets with `import`, colocate per-post images in the post's folder (see `geekpresent/AGENTS.md`).
- The blog is **static** — no `+server.js` / `load()` / form actions (they won't run on the static host).
- Don't over-build. No feeds, manifests, or generators — featuring the latest post is a hand-edit, on purpose.
