---
name: blog-publish
description: Publish an unpublished CodingBooth blog post as the new latest — renames its route to the publish date, wires the prev/next links both ways, lists it on the blog index, and features it on the codingbooth.io front page. Use when the user wants to publish, release, or go live with a draft post. Creating the draft is a separate skill (blog-add).
---

# blog-publish — make a draft the latest post

Takes an **unpublished** post created by `blog-add` and wires it into everything that points at
posts. The draft already exists and already builds; this skill does not write prose. If there is no
draft yet, that's `blog-add` — run it first.

Publishing is one atomic idea — *a post joins the chain* — spread over six places:

| # | Place | Change |
| --- | --- | --- |
| 1 | `blog/src/routes/<slug>.html/` | renamed to `<date>.html/` |
| 2 | the post itself | drop `noindex`, real dateline, `nav-prev` → previous newest |
| 3 | the previous newest post | its empty `nav-next` → the new post |
| 4 | `blog/src/lib/seo/routes.ts` | `TEXT_ROUTES` gains `'/<date>.html'` |
| 5 | `blog/src/routes/(home)/+page.svelte` | latest synopsis + first Posts entry |
| 6 | `site/index.html` | `<!-- FROM-THE-BLOG -->` — new latest, old latest demoted |

Miss one and the post is half-published. Work the table top to bottom; step 7 verifies all six.

## Before you start

**Find the draft.** Drafts are the route folders *not* named by a date:
```bash
ls -d blog/src/routes/*.html/ | grep -Ev '/[0-9]{4}-[0-9]{2}-[0-9]{2}\.html/$'
```
Cross-check with `grep -l noindex blog/src/routes/*.html/+layout.svelte`. If there are several, ask
which one. If there are none, say so and offer `blog-add`.

**Confirm the publish date** — default to today, `YYYY-MM-DD`. It becomes the folder name, so it is
the post's permanent URL. Check no existing folder already uses it.

**Read the draft** before editing: you need its title, slug (the `<h1>` `id`), and enough of the
opening to write the synopsis and abstract in steps 5 and 6.

**Identify the previous newest post** — the highest-dated `<YYYY-MM-DD>.html/` folder. You need its
date, slug, and title for the nav wiring, and it's the post that gets demoted on the front page.

## Steps

### 1. Rename the route to the publish date
```bash
git mv blog/src/routes/<slug>.html blog/src/routes/<date>.html
```
The URL becomes `/blog/<date>.html`; the `#<slug>` anchor is unchanged, so the canonical link is
`/blog/<date>.html#<slug>` — the date addresses the page, the slug is a readable anchor. Anyone
holding the old `/blog/<slug>.html` review link now has a dead URL; mention that when you report.

### 2. Edit the post
In `+layout.svelte`: **drop the `noindex` prop** and fix the header comment (it says "UNPUBLISHED
DRAFT").
```svelte
<TextPage title="<Title>" description="<Description>" type="article">
```

In `+page.svelte`: replace the placeholder dateline with the real one, and fill the **left** nav
slot. A new post is the newest, so its right slot stays empty:
```html
<p class="dateline"><D Month YYYY> · Nawa Man</p>
```
```html
<nav class="post-nav">
    <a class="nav-prev" href="./<prev-date>.html#<prev-slug>">← <Previous post title></a>
    <a class="nav-home" href="./">↑ back to the blog</a>
    <span class="nav-next"></span>
</nav>
```

### 3. Wire the neighbour (the easiest step to forget)
Open the **previous newest** article and fill its now-stale empty right slot:
```html
<a class="nav-next" href="./<new-date>.html#<new-slug>"><New post title> →</a>
```
It replaces `<span class="nav-next"></span>`. Hand-maintained on purpose — there's no shared post
list.

### 4. Register the route for the sitemap
Add `'/<date>.html'` (the page path, **no `#` fragment**) to `TEXT_ROUTES` in
`blog/src/lib/seo/routes.ts`, newest first. Each article is a standalone Text, so it must be listed
to reach the sitemap. **This is what un-hides the post** — skipping it leaves it effectively still
a draft.

### 5. Update the blog index
Edit `blog/src/routes/(home)/+page.svelte`. Layout, top to bottom: a **fixed intro** paragraph
(leave it as is), the **latest-post synopsis**, then the **Posts** list. Two edits:

**(a) The latest-post synopsis** (marked `<!-- LATEST -->`) — replace the label date, title + link,
and synopsis wholesale:
```html
<section class="latest" aria-label="Latest post">
    <p class="latest-label">Latest post · <D Mon YYYY></p>
    <h2 class="latest-title"><a href="<date>.html#<slug>"><Post title></a></h2>
    <p class="latest-synopsis"><2–3 sentence synopsis of the post></p>
    <p><a class="read-more" href="<date>.html#<slug>">Read the post →</a></p>
</section>
```

**(b) The Posts list** (`<ul class="posts">`) — **reverse-chronological (newest first)**, each entry
showing its date. Add the new post as the **first** `<li>`; nothing is removed (this list holds
every post):
```html
<li>
    <span class="date"><D Mon YYYY></span>
    <a href="<date>.html#<slug>"><Post title></a>
    <span class="meta"> — <one-line teaser>.</span>
</li>
```

### 6. Feature it on the front page
Edit `site/index.html`. Find the section by its marker comment `<!-- FROM-THE-BLOG -->`. It holds
**one latest post + up to three earlier ones + a "More posts" link**, so publishing shifts
everything down one slot:

1. **Demote the old latest** into a new *first* `<li>` of `<ul class="blog-earlier">` — its
   one-liner is the same teaser used in the blog index's Posts list.
2. **Trim** to three `<li>` by dropping the oldest.
3. **Write the new post into `.blog-latest`** — day / month / year in the date card, the title, and
   a fresh `.blog-abstract` of **at most six sentences** drawn from the post's opening.

If the section is somehow missing, recreate it immediately **after** the hero's `</header>` and
**before** `<section id="coding-booth">`. Sections alternate dark/light down the page, so keep
`section-light` here and make sure the section right after it is dark:
```html
<!-- FROM-THE-BLOG: latest post, hand-maintained by the blog-publish skill. -->
<section id="from-the-blog" class="section-light">
    <div class="container">
        <h2>From the Blog</h2>

        <!-- Latest post: date card + title/abstract. -->
        <div class="blog-latest">
            <a class="blog-datecard" href="/blog/<date>.html#<slug>" aria-label="<D Month YYYY>">
                <span class="blog-day"><DD></span>
                <span class="blog-month"><Month></span>
                <span class="blog-year"><YYYY></span>
            </a>
            <div>
                <h3 class="blog-latest-title">
                    <a href="/blog/<date>.html#<slug>"><Post title></a>
                </h3>
                <p class="blog-abstract"><Abstract, <= 6 sentences.></p>
            </div>
        </div>

        <!-- Earlier posts: date + title, then a one-liner. -->
        <ul class="blog-earlier">
            <li>
                <span class="blog-earlier-date"><D Mon YYYY></span>
                <a href="/blog/<date>.html#<slug>"><Post title></a>
                <p><One-line description.></p>
            </li>
            <!-- ...up to three... -->
        </ul>

        <div class="ctas">
            <a class="btn btn-primary blog-more" href="/blog/">More posts
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"
                    stroke-linejoin="round" aria-hidden="true">
                    <line x1="4" y1="12" x2="19" y2="12" />
                    <polyline points="13 6 19 12 13 18" />
                </svg>
            </a>
        </div>
    </div>
</section>
```
The `.blog-*` classes are already defined in the page's `<style>` block (including the
`.section-light` overrides) — reuse them rather than adding new CSS. The nav "Blog" link and the
hero "Blog" button already exist — don't duplicate them. If the post needs a matching highlight on
`site/more.html`, mirror it the same way; otherwise leave `more.html` alone.

### 7. Build and verify all six
```bash
build/build-blog.sh
```
This builds the blog (inside the blog booth, with `GEEKPRESENT_SITE_URL=https://codingbooth.io/blog`)
and copies the result to `site/blog/`. Then check, one per table row:

1. `site/blog/<date>.html` exists, and `site/blog/<slug>.html` is **gone**.
2. `grep -c 'noindex' site/blog/<date>.html` → **0**.
3. **Check the footer nav both ways** — the new post's `← nav-prev` points at the previous newest,
   and that post's `nav-next →` now points at the new one. An empty slot on either side means the
   neighbour edit didn't happen.
4. `/<date>.html` appears in `site/blog/sitemap.xml`.
5. `site/blog/index.html` shows it as latest *and* first in the Posts list.
6. `site/index.html` shows it in `.blog-latest`, the old latest first under `.blog-earlier`, and no
   more than three earlier entries.

### 8. Hand off the deploy
- `site/blog/` is **committed** (it's part of the published site, not gitignored) — so after the
  rebuild, `git add site/blog` and commit the regenerated output along with the source changes.
- **Deploying is external** — codingbooth.io is published outside this repo. Don't try to deploy.
  Tell the user to commit the regenerated `site/blog/` and upload `site/` (which now includes
  `blog/`), and remind them to rebuild both the blog and the front page.

## Rules
- Publishing is the six edits in the table. Do them all or report plainly which you couldn't.
- The rename in step 1 **changes the post's URL**. Tell the user, so any review link they shared is
  known to be dead.
- `TEXT_ROUTES` (step 4) is the difference between "listed" and "still hidden" — never skip it.
- Don't rewrite the article's prose. If it needs edits, that's ordinary editing, not this skill.
- Don't over-build. No feeds, manifests, or generators — the chain is hand-maintained on purpose.
