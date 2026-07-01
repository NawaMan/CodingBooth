<!--
  Blog index — served at the site root `/` (i.e. codingbooth.io/blog/).

  Built as a Text artifact (shares the TextPage shell). Layout, top to bottom:
    1. A short intro to CodingBooth and what this blog covers.
    2. A synopsis of the LATEST post (update it whenever you publish).
    3. "Posts" — every article, reverse-chronological, each with its date.
  Each post is a Text article at `<slug>.html`; links are relative to `/`.
-->
<h1>The CodingBooth Blog</h1>

<p class="intro">
	<a href="https://codingbooth.io">CodingBooth</a> delivers fully reproducible, isolated
	development environments in a Docker container that runs as <i>you</i>, with your project files
	staying yours on the host. This blog covers CodingBooth one topic at a time — feature deep-dives,
	hands-on examples, and project news.
</p>

<!-- LATEST: synopsis of the most recent post. Update when you publish a new one. -->
<section class="latest" aria-label="Latest post">
	<p class="latest-label">Latest post · 28 Jun 2026</p>
	<h2 class="latest-title"><a href="2026-06-28.html#onboard-quick-onboard-right">Onboard Quick, Onboard Right</a></h2>
	<p class="latest-synopsis">
		Onboarding onto a project usually feels simple — until the “good enough” setup starts charging
		a slow, creeping tax of invisible discrepancies. Getting in fast is only half the job; getting
		in <em>right</em> is the other half, and neither should rely on luck.
	</p>
	<p><a class="read-more" href="2026-06-28.html#onboard-quick-onboard-right">Read the post →</a></p>
</section>

<h2>Posts</h2>

<ul class="posts">
	<li>
		<span class="date">28 Jun 2026</span>
		<a href="2026-06-28.html#onboard-quick-onboard-right">Onboard Quick, Onboard Right</a>
		<span class="meta"> — onboarding fast isn't enough; you have to onboard right, and that shouldn't rely on luck.</span>
	</li>
	<li>
		<span class="date">18 Jun 2026</span>
		<a href="2026-06-18.html#four-promises-of-a-booth">The Four Promises of a Booth</a>
		<span class="meta"> — isolation, repeatability, shareability, and usability: the four things a booth gives every project.</span>
	</li>
	<li>
		<span class="date">29 May 2026</span>
		<a href="2026-05-29.html#works-on-my-machine">Ending “It Works on My Machine”</a>
		<span class="meta"> — why the problem keeps happening, and how a booth ends it.</span>
	</li>
</ul>

<p class="more">More posts land here over time.</p>

<p class="links">
	<a href="https://codingbooth.io">← codingbooth.io</a> &nbsp;·&nbsp;
	<a href="https://github.com/NawaMan/CodingBooth">GitHub</a>
</p>

<style>
	h1 {
		font-size: 2.6em;
		margin-bottom: 0.2em;
	}
	.intro {
		font-size: 1.15em;
		line-height: 1.6;
		opacity: 0.95;
	}
	a {
		color: #7fd9ff;
	}

	/* Latest-post synopsis card. */
	.latest {
		margin: 1.6em 0;
		padding: 1.2em 1.4em;
		border: 1px solid #2a3a40;
		border-left: 4px solid #7fd9ff;
		border-radius: 0 8px 8px 0;
		background: rgba(127, 217, 255, 0.05);
	}
	.latest-label {
		margin: 0;
		font-size: 0.85em;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		opacity: 0.7;
	}
	.latest-title {
		margin: 0.2em 0 0.4em;
		font-size: 1.7em;
	}
	.latest-synopsis {
		margin: 0.4em 0 0.8em;
		line-height: 1.6;
	}
	.read-more {
		font-weight: bold;
	}

	h2 {
		margin-top: 1.6em;
	}
	ul.posts {
		list-style: none;
		padding-left: 0;
	}
	ul.posts li {
		padding: 0.6em 0;
		border-bottom: 1px solid #2a3a40;
		font-size: 1.15em;
	}
	ul.posts li .date {
		display: inline-block;
		min-width: 6.5em;
		font-family: 'Fira Code', monospace;
		font-size: 0.8em;
		opacity: 0.6;
	}
	ul.posts li a {
		font-weight: bold;
	}
	.meta {
		opacity: 0.8;
	}
	.more {
		opacity: 0.7;
		font-style: italic;
	}
	.links {
		margin-top: 2.5em;
	}
</style>
