<script>
	import hiddenCosts from './HiddenCostsOfDevelopmentEnvironments.png';
</script>

<p class="dateline">28 June 2026 · Nawa Man</p>
<h1 id="onboard-quick-onboard-right">Onboard Quick, Onboard Right</h1>
<p class="subtitle">Getting into a project fast is only half the job — getting in <em>right</em> is the other half. Why onboarding shouldn't rely on luck.</p>

<p>
	Setting up a software development environment often feels deceptively simple. You pull a
	repository, run a few standard install commands, and start writing code. Depending on how that
	goes, you usually fall into one of three buckets:
</p>

<ul class="buckets">
	<li><strong>Really Lucky:</strong> Everything works perfectly, and you never have to think about your environment again.</li>
	<li><strong>A Bit Lucky:</strong> The setup fails immediately. You hit a missing dependency or a hard version conflict right away. It is frustrating, but you are forced to resolve the roadblock before you can start working.</li>
	<li><strong>Unlucky:</strong> It appears to work.</li>
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

<h2>Why It Matters, Project by Project</h2>
<p>
	“Quick and right” pays off differently depending on what you're building. Here's what it buys a few
	common kinds of project — and why the cost of getting it wrong lands hardest there.
</p>

<h3>Data Science &amp; Notebooks</h3>
<p>
	A notebook's output <em>is</em> the deliverable, and that output depends on the exact versions of
	numpy, pandas, and a stack of native libraries underneath them. A 0.1 bump in a numerical library
	can quietly change a result. A booth pins the whole stack and ships the Jupyter front-end with it,
	so a result that reproduces on your machine reproduces on your colleague's — and on the same
	notebook a year from now.
</p>
<pre><code># .booth/Boothfile
setup python+notebook</code></pre>

<h3>JVM Services</h3>
<p>
	“Java is Java” right up until a different JDK <em>vendor</em> or major version changes behavior, or
	a teammate's Maven build resolves a slightly different dependency tree. For a long-lived service,
	that's the gap between green CI and a 2 a.m. page. Pinning the JDK and build tool in the booth means
	the bytecode you build locally is the bytecode that ships.
</p>
<pre><code># .booth/Boothfile
setup java+maven</code></pre>

<h3>Web Frontends</h3>
<p>
	Front-end builds are famously sensitive to the Node version and to native modules compiled against
	it — the classic “delete <code>node_modules</code> and pray” loop. When the runtime is pinned in the
	booth, the lockfile resolves the same way for everyone, and a new contributor goes from clone to a
	running dev server without a single version-manager incantation.
</p>

<h3>Compiled &amp; Systems Languages</h3>
<p>
	With Rust, Go, or C/C++, the compiler version isn't a detail — it decides whether the code builds at
	all, and sometimes how it behaves. Reproducing a teammate's build error is miserable when you can't
	even be sure you share a compiler. A booth makes the toolchain part of the repo, so “works for me”
	and “works for you” finally mean the same toolchain.
</p>

<h3>Apps with Live Services</h3>
<p>
	The moment a project needs Postgres, Redis, or Kafka, onboarding stops being about code and starts
	being about infrastructure — install the engine, match the version, get it running, seed it. A booth
	brings those services up as part of the environment, pinned to a version, so a new developer gets a
	working database on the first command instead of a half-day of setup. And because it's isolated, two
	projects can each run their own Postgres without fighting over a port or a global install.
</p>
<pre><code># .booth/Boothfile
setup postgresql</code></pre>

<h3>Teaching &amp; Workshops</h3>
<p>
	Nothing derails a class faster than thirty laptops in thirty slightly different states. When the
	environment ships with the materials, every student is at parity on minute one — and the grader runs
	in the same booth the students used, so “it ran in class” and “it passes grading” can't disagree.
	Onboarding quick keeps the room moving; onboarding right keeps the grades fair.
</p>

<h3>AI-Assisted Development</h3>
<p>
	Handing an AI assistant a shell is exactly the case where isolation earns its keep. Let it run
	<code>go install that@latest</code> or try a risky upgrade inside the booth, and the blast radius
	stays in the booth — if it goes wrong, you throw the booth away and start clean, with nothing leaked
	onto your host. And because the booth is reproducible, whatever the assistant set up is something
	your teammates can rebuild exactly, not a one-off that lives only on your machine.
</p>
<pre><code># .booth/Boothfile
setup claude-code</code></pre>

<h2>Quick and Right, One Command</h2>
<p>
	Quick onboarding gets people working today; right onboarding keeps them — and everyone after them —
	working without paying the creeping tax. You don't have to choose between the two, and neither should
	rely on luck or constant vigilance. Declare the environment once in the repo, and every clone after
	that is both fast and correct by construction.
</p>

<h2>See It in Action</h2>
<p>
	The idea is only convincing if you can run it. Each of these is a ready-made booth you can fetch and
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
<pre><code>$ ./booth -- ./run-fsharp.sh
=== A tour of F# in CodingBooth ===

Squares of evens (1..20): [4; 16; 36; 64; 100; 144; 196; 256; 324; 400]
FizzBuzz (1..15): 1 2 Fizz 4 Buzz Fizz 7 8 Fizz Buzz 11 Fizz 13 14 FizzBuzz
(2 + 3) * (10 - 4) = 30
First 10 Fibonacci: [0; 1; 1; 2; 3; 5; 8; 13; 21; 34]</code></pre>

<h3>Skip the dependency hell — <code>playwright</code></h3>
<p>
	Playwright's pain is environmental: browser binaries, a pile of system libraries, and a browser build
	that must match the Playwright version or your tests flake in CI. The booth pre-bakes the browser
	<em>pinned to the project's version</em>, so the documented command just runs — and it drives a real
	browser against real pages, not a mock:
</p>
<pre><code>$ ./booth -- ./run-playwright.sh
  ✓  1 [chromium] › basic browser test (58ms)
  ✓  2 [chromium] › javascript evaluation (34ms)
  2 passed (823ms)

$ ./booth -- ./run-screenshot.sh
Visiting https://news.ycombinator.com/ ...
Page title: Hacker News
Screenshot saved to screenshot.png</code></pre>
<!-- SCREENSHOT (slot in): Hacker News front page captured by headless Chromium inside the booth. -->

<h3>The same desktop for everyone — <code>java</code></h3>
<p>
	Java onboarding is all sprawl: JDK vendor and version, a Maven that has to match CI, and GUI IDEs that
	each need installing. This booth brings up a full Linux desktop with Eclipse <em>and</em> IntelliJ IDEA
	on a pinned JDK and Maven — so everyone lands on the same desk instead of reconciling toolchains for a
	week.
</p>
<pre><code>$ ./booth -- 'java -version; mvn -version'
openjdk version "25.0.3" 2026-04-21 LTS (Temurin-25.0.3+9)
Apache Maven 3.9.12</code></pre>
<!-- SCREENSHOT (slot in): the XFCE desktop with IntelliJ IDEA / Eclipse open. -->

<h3>Credentials that never enter the image — <code>aws</code></h3>
<p>
	Cloud work is the riskiest thing to rush: copy a key into an image and it can leak through every push
	and cache. This booth mounts your host credentials <em>read-only</em> at runtime, so the image stays
	generic and the secret never leaves your machine — yet the CLI really talks to your account:
</p>
<pre><code>$ ./booth -- ./check-connection.sh
Checking AWS connection...
✅ AWS connection OK</code></pre>
<p>
	That's a real <code>aws sts get-caller-identity</code>, with the AWS CLI pinned to one version for the
	whole team — quick to onboard, and the dangerous part stays on the host.
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
