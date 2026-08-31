// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

// browserTestContext builds the smallest AppContext the browser decision reads.
func browserTestContext(browser, dryrun, public bool, port int, cmds ...string) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		Cmds: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Browser = browser
	builder.Config.Public = public
	builder.PortNumber = port
	if dryrun {
		builder.Config.Dryrun = nillable.NewNillableBool(true)
	}
	if len(cmds) > 0 {
		builder.Cmds.Append(ilist.NewListFromSlice(cmds))
	}
	return builder.Build()
}

func TestShouldOpenBrowser(t *testing.T) {
	tests := []struct {
		name string
		ctx  appctx.AppContext
		want bool
	}{
		{"a booth serving a UI opens", browserTestContext(true, false, false, 10000), true},
		{"--no-browser stays shut", browserTestContext(false, false, false, 10000), false},
		{"--dryrun runs no container to open", browserTestContext(true, true, false, 10000), false},
		// `-- bash` and `--variant terminal` land here identically: ValidateVariant
		// turns the variant into base plus a bash command, so both serve no page.
		{"a booth given a command has no page", browserTestContext(true, false, false, 10000, "bash"), false},
		{"a command still counts with --browser", browserTestContext(true, false, false, 10000, "sleep", "1"), false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldOpenBrowser(tt.ctx); got != tt.want {
				t.Errorf("shouldOpenBrowser() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestBoothURL(t *testing.T) {
	if got, want := BoothURL(browserTestContext(true, false, false, 10000)), "http://localhost:10000"; got != want {
		t.Errorf("BoothURL() = %q, want %q", got, want)
	}
	// --public terminates TLS in the booth, so the page is only reachable over https.
	if got, want := BoothURL(browserTestContext(true, false, true, 20443)), "https://localhost:20443"; got != want {
		t.Errorf("BoothURL() public = %q, want %q", got, want)
	}
}

func TestWaitForBoothServing_RespondingBooth(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// A real booth answers the front door with a redirect to its login page.
		http.Redirect(w, r, "/login", http.StatusFound)
	}))
	defer server.Close()

	if !waitForBoothServing(context.Background(), server.URL, 5*time.Second) {
		t.Error("waitForBoothServing() = false for a booth that answers")
	}
}

// TestWaitForBoothServing_PublishedButNotListening covers the case the HTTP
// probe exists for: `docker run -p` publishes the host port when the container
// is created, so the port accepts connections while the service inside is still
// starting. A TCP-connect check would call that "served" and open a browser
// onto a reset connection.
func TestWaitForBoothServing_PublishedButNotListening(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer listener.Close()

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			conn.Close() // accepted, then dropped — exactly what docker-proxy does
		}
	}()

	url := "http://" + listener.Addr().String()
	start := time.Now()
	if waitForBoothServing(context.Background(), url, 600*time.Millisecond) {
		t.Error("waitForBoothServing() = true for a port that accepts but serves nothing")
	}
	if elapsed := time.Since(start); elapsed < 500*time.Millisecond {
		t.Errorf("gave up after %s — it should have kept polling until the timeout", elapsed)
	}
}

// TestWaitForBoothServing_NginxAheadOfService covers the other early landing:
// every variant is fronted by nginx, which answers before the service behind it
// does. Its 502 is not a page worth opening — but the moment the service is up,
// the wait must finish.
func TestWaitForBoothServing_NginxAheadOfService(t *testing.T) {
	var serviceUp atomic.Bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !serviceUp.Load() {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		http.Redirect(w, r, "/login", http.StatusFound)
	}))
	defer server.Close()

	if waitForBoothServing(context.Background(), server.URL, 400*time.Millisecond) {
		t.Error("waitForBoothServing() = true while the front door was still answering 502")
	}

	serviceUp.Store(true)
	if !waitForBoothServing(context.Background(), server.URL, 5*time.Second) {
		t.Error("waitForBoothServing() = false once the service behind nginx was up")
	}
}

// TestWaitForBoothServing_ProbesHealthNotRoot is the failure this wait was
// getting wrong: nginx answers the booth's root itself — a file on disk for the
// split UI, a bare `return 302 /booth` for the wrapper variants — the instant it
// binds, with the service behind it still starting. Probing the root therefore
// says "up" while every frame on the page it opens fills with nginx's 502.
func TestWaitForBoothServing_ProbesHealthNotRoot(t *testing.T) {
	var serviceUp atomic.Bool
	var rootProbes atomic.Int32

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != boothHealthPath {
			// nginx's own answer, which never depends on the service behind it.
			rootProbes.Add(1)
			http.Redirect(w, r, "/booth", http.StatusFound)
			return
		}
		if !serviceUp.Load() {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	if waitForBoothServing(context.Background(), server.URL, 400*time.Millisecond) {
		t.Error("waitForBoothServing() = true while only nginx was answering")
	}
	if got := rootProbes.Load(); got != 0 {
		t.Errorf("the wait probed the root %d times — it must ask the health endpoint", got)
	}

	serviceUp.Store(true)
	if !waitForBoothServing(context.Background(), server.URL, 5*time.Second) {
		t.Error("waitForBoothServing() = false once the service behind nginx was up")
	}
}

func TestBoothHealthURL(t *testing.T) {
	tests := []struct{ boothURL, want string }{
		{"http://localhost:10000", "http://localhost:10000/__booth/health"},
		// A trailing slash must not double up into //__booth/health.
		{"http://localhost:10000/", "http://localhost:10000/__booth/health"},
		{"https://localhost:10443", "https://localhost:10443/__booth/health"},
	}

	for _, tt := range tests {
		if got := boothHealthURL(tt.boothURL); got != tt.want {
			t.Errorf("boothHealthURL(%q) = %q, want %q", tt.boothURL, got, tt.want)
		}
	}
}

func TestWaitForBoothServing_CancelledWhenBoothExits(t *testing.T) {
	// Nothing is listening here, so the wait can only end by cancellation.
	waitCtx, cancel := context.WithCancel(context.Background())
	go func() {
		time.Sleep(50 * time.Millisecond)
		cancel()
	}()

	start := time.Now()
	if waitForBoothServing(waitCtx, "http://127.0.0.1:1", time.Minute) {
		t.Error("waitForBoothServing() = true with nothing listening")
	}
	if elapsed := time.Since(start); elapsed > 10*time.Second {
		t.Errorf("cancelling took %s — the wait ignored its context", elapsed)
	}
}

func TestHeadlessReason(t *testing.T) {
	tests := []struct {
		name           string
		goos           string
		wsl            bool
		display        string
		waylandDisplay string
		wantHeadless   bool
	}{
		{name: "macOS always has a browser", goos: "darwin", wantHeadless: false},
		{name: "Windows always has a browser", goos: "windows", wantHeadless: false},
		{name: "Linux over SSH has nowhere to open", goos: "linux", wantHeadless: true},
		{name: "Linux with X11", goos: "linux", display: ":0"},
		{name: "Linux with Wayland", goos: "linux", waylandDisplay: "wayland-0"},
		// No local display, but the browser to open is the Windows one.
		{name: "WSL has no display and opens anyway", goos: "linux", wsl: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			reason := headlessReason(tt.goos, tt.wsl, tt.display, tt.waylandDisplay)
			if (reason != "") != tt.wantHeadless {
				t.Errorf("headlessReason() = %q, wantHeadless %v", reason, tt.wantHeadless)
			}
		})
	}
}

func TestBrowserEnvCommand(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("$BROWSER is a Unix convention and is ignored on Windows")
	}

	const url = "http://localhost:10000"
	tests := []struct {
		name    string
		browser string
		want    []string
	}{
		{"unset falls through to the platform openers", "", nil},
		{"blank is not a command", "   ", nil},
		{"a bare command gets the URL appended", "firefox", []string{"firefox", url}},
		{"%s is substituted in place", "chromium --app=%s", []string{"chromium", "--app=" + url}},
		{"only the first entry of the list is used", "firefox:chromium", []string{"firefox", url}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("BROWSER", tt.browser)
			got := browserEnvCommand(url)
			if len(got) != len(tt.want) {
				t.Fatalf("browserEnvCommand() = %v, want %v", got, tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Fatalf("browserEnvCommand() = %v, want %v", got, tt.want)
				}
			}
		})
	}
}

func TestBrowserOpenerCommands(t *testing.T) {
	const url = "http://localhost:10000"

	if runtime.GOOS != "windows" {
		t.Setenv("BROWSER", "")
	}
	commands := browserOpenerCommands(url)
	if len(commands) == 0 {
		t.Fatalf("no opener is known for %s", runtime.GOOS)
	}

	// Every candidate must carry the URL, or it opens a browser on nothing.
	for _, cmd := range commands {
		if len(cmd) < 2 {
			t.Fatalf("opener %v has no arguments", cmd)
		}
		found := false
		for _, arg := range cmd[1:] {
			if strings.Contains(arg, url) {
				found = true
			}
		}
		if !found {
			t.Errorf("opener %v does not pass the URL", cmd)
		}
	}

	want := map[string]string{"darwin": "open", "windows": "rundll32"}[runtime.GOOS]
	if want == "" {
		want = "xdg-open" // Linux and the BSDs
	}
	found := false
	for _, cmd := range commands {
		if cmd[0] == want {
			found = true
		}
	}
	if !found {
		t.Errorf("openers for %s = %v, expected %q among them", runtime.GOOS, commands, want)
	}
}

// TestBrowserOpenerCommandsHonorsBrowserEnv checks that $BROWSER is tried first
// but does not replace the platform openers — an unrunnable $BROWSER must not
// be the end of it.
func TestBrowserOpenerCommandsHonorsBrowserEnv(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("$BROWSER is a Unix convention and is ignored on Windows")
	}
	t.Setenv("BROWSER", "my-browser")

	commands := browserOpenerCommands("http://localhost:10000")
	if len(commands) < 2 {
		t.Fatalf("expected $BROWSER plus the platform openers, got %v", commands)
	}
	if commands[0][0] != "my-browser" {
		t.Errorf("$BROWSER should be tried first, got %v", commands[0])
	}
}
