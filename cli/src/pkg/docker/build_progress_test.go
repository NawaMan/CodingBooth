// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"io"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

// newTestProgress builds a buildProgress with no ticker goroutine, so a test
// drives rendering by feeding bytes rather than by waiting on the clock. begun
// is backdated past progressStartDelay so the very first write draws.
func newTestProgress() (*buildProgress, *bytes.Buffer, *bytes.Buffer) {
	var sink, out bytes.Buffer

	progress := &buildProgress{
		sink:  &sink,
		out:   &out,
		begun: time.Now().Add(-time.Hour),
	}

	return progress, &sink, &out
}

// The build log this whole feature exists for: `RUN codeserver--setup.sh` spends
// eight minutes on one curl with no newline in sight.
const codeserverBuildLog = `#7 [2/6] RUN python--setup.sh
#7 CACHED

#8 [3/6] RUN codeserver--setup.sh
#8 0.097 [1/9] Install code-server…
#8 2.936 Downloading code-server 4.133.0 for arm64 (224 MB)…
`

func TestBuildProgress_TracksCurrentStep(t *testing.T) {
	progress, _, _ := newTestProgress()

	if _, err := progress.Write([]byte(codeserverBuildLog)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	if progress.vertex != "8" {
		t.Errorf("vertex = %q, want \"8\"", progress.vertex)
	}
	if progress.name != "[3/6] RUN codeserver--setup.sh" {
		t.Errorf("name = %q, want the step header", progress.name)
	}
	if progress.detail != "Downloading code-server 4.133.0 for arm64 (224 MB)…" {
		t.Errorf("detail = %q, want the latest output line", progress.detail)
	}
}

func TestBuildProgress_DrawsStepAndClock(t *testing.T) {
	progress, _, out := newTestProgress()

	// Backdate the step so the clock has something to show. Writing sets
	// started to now, so override it afterwards and force a redraw.
	if _, err := progress.Write([]byte(codeserverBuildLog)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}
	progress.started = time.Now().Add(-449 * time.Second)
	progress.render()

	drawn := out.String()

	if !strings.Contains(drawn, "7m29s") {
		t.Errorf("drawn line has no elapsed clock: %q", drawn)
	}
	if !strings.Contains(drawn, "RUN codeserver--setup.sh") {
		t.Errorf("drawn line has no step name: %q", drawn)
	}
	if !strings.Contains(drawn, "Downloading code-server") {
		t.Errorf("drawn line has no detail: %q", drawn)
	}
	if !strings.HasPrefix(drawn, "\r\033[K") {
		t.Errorf("line is not redrawn in place: %q", drawn)
	}
	if strings.Contains(drawn, "\n") {
		t.Errorf("progress must stay on one line, got a newline: %q", drawn)
	}
}

func TestBuildProgress_CloseErasesTheLine(t *testing.T) {
	progress, _, out := newTestProgress()

	if _, err := progress.Write([]byte(codeserverBuildLog)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}
	if !progress.drawn {
		t.Fatal("expected a line to have been drawn")
	}

	out.Reset()
	progress.Close()

	if got := out.String(); got != "\r\033[K" {
		t.Errorf("Close wrote %q, want a bare erase sequence", got)
	}
	if progress.drawn {
		t.Error("drawn should be false after Close")
	}

	// The failure path closes early and then again via defer.
	out.Reset()
	progress.Close()
	if got := out.String(); got != "" {
		t.Errorf("second Close wrote %q, want nothing", got)
	}
}

func TestBuildProgress_NothingDrawnBeforeTheStartDelay(t *testing.T) {
	progress, _, out := newTestProgress()
	progress.begun = time.Now()

	if _, err := progress.Write([]byte(codeserverBuildLog)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	if got := out.String(); got != "" {
		t.Errorf("a build under %v drew %q, want nothing", progressStartDelay, got)
	}
}

func TestBuildProgress_PassesEveryByteToTheSink(t *testing.T) {
	progress, sink, _ := newTestProgress()

	// Split mid-line to prove reassembly across writes.
	half := len(codeserverBuildLog) / 2
	for _, chunk := range []string{codeserverBuildLog[:half], codeserverBuildLog[half:]} {
		if _, err := progress.Write([]byte(chunk)); err != nil {
			t.Fatalf("Write failed: %v", err)
		}
	}

	if sink.String() != codeserverBuildLog {
		t.Error("sink did not receive the stream verbatim")
	}
	if progress.detail != "Downloading code-server 4.133.0 for arm64 (224 MB)…" {
		t.Errorf("detail = %q after a split write", progress.detail)
	}
}

// A curl meter rewrites one line with \r for the whole 224 MB download. The
// buffer must not grow without bound, and the unattributable tail must not be
// mistaken for the step's output.
func TestBuildProgress_SurvivesACurlProgressMeter(t *testing.T) {
	progress, sink, _ := newTestProgress()

	if _, err := progress.Write([]byte(codeserverBuildLog)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	meter := "#8 3.047 " + strings.Repeat("\r  #=#=#   42.0%"+strings.Repeat(" ", 200), 5000)
	if _, err := progress.Write([]byte(meter)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	if len(progress.partial) > progressMaxPartial {
		t.Errorf("partial grew to %d bytes, cap is %d", len(progress.partial), progressMaxPartial)
	}
	if sink.Len() != len(codeserverBuildLog)+len(meter) {
		t.Error("sink lost bytes from the meter")
	}
	if progress.detail != "Downloading code-server 4.133.0 for arm64 (224 MB)…" {
		t.Errorf("detail = %q, want the last real message to survive the meter", progress.detail)
	}
}

func TestBuildProgress_StatusLinesEndTheStepButKeepItNamed(t *testing.T) {
	progress, _, _ := newTestProgress()

	if _, err := progress.Write([]byte(codeserverBuildLog + "#8 DONE 482.4s\n")); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	if progress.name != "[3/6] RUN codeserver--setup.sh" {
		t.Errorf("name = %q, want the step to stay named after DONE", progress.name)
	}
	if progress.detail != "" {
		t.Errorf("detail = %q, want it cleared by DONE", progress.detail)
	}
}

// BuildKit renames a vertex as it works ("exporting to image" then "exporting
// layers"); only a new vertex restarts the clock.
func TestBuildProgress_ClockRestartsOnlyOnANewStep(t *testing.T) {
	progress, _, _ := newTestProgress()

	if _, err := progress.Write([]byte("#12 exporting to image\n")); err != nil {
		t.Fatalf("Write failed: %v", err)
	}
	started := progress.started

	if _, err := progress.Write([]byte("#12 exporting layers\n")); err != nil {
		t.Fatalf("Write failed: %v", err)
	}
	if !progress.started.Equal(started) {
		t.Error("a rename restarted the clock")
	}
	if progress.name != "exporting layers" {
		t.Errorf("name = %q, want the rename applied", progress.name)
	}

	if _, err := progress.Write([]byte("#13 [6/6] RUN elixir-code-extension--setup.sh\n")); err != nil {
		t.Fatalf("Write failed: %v", err)
	}
	if progress.started.Equal(started) {
		t.Error("a new step did not restart the clock")
	}
}

// Output belongs to the vertex that announced it; BuildKit interleaves vertices
// when steps run in parallel.
func TestBuildProgress_IgnoresOutputFromOtherVertices(t *testing.T) {
	progress, _, _ := newTestProgress()

	log := "#8 [3/6] RUN codeserver--setup.sh\n#8 0.097 mine\n#4 12.5 someone else's\n"
	if _, err := progress.Write([]byte(log)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	if progress.detail != "mine" {
		t.Errorf("detail = %q, want the current vertex's own output", progress.detail)
	}
}

func TestBuildProgress_NilOutIsAPlainPassThrough(t *testing.T) {
	var sink bytes.Buffer

	progress := newBuildProgress(&sink, nil)
	if _, err := progress.Write([]byte(codeserverBuildLog)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}
	progress.Close() // must not block on a ticker that was never started

	if sink.String() != codeserverBuildLog {
		t.Error("sink did not receive the stream verbatim")
	}
	if progress.name != "" {
		t.Errorf("name = %q, want no parsing work when there is nowhere to draw", progress.name)
	}
}

func TestTruncateProgress(t *testing.T) {
	tests := []struct {
		name  string
		text  string
		limit int
		want  string
	}{
		{"fits", "abc", 10, "abc"},
		{"exact", "abcde", 5, "abcde"},
		{"trimmed", "abcdefgh", 5, "abcd…"},
		{"multibyte counted as runes", "⠋ 7m29s  ⣿⣿⣿", 6, "⠋ 7m2…"},
		{"no room", "abc", 1, ""},
		{"negative", "abc", -4, ""},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := truncateProgress(test.text, test.limit); got != test.want {
				t.Errorf("truncateProgress(%q, %d) = %q, want %q", test.text, test.limit, got, test.want)
			}
		})
	}
}

func TestFormatProgressDuration(t *testing.T) {
	tests := []struct {
		elapsed time.Duration
		want    string
	}{
		{0, "0s"},
		{-time.Second, "0s"},
		{12 * time.Second, "12s"},
		{59*time.Second + 999*time.Millisecond, "59s"},
		{time.Minute, "1m00s"},
		{449 * time.Second, "7m29s"},
		{time.Hour + 7*time.Minute, "1h07m"},
	}

	for _, test := range tests {
		if got := formatProgressDuration(test.elapsed); got != test.want {
			t.Errorf("formatProgressDuration(%v) = %q, want %q", test.elapsed, got, test.want)
		}
	}
}

func TestIsProgressStatus(t *testing.T) {
	statuses := []string{"DONE", "DONE 482.4s", "CACHED", "ERROR: oops", "CANCELED"}
	for _, status := range statuses {
		if !isProgressStatus(status) {
			t.Errorf("isProgressStatus(%q) = false, want true", status)
		}
	}

	others := []string{"DONEISH", "[3/6] RUN foo", "exporting to image", "CACHEDX"}
	for _, other := range others {
		if isProgressStatus(other) {
			t.Errorf("isProgressStatus(%q) = true, want false", other)
		}
	}
}

// syncBuffer lets a test read what the ticker goroutine is writing.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(chunk []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	return b.buf.Write(chunk)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()

	return b.buf.String()
}

// The real path: a ticker goroutine redrawing while stderr streams in. This is
// what keeps the clock moving through the 449 seconds where curl says nothing.
func TestBuildProgress_TickerAnimatesWhileTheStepIsSilent(t *testing.T) {
	var sink bytes.Buffer
	out := &syncBuffer{}

	progress := newBuildProgress(&sink, out)
	progress.begun = time.Now().Add(-time.Hour) // skip progressStartDelay

	if _, err := progress.Write([]byte(codeserverBuildLog)); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	// No further output — exactly the silent-download case. The ticker alone
	// must keep redrawing.
	time.Sleep(5 * progressFrameRate)

	frames := strings.Count(out.String(), "\r\033[K")
	if frames < 2 {
		t.Errorf("ticker drew %d frames while the step was silent, want it animating", frames)
	}

	progress.Close()

	if !strings.HasSuffix(out.String(), "\r\033[K") {
		t.Error("Close did not leave the line erased")
	}
}

// fakeTerminal stands in for the controlling terminal, so the fallback can be
// tested where there is none: `go test` captures output, which is exactly the
// redirected-stderr case the fallback exists for.
type fakeTerminal struct {
	bytes.Buffer
	closed bool
}

func (f *fakeTerminal) Close() error {
	f.closed = true
	return nil
}

// stubProgressOut points the three seams at fixed answers for one test.
func stubProgressOut(t *testing.T, stderrTTY bool, stdTTY bool, terminal io.WriteCloser) {
	t.Helper()
	t.Setenv("CB_NO_BUILD_PROGRESS", "")

	stderrWas, stdWas, openWas := progressStderrIsTTY, progressStdIsTTY, progressOpenTerminal
	t.Cleanup(func() {
		progressStderrIsTTY, progressStdIsTTY, progressOpenTerminal = stderrWas, stdWas, openWas
	})

	progressStderrIsTTY = func() bool { return stderrTTY }
	progressStdIsTTY = func() bool { return stdTTY }
	progressOpenTerminal = func() io.WriteCloser { return terminal }
}

func TestBuildProgressOut_DrawsOnStderrWhenItIsATerminal(t *testing.T) {
	terminal := &fakeTerminal{}
	stubProgressOut(t, true, true, terminal)

	out, release := buildProgressOut()
	release()

	if out != io.Writer(os.Stderr) {
		t.Errorf("out = %v, want os.Stderr", out)
	}
	if terminal.closed {
		t.Error("released a terminal it never opened")
	}
}

// The case this whole fallback is for: the complex suite sends booth's stderr to
// /dev/null or CB_DIAG_LOG and pipes the test through `tee`, so stderr is never
// a terminal — but someone is sitting there watching a build that can take
// twenty minutes.
func TestBuildProgressOut_FallsBackToTheTerminalWhenStderrIsRedirected(t *testing.T) {
	terminal := &fakeTerminal{}
	stubProgressOut(t, false, true, terminal)

	out, release := buildProgressOut()

	if out != io.Writer(terminal) {
		t.Fatalf("out = %v, want the controlling terminal", out)
	}

	release()
	if !terminal.closed {
		t.Error("release did not close the terminal it opened")
	}
}

// A daemonised run, a cron job, CI: nothing to draw on and nobody to see it.
func TestBuildProgressOut_StaysSilentWithNoTerminalAnywhere(t *testing.T) {
	stubProgressOut(t, false, false, &fakeTerminal{})

	out, release := buildProgressOut()
	release()

	if out != nil {
		t.Errorf("out = %v, want nil when no standard stream is a terminal", out)
	}
}

// A terminal on stdin or stdout, but no controlling terminal to open — the nil
// here must stay a nil *interface*, or newBuildProgress starts a ticker that
// writes into nothing.
func TestBuildProgressOut_StaysSilentWhenTheTerminalWontOpen(t *testing.T) {
	stubProgressOut(t, false, true, nil)

	out, release := buildProgressOut()
	release()

	if out != nil {
		t.Errorf("out = %v, want nil when the controlling terminal will not open", out)
	}
}

func TestBuildProgressOut_OptOutWinsOverEveryTerminal(t *testing.T) {
	stubProgressOut(t, true, true, &fakeTerminal{})
	t.Setenv("CB_NO_BUILD_PROGRESS", "1")

	out, release := buildProgressOut()
	release()

	if out != nil {
		t.Errorf("out = %v, want nil when CB_NO_BUILD_PROGRESS is set", out)
	}
}

// The width comes from wherever the line is drawn, which is not always stderr.
// Anything that isn't a terminal — a test buffer, a pipe — takes the fallback.
func TestProgressWidth_FallsBackForANonTerminal(t *testing.T) {
	if width := progressWidth(&bytes.Buffer{}); width != progressFallbackWidth {
		t.Errorf("progressWidth(buffer) = %d, want %d", width, progressFallbackWidth)
	}

	read, write, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe failed: %v", err)
	}
	defer read.Close()
	defer write.Close()

	if width := progressWidth(write); width != progressFallbackWidth {
		t.Errorf("progressWidth(pipe) = %d, want %d", width, progressFallbackWidth)
	}
}

// A step that prints a blank line arrives as a vertex prefix and a timestamp and
// nothing else. Seen for real from `pip--install.sh`, where it briefly replaced
// the step name with "20.10".
func TestBuildProgress_ABlankOutputLineKeepsTheStepNamed(t *testing.T) {
	progress, _, _ := newTestProgress()

	if _, err := progress.Write([]byte("#8 [3/3] RUN pip--install.sh rich\n#8 19.87 Installing collected packages\n#8 20.10\n")); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	if progress.name != "[3/3] RUN pip--install.sh rich" {
		t.Errorf("name = %q, want the step still named", progress.name)
	}
	if progress.detail != "" {
		t.Errorf("detail = %q, want a blank line to clear the detail", progress.detail)
	}
}
