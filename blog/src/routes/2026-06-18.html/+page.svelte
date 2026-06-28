<script>
	import overview    from './Overview.png';
	import hostVsBooth from './Host-vs-Booth.png';
	import variants    from './Variants.png';
</script>

<p class="dateline">18 June 2026 · Nawa Man</p>
<h1 id="four-promises-of-a-booth">The Four Promises of a Booth</h1>
<p class="subtitle">Isolation, repeatability, shareability, and usability — the four things a booth gives every project.</p>

<figure class="hero">
	<img src={overview} alt="Overview of CodingBooth: each project gets its own isolated, reproducible, shareable development environment" />
	<figcaption>One booth per project — declared in the repo, brought up with one command.</figcaption>
</figure>

<p>
	<a href="https://codingbooth.io">CodingBooth</a> improves your — and your team's — development
	experience by eliminating the “it works only on my machine” problem. It does this by giving every
	project its own fully isolated environment.
</p>
<p>
	I've written before about
	<a href="./2026-05-29.html#works-on-my-machine">why the “works on my machine” problem keeps happening</a>.
	This post takes a different cut: the <strong>four promises</strong> a booth makes to every project
	it wraps. Get all four at once and the environment stops being a variable.
</p>
<p class="video-aside">
	Prefer to watch? Here's the same idea as a
	<a href="https://www.youtube.com/shorts/6ahi72ym3jk" target="_blank" rel="noopener">YouTube Shorts video</a>.
</p>

<h2>1. Isolation — What Happens in the Booth Stays in the Booth</h2>
<p>
	Any activity inside a project stays inside its isolated environment and never touches your host
	system. Each project gets its own dedicated booth, so you can work on several projects at once
	without conflicts — no shared global runtime, no <code>PATH</code> entry bleeding from one project
	into the next.
</p>
<p>
	That same isolation is what makes a booth a safe place to experiment. Install a sketchy CLI, let an
	AI assistant run <code>go install that@latest</code>, try a risky upgrade — if it goes wrong, you
	throw the booth away and start clean. Nothing leaked onto your machine, and no other project
	noticed.
</p>

<figure>
	<img src={hostVsBooth} alt="A messy host machine versus a clean, isolated booth holding only the current project" />
	<figcaption>The blast radius of anything you do lives inside the booth, not on your host.</figcaption>
</figure>

<h2>2. Repeatability — The Same Environment Every Time</h2>
<p>
	A booth is created exactly according to its definition, which makes it fully repeatable. It's spun
	up when you need it and thrown away when you're done, so you always get the same consistent
	environment — not “close enough,” but the same image with the same tools at the same versions.
</p>
<p>
	Because the definition is plain text living in <code>.booth/</code>, it can be version controlled
	right alongside your code. The environment changes when the repo changes, reviewed in the same pull
	request as everything else.
</p>
<pre><code># .booth/Boothfile
setup java+maven
setup claude-code</code></pre>
<p>
	Two lines, and the environment is pinned. Run <code>./booth</code> today or in two years and you
	get the same toolchain — no drift, no “it used to build.”
</p>

<h2>3. Shareability — Onboarding in One Command</h2>
<p>
	Because the definition is shareable, every team member gets an identical environment. Clone the
	repo, run the booth, and you're at parity with the rest of the team — same versions, same CLIs,
	same defaults. Onboarding goes from a day of platform-specific debugging to a single command.
</p>
<pre><code>git clone &lt;repo&gt; &amp;&amp; cd &lt;repo&gt; &amp;&amp; ./booth</code></pre>
<p>
	This is the move that actually retires “works on my machine.” The environment isn't described in an
	onboarding wiki that nobody updates — it <em>is</em> the repo. New teammates, future-you reviving a
	dormant project, students handed a workshop repo: everyone runs the same booth.
</p>

<h2>4. Usability — A Terminal, or a Full Desktop</h2>
<p>
	All of this is delivered in a highly usable way. You can interact with the booth through a
	terminal, browser-based VS Code, a Jupyter notebook, or even a full Linux desktop — same
	environment underneath, different lens on top.
</p>

<figure>
	<img src={variants} alt="CodingBooth variants: terminal, browser VS Code, Jupyter notebook, and a full Linux desktop, all sharing one environment" />
	<figcaption>Attach how you like — the variant is just a front-end on the same booth.</figcaption>
</figure>

<p>
	CodingBooth also handles file permissions seamlessly by matching your host user ID and group ID.
	Every file you create or edit inside the booth is owned by <em>you</em> on the host — no
	<code>chown</code> dance, no root-owned artifacts left behind.
</p>
<p>
	And the booth definition itself is intuitive: it ships pre-loaded with useful built-in setups and
	templates, plus an easy-to-use configuration tool. You rarely start from a blank file — you pick
	what you need and let the tool write the <code>.booth/</code> folder for you.
</p>
<pre><code>booth config</code></pre>

<h2>Four Promises, One Command</h2>
<p>
	Isolation keeps your host clean. Repeatability keeps the environment honest. Shareability gets your
	whole team to parity. Usability makes it something you actually want to live in. Each one is useful
	on its own; together they're what makes “works on my machine” a problem you stop having.
</p>
<p>Installing CodingBooth is one command:</p>
<pre><code>curl -fsSL https://codingbooth.io/install.sh | bash</code></pre>
<p>Start using CodingBooth in your project today — and thank me later.</p>
<p>Happy coding!<br />Nawa Man</p>

<hr />

<h2>Learn More</h2>
<ul class="links">
	<li><a href="https://codingbooth.io">codingbooth.io</a> — the website</li>
	<li><a href="https://codingbooth.io/more.html">Deep dive</a> — more about CodingBooth</li>
	<li><a href="https://github.com/NawaMan/CodingBooth">GitHub</a> — source &amp; issues</li>
</ul>

<nav class="post-nav">
	<a class="nav-prev" href="./2026-05-29.html#works-on-my-machine">← Ending “It Works on My Machine”</a>
	<a class="nav-home" href="./">↑ back to the blog</a>
	<span class="nav-next"></span>
</nav>

<style>
	.dateline { font-size: 0.9em; opacity: 0.6; margin-bottom: 0.2em; }
	h1 { font-size: 2.5em; margin: 0 0 0.15em; line-height: 1.15; }
	.subtitle { font-size: 1.25em; opacity: 0.85; font-style: italic; margin-top: 0; }
	h2 { margin-top: 1.8em; color: #7fd9ff; }
	p { line-height: 1.6; }
	a { color: #7fd9ff; }
	code { font-family: 'Fira Code', monospace; font-size: 0.9em; }
	em { color: #f0d27f; font-style: italic; }

	figure { margin: 1.8em 0; text-align: center; }
	figure img { max-width: 70%; height: auto; border-radius: 6px; box-shadow: 0 2px 12px rgba(0,0,0,0.35); }
	figcaption { margin-top: 0.5em; font-size: 0.9em; opacity: 0.7; font-style: italic; }

	.video-aside {
		margin: 1.5em 0;
		padding: 0.75rem 1rem;
		border-left: 3px solid #7fd9ff;
		background: rgba(255,255,255,0.04);
		border-radius: 0 4px 4px 0;
		font-size: 0.95em;
		font-style: italic;
	}
	.video-aside a { font-style: normal; }

	pre {
		background: #0e1112;
		border: 1.5px solid #2a3a40;
		border-radius: 10px;
		padding: 1em 1.3em;
		overflow-x: auto;
		margin: 1.2em 0;
	}
	pre code {
		font-family: 'Fira Code', monospace;
		font-size: 0.95em;
		line-height: 1.6;
		color: #cfe9f1;
		white-space: pre;
	}

	hr { border: 0; border-top: 1px solid #2a3a40; margin: 2.5em 0 1.5em; }
	ul.links li { margin: 0.3em 0; }

	.post-nav {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: 1.5em;
		margin-top: 2.5em;
		padding-top: 1.2em;
		border-top: 1px solid #2a3a40;
		font-size: 0.95em;
	}
	.post-nav .nav-prev { flex: 1; text-align: left; }
	.post-nav .nav-home { flex: 0 0 auto; text-align: center; opacity: 0.8; }
	.post-nav .nav-next { flex: 1; text-align: right; }
</style>
