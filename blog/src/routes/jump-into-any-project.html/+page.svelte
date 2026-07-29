<p class="dateline">Unpublished draft · Nawa Man</p>
<h1 id="jump-into-any-project">Jump Into Any Project with a Single Command</h1>
<p class="subtitle">Try these ready-to-run examples — and see how effortless your own projects could be.</p>

<p>
	Whether you're spinning up a lightweight utility script, a full data-science notebook, or a
	multi-container local Kubernetes environment, getting a project ready to run should never mean
	spending hours battling system dependencies.
	<strong><a href="https://codingbooth.io">CodingBooth</a> lets you bring up a fully isolated
	development environment quickly, correctly, and painlessly — with a single <code>booth</code>
	command.</strong>
</p>
<p>
	You don't need to install language toolchains, resolve version conflicts, or worry about
	root-owned files on your host; everything you need lives alongside the code. Let's look at how you
	can grab a pre-configured workspace and start building right away.
</p>

<h2>What Is CodingBooth?</h2>
<p>
	CodingBooth gives every project its own fully isolated, reproducible development environment — one
	that starts with a single command and stays consistent for everyone who uses it. Fast startup is
	the first thing you notice, but here's the rest of what you get. <strong>Isolation:</strong>
	everything a project installs stays inside its booth, so different toolchains never collide and a
	risky experiment's blast radius ends at the container. <strong>Shareability:</strong> the
	environment lives as plain text in a <code>.booth/</code> folder next to your code, so a teammate
	clones the repo, runs <code>booth</code>, and is at parity — no wiki, no manual sync.
	<strong>Your files stay yours:</strong> the booth runs with your host UID/GID, so anything you
	create inside is owned by you outside, with no root-owned artifacts.
	<strong>Fresh every time (ephemeral):</strong> a booth is built from its definition and discarded when you're
	done, so nothing accumulates or drifts — what you want to keep, you name explicitly. And
	<strong>many ways in:</strong> the same environment through different views — your terminal, a
	browser terminal, VS Code in the browser, Jupyter, or a full XFCE/KDE desktop — plus
	<code>booth shell</code> to attach and <code>booth exec</code> for a one-off command.
</p>

<h2>Installing It</h2>
<p>To install and run CodingBooth, you would need the following: </p>
<ul>
	<li><strong>Docker</strong> — the booth is a container</li>
	<li><strong>Bash</strong> or <strong>Zsh</strong> — the wrapper is a shell script allowing the CodingBooth core to evolve.</li>
	<li><strong>curl</strong> - for some downloads</li>
</ul>
<p>
	Linux, macOS, and Windows are all supported, on both x86-64 and ARM64. Installing is one line:
</p>
<pre><code>curl -fsSL https://codingbooth.io/install.sh | bash</code></pre>
<p>
	That drops a <code>booth</code> wrapper script in the current directory, downloads the matching
	binary, and wires up your shell so <code>booth</code> works from anywhere inside the project.
</p>
<p>
	Because it touches your shell configuration, the <code>booth</code> command won't be on your
	<code>PATH</code> in terminals you already have open. Either open a new one, or reload your
	profile:
</p>
<pre><code>source ~/.bashrc      # bash
source ~/.zshrc       # zsh</code></pre>

<h2>Try Examples</h2>
<p>
	Now the fun part. CodingBooth ships a catalog of ready-made <em>example workspaces</em> — complete,
	runnable projects, each with its environment already declared. Two commands: one to see what's
	there, one to take a copy.
</p>
<pre><code>booth example list                    # see what's available
booth example try &lt;name&gt; &lt;folder&gt;     # copy one into &lt;folder&gt;
cd &lt;folder&gt;
booth                                 # start it</code></pre>
<p>
	That bare <code>booth</code> at the end is the whole ceremony. It reads the project's
	<code>.booth/</code> folder, builds or fetches the right image, and brings the environment up in
	your browser. The examples are versioned alongside the release you have installed, so the one you
	download always matches the binary you're running.
</p>

<h2>Examples</h2>
<p>
	There are dozens in the catalog — the full list is in the <a href="#appendix">appendix</a> below.
	The three that follow are deliberately far apart: a single language runtime, a full graphical
	workbench, and an entire Kubernetes cluster. All three start the same way.
</p>

<h3><code>elixir</code> — getting a version pairing right</h3>
<p>
	A minimal Elixir program with a palindrome checker. It's small, but it earns its place: Elixir runs
	on the Erlang BEAM VM, and every Elixir release only supports a specific window of OTP versions.
	Pair them wrong by hand and you get cryptic BEAM load errors or a build that just refuses to
	compile — a classic first-day time sink.
</p>
<pre><code>booth example try elixir ./my-elixir
cd ./my-elixir &amp;&amp; booth</code></pre>
<p>
	The booth brings Elixir with a known-compatible Erlang/OTP already paired. Pin a different Elixir
	with the <code>ELIXIR_VERSION</code> build arg and you get a matching OTP along with it.
</p>

<h3><code>data</code> — a whole workbench, with GUIs</h3>
<p>
	This one is a single booth that stands up an entire graphical data-analysis stack. It seeds a
	Postgres <code>demo</code> database with a small <code>sales</code> table, then exposes that one
	dataset through four lenses at once:
</p>
<ul>
	<li><strong>DBeaver</strong> — a real graphical SQL client, pre-wired to the database</li>
	<li><strong>JupyterLab</strong> — a notebook that charts it with matplotlib</li>
	<li><strong>Sales Explorer</strong> — a small Node/Express dashboard with Chart.js filters</li>
	<li><strong>PostgreSQL</strong> — the database itself</li>
</ul>
<pre><code>booth example try data ./my-data
cd ./my-data &amp;&amp; booth</code></pre>
<p>
	It opens as an XFCE desktop in your browser, with DBeaver already on it. Postgres, DBeaver, Python,
	and Node never touch your host — and the whole workbench goes away when you stop the booth.
</p>

<h3><code>kind</code> — a Kubernetes cluster you can be careless with</h3>
<p>
	At the heavy end: a full Kubernetes cluster running inside the booth, via
	<a href="https://kind.sigs.k8s.io/" target="_blank" rel="noopener">KinD</a> on Docker-in-Docker.
	Control plane, nodes, and pods are all nested inside the container.
</p>
<pre><code>booth example try kind ./my-kind
cd ./my-kind &amp;&amp; booth
# then, inside the booth:
./start-cluster.sh
./deploy-app.sh</code></pre>
<p>
	The sample nginx app lands on NodePort 30080, reachable from your host browser. And you never
	installed kind, kubectl, or a container runtime on your own machine — so when you're done, deleting
	the cluster means stopping the booth. No lingering <code>~/.kube</code> config, no orphaned Docker
	networks, no wondering later why your laptop is running eight etcd pods.
</p>

<h2>Go Pick One</h2>
<p>
	The examples exist to be taken apart. Once one is running, open its <code>.booth/</code> folder and
	read it — that's the entire environment, usually a handful of lines. Change a version, add a
	<code>setup</code>, run <code>booth</code> again, and you've just configured your own project the
	same way the example was configured.
</p>
<p>
	That's really the argument. Not that these particular workspaces are useful to you, but that
	<em>your</em> project could start the same way: one file in the repo, one command, and everyone who
	clones it gets the environment you meant them to have.
</p>
<p>Happy coding!<br />Nawa Man</p>

<hr />

<h2 id="appendix">Appendix: The Full Catalog</h2>
<p>
	Every example below is available with
	<code>booth example try &lt;name&gt; &lt;folder&gt;</code>. The grouping is mine, for readability —
	the command itself prints a flat alphabetical list.
</p>

<h3>Languages &amp; runtimes</h3>
<p class="catalog">
	<code>all-java</code> <code>bun</code> <code>clang</code> <code>csharp</code> <code>deno</code>
	<code>elixir</code> <code>fsharp</code> <code>go</code> <code>haskell</code> <code>java</code>
	<code>js</code> <code>kotlin</code> <code>nodejs</code> <code>octave</code> <code>php</code>
	<code>python</code> <code>rlang</code> <code>ruby</code> <code>rust</code> <code>zig</code>
	<code>zig-snake</code>
</p>

<h3>Web frameworks &amp; full stacks</h3>
<p class="catalog">
	<code>angular</code> <code>django</code> <code>fastapi</code> <code>flask</code> <code>lamp</code>
	<code>lemp</code> <code>mean</code> <code>mern</code> <code>nextjs</code> <code>pern</code>
	<code>rails</code> <code>react</code> <code>spring-boot</code> <code>vaadin</code>
	<code>wordpress</code>
</p>

<h3>Data &amp; notebooks</h3>
<p class="catalog"><code>conda</code> <code>data</code></p>

<h3>Containers &amp; Kubernetes</h3>
<p class="catalog"><code>dind</code> <code>kind</code> <code>kind-app</code></p>

<h3>Cloud &amp; services</h3>
<p class="catalog">
	<code>aws</code> <code>firebase</code> <code>gcloud</code> <code>server</code>
</p>

<h3>Dependencies, caching &amp; system packages</h3>
<p class="catalog">
	<code>apt</code> <code>cache</code> <code>homebrew</code> <code>mvn-deps</code> <code>npm</code>
	<code>npm-deps</code> <code>pip</code> <code>pip-deps</code> <code>systemlib</code>
</p>

<h3>Testing &amp; browsers</h3>
<p class="catalog">
	<code>browser-shared</code> <code>playwright</code> <code>playwright-polyglot</code>
</p>

<h3>Editors &amp; AI tooling</h3>
<p class="catalog"><code>claude</code> <code>herdr</code> <code>neovim</code></p>

<h3>Security &amp; network isolation</h3>
<p class="catalog"><code>egress-allowlist-extra</code> <code>egress-envoy</code></p>

<h3>Starting points</h3>
<p class="catalog"><code>demo</code> <code>empty</code></p>
<p>
	<code>empty</code> is the bare minimum — just the wrapper and a blank config, a good base for your
	own project. <code>demo</code> is the opposite: a full showcase with notebooks and a sample app.
</p>

<h3>Where to find the current list</h3>
<p>
	This catalog grows between releases, so treat the list above as a snapshot. The authoritative,
	always-current answer is the command itself — it fetches the list published with the exact version
	you have installed:
</p>
<pre><code>booth example list</code></pre>
<p>
	For what each one is actually <em>demonstrating</em>, see
	<a href="https://github.com/NawaMan/CodingBooth/blob/main/docs/EXAMPLES_ADVANTAGES.md" target="_blank" rel="noopener">Examples &amp; Advantages</a>
	in the repo, which groups every workspace by the problem it solves, and
	<a href="https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_EXAMPLE.md" target="_blank" rel="noopener">the <code>booth example</code> reference</a>
	for the command's full flags.
</p>

<hr />

<h2>Learn More</h2>
<ul class="links">
	<li><a href="https://codingbooth.io">codingbooth.io</a> — the website</li>
	<li><a href="https://codingbooth.io/more.html">Deep dive</a> — more about CodingBooth</li>
	<li><a href="./2026-06-18.html#four-promises-of-a-booth">The Four Promises of a Booth</a> — what a booth guarantees</li>
	<li><a href="./2026-06-28.html#onboard-quick-onboard-right">Onboard Quick, Onboard Right</a> — getting in fast <em>and</em> correctly</li>
	<li><a href="https://github.com/NawaMan/CodingBooth">GitHub</a> — source &amp; issues</li>
</ul>

<nav class="post-nav">
	<span class="nav-prev"></span>
	<a class="nav-home" href="./">↑ back to the blog</a>
	<span class="nav-next"></span>
</nav>

<style>
	.dateline { font-size: 0.9em; opacity: 0.6; margin-bottom: 0.2em; }
	h1 { font-size: 2.5em; margin: 0 0 0.15em; line-height: 1.15; }
	.subtitle { font-size: 1.25em; opacity: 0.85; font-style: italic; margin-top: 0; }
	h2 { margin-top: 1.8em; color: #7fd9ff; }
	h3 { margin-top: 1.4em; opacity: 0.95; }
	p { line-height: 1.6; }
	a { color: #7fd9ff; }
	code { font-family: 'Fira Code', monospace; font-size: 0.9em; }
	em { color: #f0d27f; font-style: italic; }
	strong { color: #f0d27f; }

	ul li { margin: 0.5em 0; line-height: 1.6; }

	.catalog { line-height: 2.1; }
	.catalog code {
		background: #0e1112;
		border: 1px solid #2a3a40;
		border-radius: 4px;
		padding: 0.15em 0.45em;
		white-space: nowrap;
	}

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
