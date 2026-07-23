<script>
	import hiddenCosts   from './HiddenCostsOfDevelopmentEnvironments.png';
	import screenshot    from './screenshot.png';
	import dataDesktop   from './data-desktop.jpg';
	import dataDashboard from './data-dashboard.jpg';
</script>

<p class="dateline">28 June 2026 · Nawa Man</p>
<h1 id="onboard-quick-onboard-right">Onboard Quick, Onboard Right</h1>
<p class="subtitle">Getting into a project fast is only half the job — getting in <em>right</em> is the other half. Why onboarding shouldn't rely on luck.</p>

<p>
	When we think about software development, we often think about adding or changing of code and the understanding of the code before that.
	Setting up the development environment is often overlook until someone on-broard the project who are not familiar with the toolchain.
	The setup can range from just having the compiler to multiple setup steps and be a simple sentense like "Use python" to super complext make file.
	Even with an automate installtion script, it is not always up to date and/or work with different environment.
	There also "multiple project" interferances like version conflict or worst "almost" conflict.
	Depending on how that goes, you usually fall into one of three buckets:
</p>

<ul class="buckets">
	<li><strong>Really Lucky:</strong>
		Everything works perfectly, and you never have to think about your environment again.
	</li>
	<li><strong>A Bit Lucky:</strong>
		The setup fails immediately. You hit a missing dependency or a hard version conflict right away. 
		It is frustrating, but you are forced to resolve the roadblock before you can start working.
		Fixing the problem might not always success so you can't proceed OR it can bring you to the next category "Unlucky".
	</li>
	<li><strong>Unlucky:</strong>
		The setup appears to work so the development proceed while discrepancies are still there waiting to cause problem.
	</li>
</ul>

<figure class="hero">
	<img src={hiddenCosts} alt="The hidden costs of development environments: the Really Lucky, A Bit Lucky, and Unlucky onboarding paths, and the slow creeping tax of invisible discrepancies that the Unlucky path hides" />
	<figcaption>Three ways onboarding goes — and the creeping tax the “good enough” path hides.</figcaption>
</figure>

<p>
	For many developers, that “good enough” setup in the third bucket is where the process ends,
	allowing them to push forward without much thought. But the real cost of environment management
	isn't an upfront roadblock — it's the slow, creeping tax of invisible discrepancies.
</p>
<p>
	A minor version difference in a compiler, a globally installed package that silently alters a
	project's behavior, or a toolchain update that inexplicably breaks an older codebase months later.
	These issues don't stop you on day one; they surface as mysterious bugs during code review or
	broken builds in CI. Too often, we just accept this fragile state and the inevitable “works on my
	machine” conversations as a frustrating fact of life. CodingBooth was built because keeping your
	environment reproducible and isolated shouldn't rely on luck or constant vigilance.
</p>

<h2>Onboard Quick</h2>
<p>
	Quick onboarding means the distance between “I have the repo” and “I'm writing code” is a single
	command. No README full of platform-specific install steps, no afternoon spent chasing a missing
	system library, no Slack thread asking which version of the toolchain everyone else is on. You
	clone, you run the booth, and the environment builds itself.
</p>
<pre><code>git clone &lt;repo&gt; &amp;&amp; cd &lt;repo&gt; &amp;&amp; ./booth</code></pre>
<p>
	The environment is declared in the repo, in a small <code>.booth/</code> folder, so the very first
	command a new teammate runs is also the command that gives them the <em>exact</em> setup. There's
	nothing to install by hand and nothing to get subtly wrong. A new hire, a teammate switching
	branches, or future-you reviving a dormant project all reach a working environment in minutes —
	not on day three.
</p>

<h2>Onboard Right</h2>
<p>
	Quick is only half of it. The “Unlucky” path from the start of this post is quick too — it just
	happens to be wrong in ways you won't notice for weeks. Onboarding <em>right</em> means everyone
	gets the same image: the same compiler at the same version, the same libraries, the same running
	services, every time the booth is built.
</p>
<p>
	Because the booth is created from its definition and thrown away when you're done, there's no
	long-lived machine accumulating drift. The definition lives in version control next to your code,
	so the environment changes only when the repo changes — reviewed in the same pull request as
	everything else. That's what turns off the creeping tax: no minor version difference sneaking in, no
	globally installed package silently changing behavior, no “it used to build.” The environment stops
	being a variable, so the only thing left to explain a bug is the code itself.
</p>

<h2>CodingBooth: Quick and Right OnBoarding with One Command</h2>
<p>
	Quick onboarding gets people working today;
		right onboarding keeps them and everyone after them working without paying the creeping tax.
	You don't have relia on luck to get both.
	Declare the environment once in the repo, and every clone after that is both fast and correct by construction.
</p>

<h2>See It in Action</h2>
<p>
	The idea is only convincing if you can run it.
	Each of these is a ready-made booth you can fetch and
	launch in two commands — <code>booth example try</code> to grab it, then one command to run. Every
	line of output below is real, captured from an actual run; browse the full set with
	<code>booth example list</code>.
</p>
<pre><code>./booth example try fsharp ./fsharp-demo</code></pre>

<h3>Try a language without committing — <code>fsharp</code></h3>
<p>
	The friction in <em>evaluating</em> a language is the install: the .NET SDK is a heavy thing to put
	on your machine for a weekend's curiosity. In a booth it's one command, nothing on your host, and the
	.NET version is pinned — so the playground behaves the same for whoever you send it to. That's quick
	(no install) and right (reproducible) at the same time.
</p>
<pre><code>$ ./booth --silence-build -- ./run-fsharp.sh      # Run `./run-fsharp.sh` inside booth.

== customers.csv ==
customer_id,age,annual_income_k,spending_score
1,25,25,18
2,28,22,15
3,23,30,22
...            # More data
29,38,57,51
30,33,51,46

=== Customer analytics (F# in CodingBooth) ===
Loaded 30 customers from customers.csv

Summary statistics:
  age               mean=  33.8  min=  22.0  max=  48.0  std=  6.6
  income (k$)       mean=  55.2  min=  21.0  max=  92.0  std= 24.8
  spending (1-100)  mean=  50.3  min=  12.0  max=  90.0  std= 26.5

K-means clustering (k=3) on income vs spending:
  Segment 1: 10 customers | centroid income= 25.5k spending=18.5
             customers: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  Segment 2: 10 customers | centroid income= 54.6k spending=49.6
             customers: 21, 22, 23, 24, 25, 26, 27, 28, 29, 30
  Segment 3: 10 customers | centroid income= 85.6k spending=82.7
             customers: 11, 12, 13, 14, 15, 16, 17, 18, 19, 20

</code></pre>

You can play around with the code, make changes and rerun, all these <b>without</b> having to install f-sharp (dotnet).

<h3>Skip the dependency hell — <code>playwright</code></h3>
<p>
	Playwright's pain is environmental: browser binaries, a pile of system libraries, and a browser build
	that must match the Playwright version or your tests flake in CI. The booth pre-bakes the browser
	<em>pinned to the project's version</em>, so the documented command just runs — and it drives a real
	browser against real pages, not a mock:
</p>
<pre><code>$ ./booth -- ./run-screenshot.sh
Visiting https://news.ycombinator.com/ ...
Page title: Hacker News
Screenshot saved to screenshot.png</code></pre>

<figure>
	<img src={screenshot} alt="The Screenshot of Hacker News" />
	<figcaption>The Screenshot of Hacker News.</figcaption>
</figure>

<h3>The system-library dance, done once — <code>systemlib</code></h3>
<p>
	The hard part of C and C++ isn't the compiler — it's the libraries. You need the right
	<code>libxxx-dev</code> packages so the headers <em>and</em> the shared objects are present, you
	need the build to find and link them, and you need everyone on the <em>same</em> versions or you
	get an "undefined reference" on one machine and a subtly different bug on another. A booth bakes the
	libraries in, pinned, so the build just resolves them:
</p>
<pre><code>$ ./booth -- ./run-linkcheck.sh
-- Found CURL: /usr/lib/x86_64-linux-gnu/libcurl.so (found version "8.5.0")
-- Found SQLite3: /usr/lib/x86_64-linux-gnu/libsqlite3.so (found version "3.45.1")
[100%] Built target linkcheck

URL                                              RESULT STATUS
------------------------------------------------ ------ ------
https://www.iana.org/                            ALIVE  200
https://www.google.com/                          ALIVE  200
https://www.google.com/this-page-does-not-exist  DEAD   DEAD: HTTP 404
https://this-host-does-not-exist-9x8y7z.invalid  DEAD   DEAD: Couldn't resolve host name

Summary: 2 alive, 2 dead. Recorded 4 rows to linkcheck.db</code></pre>
<p>
	The program is a link checker: it reads a list of URLs, checks each one with <em>libcurl</em>, and
	records every result — URL, timestamp, status — into a <em>SQLite</em> database. Two real system
	libraries, installed with <code>apt</code> and linked by CMake's <code>find_package</code> — exactly
	the part header-only libraries let you skip. Nothing lands on your host, and the pinned
	<code>APT_SNAPSHOT</code> means the same library versions build for everyone, every time.
</p>

<h3>A whole stack on your laptop, then gone — <code>kind-app</code></h3>
<p>
	The hardest onboarding is the realistic one. This booth bakes Docker-in-Docker, KinD, kubectl, Go, Bun
	and Python — all pinned — and stands up a real React + Go + PostgreSQL app on an in-container Kubernetes
	cluster from one command chain:
</p>
<pre><code>$ ./booth -- './start-cluster.sh &amp;&amp; ./build.sh &amp;&amp; ./deploy-app.sh &amp;&amp; ./status.sh'
=== Deployment complete ===
NAME                 READY   STATUS    RESTARTS   AGE
api-...              1/1     Running   0          8s
export-service-...   1/1     Running   0          9s
postgres-...         1/1     Running   0          22s
web-...              1/1     Running   0          8s

✔ SUCCESS: Cluster 'kind' is UP
kind-control-plane   Ready   control-plane   87s   v1.32.2</code></pre>
<!-- SCREENSHOT (slot in): the running TODO app in the browser, and/or `kubectl get pods`. -->
<p>
	The cluster lives <em>inside</em> the booth, so tearing it down is just stopping the booth — your host
	is left exactly as clean as it started.
</p>

<h3>Batteries included, GUIs and all — <code>data</code></h3>
<p>
	A data project is a pile of separate installs that all have to agree: a database, a SQL client,
	Python with the right libraries, a notebook server. This booth bakes the whole workbench —
	<em>PostgreSQL, DBeaver, JupyterLab, Python with matplotlib and psycopg2, and a small web
	dashboard</em> — and wires every one of them to the <em>same</em> seeded dataset. It's the
	<code>kind-app</code> idea made graphical: instead of a cluster on the command line, one command opens
	a full desktop in your browser with the tools already running.
</p>
<pre><code>$ ./booth        # opens an XFCE desktop in your browser</code></pre>
<figure>
	<img src={dataDesktop} alt="An XFCE desktop running in the browser, with DBeaver, JupyterLab, Visual Studio Code, Firefox and Chrome all sitting on the CodingBooth wallpaper" />
	<figcaption>One command, a whole desktop of tools — DBeaver, JupyterLab and VS Code, all in the browser.</figcaption>
</figure>
<p>
	DBeaver opens with its connection to the demo database <em>already configured</em>; JupyterLab is up
	with a notebook that queries the data and charts it with matplotlib; and a Sales Explorer dashboard
	is serving live rows straight from PostgreSQL. One dataset, seen through every lens at once:
</p>
<figure>
	<img src={dataDashboard} alt="The Sales Explorer web dashboard: filters, summary stat cards, and two bar charts of revenue and quantity by category, all drawn from the seeded PostgreSQL data" />
	<figcaption>The Sales Explorer dashboard — real rows from the booth's PostgreSQL, charted in the browser.</figcaption>
</figure>
<p>
	Stop the booth and the whole workbench — database, notebook, dashboard, every GUI — is gone, with
	nothing left installed on your host.
</p>

<p>Installing CodingBooth is one command:</p>
<pre><code>curl -fsSL https://codingbooth.io/install.sh | bash</code></pre>
<p>Happy coding!<br />Nawa Man</p>

<hr />

<h2>Learn More</h2>
<ul class="links">
	<li><a href="https://codingbooth.io">codingbooth.io</a> — the website</li>
	<li><a href="https://codingbooth.io/more.html">Deep dive</a> — more about CodingBooth</li>
	<li><a href="https://github.com/NawaMan/CodingBooth">GitHub</a> — source &amp; issues</li>
</ul>

<nav class="post-nav">
	<a class="nav-prev" href="./2026-06-18.html#four-promises-of-a-booth">← The Four Promises of a Booth</a>
	<a class="nav-home" href="./">↑ back to the blog</a>
	<span class="nav-next"></span>
</nav>

<style>
	.dateline { font-size: 0.9em; opacity: 0.6; margin-bottom: 0.2em; }
	h1 { font-size: 2.5em; margin: 0 0 0.15em; line-height: 1.15; }
	.subtitle { font-size: 1.25em; opacity: 0.85; font-style: italic; margin-top: 0; }
	h2 { margin-top: 1.8em; color: #7fd9ff; }
	h3 { margin-top: 1.5em; margin-bottom: 0.3em; color: #cfe9f1; font-size: 1.15em; }
	p { line-height: 1.6; }
	a { color: #7fd9ff; }
	code { font-family: 'Fira Code', monospace; font-size: 0.9em; }
	em { color: #f0d27f; font-style: italic; }

	ul.buckets { line-height: 1.6; }
	ul.buckets li { margin: 0.5em 0; }
	ul.buckets strong { color: #7fd9ff; }

	figure { margin: 1.8em 0; text-align: center; }
	figure img { max-width: 70%; height: auto; border-radius: 6px; box-shadow: 0 2px 12px rgba(0,0,0,0.35); }
	figure.hero img { max-width: 100%; }
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
