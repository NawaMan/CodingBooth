<script>
	import infographic from './infographic.png';
	import frustrated  from './Dev-Frustrated-with-Errors.png';
	import variants    from './Variants.png';
</script>

<p class="dateline">29 May 2026 · Nawa Man</p>
<h1 id="works-on-my-machine">Ending “It Works on My Machine” with CodingBooth</h1>
<p class="subtitle">When the environment stops being a variable, teams can focus on the code.</p>

<figure class="hero">
	<img src={infographic} alt="CodingBooth infographic: the problem, the hidden cost of environmental chaos, how CodingBooth solves it, and real team benefits" />
	<figcaption>The whole article in one picture.</figcaption>
</figure>

<p>
	We've all been there. Your code runs perfectly on your laptop. You push it to the repository,
	and suddenly everything breaks for your teammate or in CI/CD. Hours — sometimes days — disappear
	into debugging environment differences, version conflicts, flaky tests, and mysterious
	production failures.
</p>
<p>This classic problem has a name: <em>“It works on my machine.”</em></p>
<p>
	<a href="https://codingbooth.io">CodingBooth</a> aims to eliminate that pain point once and for
	all by giving every project its own isolated, repeatable, and shareable development environment.
</p>
<p class="video-aside">
	Prefer to watch? Here's the same pitch as a
	<a href="https://youtube.com/shorts/gjRgz0RU2wU" target="_blank" rel="noopener">YouTube Shorts video (about 2½ minutes)</a>.
</p>

<h2>The Hidden Cost of Environmental Chaos</h2>
<p>
	The “works on my machine” problem isn't one bug — it's the accumulated weight of failed
	experiments left behind, conflicting global tools, undocumented quick fixes, AI assistants
	quietly mutating configs, and tests that pass or fail depending on whose laptop they run on. The
	result is lost setup time, surprise production outages, eroded team trust, and an onboarding
	experience measured in days instead of minutes.
</p>

<figure class="frustrated-dev">
	<img src={frustrated} alt="A developer frustrated by a screen full of environment errors that don't reproduce anywhere else" />
	<figcaption>Lost hours chasing “works on my machine” — the hidden cost of environmental chaos.</figcaption>
</figure>

<h2>How CodingBooth Solves It</h2>
<p>
	CodingBooth puts the entire development environment in your repository — declared in a
	<code>.booth/</code> folder, brought up with one command, contained in a container. Tools run
	inside, not on your host. Every teammate gets exactly the same setup automatically. Spin up a
	fresh one any time; no drift, no hidden state. UID/GID mapping is handled for you so files stay
	yours. Attach via terminal, browser VS Code, Jupyter, or a full Linux desktop — same environment
	underneath, different lens on top.
</p>

<figure class="variants">
	<img src={variants} alt="CodingBooth attach variants: terminal, browser VS Code, Jupyter, and a full Linux desktop, all sharing the same environment" />
	<figcaption>Attach how you like — same environment underneath, different lens on top.</figcaption>
</figure>

<p>
	The payoff for teams: instant onboarding, identical environments across every machine, a host
	that stays clean, and setups that are still usable months or years later when you come back to a
	dormant project.
</p>

<h2>The Bottom Line</h2>
<p>
	CodingBooth doesn't just solve a technical problem — it restores confidence in the development
	process. When the environment is no longer a variable, teams can focus on what actually matters:
	writing great code.
</p>
<p>
	Production is containerized. CI is containerized. The development loop — where developers actually
	spend their day — finally can be too. Put CodingBooth in your project and thank yourself (and your
	team) later.
</p>
<p>Happy coding!<br />Nawa Man</p>

<hr />

<h2>Learn More</h2>
<ul class="links">
	<li><a href="https://codingbooth.io">codingbooth.io</a> — the website</li>
	<li><a href="https://codingbooth.io/more.html">Deep dive</a> — more about CodingBooth</li>
	<li><a href="https://github.com/NawaMan/CodingBooth">GitHub</a> — source &amp; issues</li>
</ul>

<nav class="post-nav">
	<span class="nav-prev"></span>
	<a class="nav-home" href="./">↑ back to the blog</a>
	<a class="nav-next" href="./2026-06-18.html#four-promises-of-a-booth">The Four Promises of a Booth →</a>
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
	figure img { max-width: 100%; height: auto; border-radius: 6px; box-shadow: 0 2px 12px rgba(0,0,0,0.35); }
	figure.frustrated-dev img, figure.variants img { max-width: 70%; }
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
