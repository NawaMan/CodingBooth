// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"

	"golang.org/x/term"
)

// A silenced build still has to say *something*. `--silence-build` exists so a
// booth launch isn't buried under a hundred lines of BuildKit output, but a step
// like `RUN codeserver--setup.sh` can spend eight minutes pulling a 224 MB
// tarball without printing a byte, and a terminal that has shown nothing for
// eight minutes is indistinguishable from a hung one.
//
// So: draw one line, in place, and erase it when the build ends. The scrollback
// stays as clean as it was before — the line never survives the build — but
// while the build runs there is always a step name and a ticking clock to look
// at. This is the shape `docker build` itself uses for its progress rows.
//
// Everything BuildKit writes still goes to the capture buffer verbatim, so the
// failure path prints the full log exactly as it did before.

const (
	// Don't flash a line for a build that's over before it's read. Cached
	// rebuilds finish in a couple of seconds; those stay as silent as they were.
	progressStartDelay = 400 * time.Millisecond

	// Fast enough that the clock looks live, slow enough to cost nothing.
	progressFrameRate = 120 * time.Millisecond

	// A `curl` progress meter rewrites one line with \r for the whole download,
	// so a "line" can reach megabytes before its newline arrives. Keep the tail
	// (which is where the current state is) and drop the rest.
	progressMaxPartial = 64 * 1024
	progressKeepTail   = 4 * 1024

	progressFallbackWidth = 80
)

var progressSpinner = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

var (
	// BuildKit's plain progress prefixes every line with its vertex: `#8 ...`.
	progressVertexRe = regexp.MustCompile(`^#(\d+)\s+(.*)$`)
	// Within a vertex, output lines carry the step-relative timestamp: `#8 3.047 msg`.
	// The message is optional: a step that prints a blank line arrives as a bare
	// `#8 20.10`, which must stay an output line — read as a vertex name it would
	// replace "[3/3] RUN pip--install.sh …" with a naked "20.10".
	progressOutputRe = regexp.MustCompile(`^\d+(?:\.\d+)?(?:\s+(.*))?$`)
	progressANSIRe   = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`)
)

// buildProgress is the io.Writer handed to a silenced build's stderr. It passes
// every byte through to sink and, when out is non-nil, renders the current step
// as a single transient line.
type buildProgress struct {
	sink io.Writer
	out  io.Writer

	mu      sync.Mutex
	partial []byte
	vertex  string // "8" — the BuildKit vertex currently being reported
	name    string // "[3/6] RUN codeserver--setup.sh"
	detail  string // the step's most recent output line
	started time.Time
	frame   int
	drawn   bool

	begun     time.Time
	stop      chan struct{}
	done      chan struct{}
	closeOnce sync.Once
}

// newBuildProgress returns a writer that mirrors into sink. When out is nil
// (not a terminal, or progress opted out) it is a plain pass-through.
func newBuildProgress(sink io.Writer, out io.Writer) *buildProgress {
	progress := &buildProgress{
		sink:  sink,
		out:   out,
		begun: time.Now(),
	}

	if out != nil {
		progress.stop = make(chan struct{})
		progress.done = make(chan struct{})
		go progress.tick()
	}

	return progress
}

// Seams, so the choice below can be tested on a machine that has no terminal —
// and, more to the point, inside `go test`, which is one of the cases the choice
// is about.
var (
	progressStderrIsTTY  = IsStderrTTY
	progressStdIsTTY     = func() bool { return IsStdinTTY() || IsStdoutTTY() }
	progressOpenTerminal = openControllingTerminal
)

// buildProgressOut picks where the transient line is drawn — nil for nowhere —
// together with a release for a terminal it had to open itself.
//
// stderr first: that is where the line belongs, and where an ordinary
// `codingbooth run` on a terminal draws it.
//
// When stderr has been redirected the line would disappear into the redirect,
// and that is precisely the case a silent build hurts most. Every complex test
// sends booth's stderr to /dev/null or to CB_DIAG_LOG, and the suite pipes each
// test through `tee` — so the suite, which silences every build and can spend
// twenty minutes inside one, was the one caller that could never show the line.
// A suite that prints nothing for twenty minutes reads as hung.
//
// So fall back to the controlling terminal itself. That is safe here for a
// reason specific to this line: it is transient, and it goes to a stream nobody
// is capturing. It cannot land in a captured log, an expected-output fixture, or
// a diff — the redirect the caller set up still receives exactly the bytes it
// received before.
//
// What it does need is a person watching, so it is drawn only while one of the
// standard streams is still a terminal. A daemonised run, a cron job, or CI has
// none, and stays byte-for-byte as silent as before.
func buildProgressOut() (io.Writer, func()) {
	noRelease := func() {}

	if os.Getenv("CB_NO_BUILD_PROGRESS") != "" {
		return nil, noRelease
	}
	if progressStderrIsTTY() {
		return os.Stderr, noRelease
	}
	if !progressStdIsTTY() {
		return nil, noRelease
	}

	terminal := progressOpenTerminal()
	if terminal == nil {
		return nil, noRelease
	}

	return terminal, func() { terminal.Close() }
}

// openControllingTerminal opens the terminal this process is attached to for
// writing, or returns nil when there is none to open — a container, a service, a
// CI runner. The IsTTY check is not redundant: /dev/tty can open and still not
// be a terminal in an odd environment, and drawing escape codes into something
// that isn't one is how a "harmless" status line ends up in somebody's log.
func openControllingTerminal() io.WriteCloser {
	name := "/dev/tty"
	if runtime.GOOS == "windows" {
		name = "CONOUT$"
	}

	terminal, err := os.OpenFile(name, os.O_WRONLY, 0)
	if err != nil {
		return nil
	}
	if !IsTTY(terminal.Fd()) {
		terminal.Close()
		return nil
	}

	return terminal
}

func (p *buildProgress) Write(chunk []byte) (int, error) {
	written, err := p.sink.Write(chunk)

	if p.out != nil {
		p.consume(chunk)
	}

	return written, err
}

// Close stops the ticker and wipes the line. Safe to call more than once, which
// the failure path relies on: it closes early so the captured log isn't printed
// on top of a half-drawn status line.
func (p *buildProgress) Close() {
	if p.out == nil {
		return
	}

	p.closeOnce.Do(func() {
		// stop is nil only when the ticker was never started, which is how the
		// tests drive rendering deterministically.
		if p.stop != nil {
			close(p.stop)
			<-p.done
		}

		p.mu.Lock()
		defer p.mu.Unlock()
		p.erase()
	})
}

func (p *buildProgress) tick() {
	defer close(p.done)

	ticker := time.NewTicker(progressFrameRate)
	defer ticker.Stop()

	for {
		select {
		case <-p.stop:
			return
		case <-ticker.C:
			p.mu.Lock()
			p.frame++
			p.render()
			p.mu.Unlock()
		}
	}
}

// consume splits the stream into lines and feeds the complete ones to parse.
func (p *buildProgress) consume(chunk []byte) {
	p.mu.Lock()
	defer p.mu.Unlock()

	p.partial = append(p.partial, chunk...)

	for {
		end := bytes.IndexByte(p.partial, '\n')
		if end < 0 {
			break
		}

		p.parse(string(p.partial[:end]))
		p.partial = p.partial[end+1:]
	}

	if len(p.partial) > progressMaxPartial {
		p.partial = append([]byte(nil), p.partial[len(p.partial)-progressKeepTail:]...)
	}

	p.render()
}

// parse folds one line of BuildKit plain output into the current step.
func (p *buildProgress) parse(raw string) {
	line := progressANSIRe.ReplaceAllString(raw, "")

	// A \r-rewritten line (curl's meter) only ever carries its vertex prefix
	// once, at the very front, so anything after the last \r is unattributable
	// and gets dropped by the vertex match below.
	if cut := strings.LastIndexByte(line, '\r'); cut >= 0 {
		line = line[cut+1:]
	}

	match := progressVertexRe.FindStringSubmatch(strings.TrimSpace(line))
	if match == nil {
		return
	}

	vertex, rest := match[1], strings.TrimSpace(match[2])
	if rest == "" {
		return
	}

	switch {
	case isProgressStatus(rest):
		// DONE / CACHED / ERROR — the step is over; drop its last output line
		// but keep the name up until the next step names itself.
		if vertex == p.vertex {
			p.detail = ""
		}

	case progressOutputRe.MatchString(rest):
		if vertex == p.vertex {
			p.detail = strings.TrimSpace(progressOutputRe.FindStringSubmatch(rest)[1])
		}

	default:
		// The vertex naming itself. BuildKit re-names a vertex as it goes
		// ("exporting to image" then "exporting layers"), so only a genuinely
		// new vertex restarts the clock.
		if vertex != p.vertex {
			p.vertex = vertex
			p.started = time.Now()
		}
		p.name, p.detail = rest, ""
	}
}

// render redraws the status line in place. Callers hold p.mu.
func (p *buildProgress) render() {
	if p.out == nil || p.name == "" {
		return
	}
	if time.Since(p.begun) < progressStartDelay {
		return
	}

	text := fmt.Sprintf(
		"%s %s  %s",
		progressSpinner[p.frame%len(progressSpinner)],
		formatProgressDuration(time.Since(p.started)),
		p.name,
	)
	if p.detail != "" {
		text += "  — " + p.detail
	}

	// One column short of the width, so the line can't wrap — a wrapped line
	// leaves a stray row behind when \r\033[K only clears the last one.
	fmt.Fprintf(p.out, "\r\033[K%s", truncateProgress(text, progressWidth(p.out)-1))
	p.drawn = true
}

func (p *buildProgress) erase() {
	if !p.drawn {
		return
	}

	fmt.Fprint(p.out, "\r\033[K")
	p.drawn = false
}

// isProgressStatus recognises a vertex's terminal line: `DONE 482.4s`, `CACHED`,
// `ERROR: process ... did not complete successfully`, `CANCELED`.
func isProgressStatus(rest string) bool {
	for _, word := range []string{"DONE", "CACHED", "ERROR", "CANCELED"} {
		if rest == word || strings.HasPrefix(rest, word+" ") || strings.HasPrefix(rest, word+":") {
			return true
		}
	}
	return false
}

// progressWidth measures the terminal the line is actually drawn on, which is
// not always stderr — a redirected stderr sends it to /dev/tty instead, and the
// two can be different sizes. Anything that isn't a terminal gets the fallback.
func progressWidth(out io.Writer) int {
	file, ok := out.(*os.File)
	if !ok {
		return progressFallbackWidth
	}

	width, _, err := term.GetSize(int(file.Fd()))
	if err != nil || width <= 0 {
		return progressFallbackWidth
	}

	return width
}

func truncateProgress(text string, limit int) string {
	if limit <= 1 {
		return ""
	}

	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}

	return string(runes[:limit-1]) + "…"
}

// formatProgressDuration keeps the clock a fixed-ish width so it doesn't jitter:
// "12s", "7m29s", "1h07m".
func formatProgressDuration(elapsed time.Duration) string {
	if elapsed < 0 {
		elapsed = 0
	}

	switch {
	case elapsed < time.Minute:
		return fmt.Sprintf("%ds", int(elapsed.Seconds()))
	case elapsed < time.Hour:
		return fmt.Sprintf("%dm%02ds", int(elapsed.Minutes()), int(elapsed.Seconds())%60)
	default:
		return fmt.Sprintf("%dh%02dm", int(elapsed.Hours()), int(elapsed.Minutes())%60)
	}
}
