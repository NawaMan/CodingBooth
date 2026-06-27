<!--
  Blog index — served at the site root `/` (i.e. codingbooth.io/blog/).

  Built as a Text artifact (shares the TextPage shell). Its job is to say what
  the blog is and then list the posts. Each post is its own route folder (a
  presentation deck or a Text); add a new <li> here when you publish one.
  Links are relative to `/`, so they resolve to sibling post routes
  (e.g. /welcome/title.html).
-->
<h1>The CodingBooth Blog</h1>

<p class="lede">
	Notes from inside the booth — short, focused deep dives into the bits and pieces that make
	CodingBooth tick.
</p>

<p>
	<a href="https://codingbooth.io">CodingBooth</a> delivers fully reproducible, isolated
	development environments in a Docker container that runs as <i>you</i>, with your project
	files staying yours on the host. This blog takes it apart one piece at a time — a feature,
	a design decision, or a workflow per post.
</p>

<p>
	Each post comes in two shapes: click through it as a slide deck, or read it as a long-form
	page. New posts land here over time.
</p>

<h2>Posts</h2>

<ul class="posts">
	<li>
		<a href="welcome/title.html">Welcome to the CodingBooth Blog</a>
		<span class="meta"> — what this is, and what's coming.</span>
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
	.lede {
		font-size: 1.25em;
		font-weight: bold;
		opacity: 0.95;
	}
	a {
		color: #7fd9ff;
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
