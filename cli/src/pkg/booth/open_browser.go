// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

const (
	// browserWaitTimeout bounds the wait for the booth to answer. A first run
	// that has to install setups can take minutes before the UI is up, so this
	// is generous; it exists to stop the wait being unbounded, not to guess how
	// long a booth takes.
	browserWaitTimeout = 5 * time.Minute

	// browserPollInterval is how often the booth's URL is probed while waiting.
	browserPollInterval = 250 * time.Millisecond

	// browserProbeTimeout bounds one probe. The target is on loopback, so a
	// probe that has not answered in this long is a booth that is not up yet.
	browserProbeTimeout = 3 * time.Second

	// boothHealthPath is the readiness endpoint every variant's nginx serves
	// (see BOOTH_HEALTH.md). It proxies to the service behind nginx, which is
	// the only thing that answers the question the wait is asking.
	boothHealthPath = "/__booth/health"
)

// boothHealthURL is the readiness endpoint on a booth's front door.
func boothHealthURL(boothURL string) string {
	return strings.TrimSuffix(boothURL, "/") + boothHealthPath
}

// BoothURL is the address this run's booth UI answers on.
func BoothURL(ctx appctx.AppContext) string {
	scheme := "http"
	if ctx.Public() {
		scheme = "https"
	}
	return fmt.Sprintf("%s://localhost:%d", scheme, ctx.PortNumber())
}

// shouldOpenBrowser reports whether this run has a page worth opening.
//
// A booth handed a command has no UI to open: `-- bash` runs in the terminal
// the booth was launched from, and `--variant terminal` is the same thing —
// ValidateVariant turns it into `base` plus a `bash` command. So the command
// list, not the variant, is what says whether the published port serves a page.
func shouldOpenBrowser(ctx appctx.AppContext) bool {
	return ctx.Browser() && !ctx.Dryrun() && ctx.Cmds().Length() == 0
}

// OpenBoothInBrowser waits for the booth to answer on its port, then hands the
// URL to the host's browser.
//
// Nothing here is fatal. The booth is running and reachable whether or not a
// browser could be opened for it, so every failure prints a warning naming the
// URL to open by hand and returns.
//
// waitCtx cancels the wait: in foreground mode it is cancelled when the
// container exits, so a booth that dies during startup does not leave a
// goroutine polling a port nothing is on.
func OpenBoothInBrowser(waitCtx context.Context, ctx appctx.AppContext) {
	url := BoothURL(ctx)

	if reason := browserUnavailable(); reason != "" {
		warnBrowser(url, "not opening a browser: %s", reason)
		return
	}

	if !waitForBoothServing(waitCtx, url, browserWaitTimeout) {
		// A cancelled wait means the booth exited first — it has already said so.
		if waitCtx.Err() != nil {
			return
		}
		warnBrowser(url, "the booth did not answer within %s", browserWaitTimeout)
		return
	}

	if err := openURL(url); err != nil {
		warnBrowser(url, "could not open a browser: %v", err)
		return
	}
	LogFprintf(os.Stderr, "🌐 Opened %s in your browser.\n", url)
}

// warnBrowser reports why the browser did not open and points at the URL, so
// the failure costs the user a click rather than the session.
func warnBrowser(url, format string, a ...any) {
	fmt.Fprintf(os.Stderr, "⚠️  "+format+"\n", a...)
	fmt.Fprintf(os.Stderr, "   Open %s yourself.\n", url)
}

// waitForBoothServing polls the booth's readiness endpoint until it answers,
// and reports whether it did before the timeout (or the wait being cancelled).
//
// A TCP connect is not enough to tell. `docker run -p` publishes the host port
// the moment the container is created, so the port accepts connections long
// before anything inside the container is listening — a browser opened on that
// signal lands on a connection reset, which is exactly the "opened too early"
// failure this is meant to avoid.
//
// Neither is the booth's front page. Every variant is fronted by nginx (see
// BOOTH_UI_OVERLAY.md), and nginx answers the root itself, without touching the
// service behind it: the split UI's root is a file on disk, and the wrapper
// variants' is a bare `return 302 /booth`. Both come back the instant nginx
// binds, while ttyd or code-server is still starting — so the browser opens on
// a page whose frames then fill with nginx's 502. /__booth/health is the one
// endpoint that proxies through to that service, so it is the only answer that
// means the booth is up.
func waitForBoothServing(waitCtx context.Context, url string, timeout time.Duration) bool {
	client := &http.Client{
		Timeout: browserProbeTimeout,
		// Any response proves something is serving. Where it points does not
		// matter, and following the redirect only costs another round trip.
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		Transport: &http.Transport{
			// --public serves HTTPS with a certificate the booth generated for
			// itself, so verification would fail on every healthy booth. This
			// is a liveness probe against loopback, not a trust decision.
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true}, // #nosec G402
		},
	}
	defer client.CloseIdleConnections()

	deadline := time.Now().Add(timeout)
	healthURL := boothHealthURL(url)
	announced := false

	for {
		if boothIsServing(waitCtx, client, healthURL) {
			return true
		}
		if waitCtx.Err() != nil || time.Now().After(deadline) {
			return false
		}
		if !announced {
			// Only once the booth is not up on the first try: a booth that is
			// already serving should not print a wait it never did.
			LogFprintf(os.Stderr, "⏳ Waiting for the booth to answer on %s ...\n", url)
			announced = true
		}
		select {
		case <-waitCtx.Done():
			return false
		case <-time.After(browserPollInterval):
		}
	}
}

// boothIsServing reports whether one probe of the URL found a booth to show.
//
// Nearly any status counts: /__booth/health normalizes every non-5xx answer it
// gets from the service behind nginx to 200. The exception is the gateway
// errors, which are nginx reporting it could not reach that service — the gap
// this wait exists to sit out.
//
// A booth from an image too old to serve the endpoint falls back to whatever
// answers the path instead. For the wrapper variants that is the catch-all
// proxy, which is the right answer by accident; for the terminal variant it is
// the front page from disk, which is the old too-early behaviour. Neither is
// worse than not waiting, and an image and its CLI normally ship together.
func boothIsServing(waitCtx context.Context, client *http.Client, url string) bool {
	req, err := http.NewRequestWithContext(waitCtx, http.MethodGet, url, nil)
	if err != nil {
		return false
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout:
		return false
	}
	return true
}

// browserUnavailable explains why this host cannot open a browser, or returns
// "" when it can.
//
// Only Linux has a case worth guessing at: a booth is routinely run over SSH on
// a machine with no graphical session, where xdg-open either fails or launches
// a text browser into the middle of the terminal the booth is using.
// WSL is the exception — there is no local display, but the browser to open
// lives on the Windows side and opening it works.
func browserUnavailable() string {
	return headlessReason(runtime.GOOS, isWSL(), os.Getenv("DISPLAY"), os.Getenv("WAYLAND_DISPLAY"))
}

// headlessReason is the decision browserUnavailable makes, as a pure function
// so the Linux-over-SSH case — the one this guard exists for, and the one least
// likely to be reproducible on the machine the tests run on — is testable from
// any host.
func headlessReason(goos string, wsl bool, display, waylandDisplay string) string {
	if goos != "linux" || wsl {
		return ""
	}
	if display != "" || waylandDisplay != "" {
		return ""
	}
	return "this host has no graphical session (DISPLAY and WAYLAND_DISPLAY are unset)"
}

// openURL hands a URL to whatever opens links on this host.
//
// The candidates are tried in order and the first one present on PATH wins, so
// a desktop without the usual opener still gets its browser, and a host with
// none of them says which ones it looked for instead of failing silently.
func openURL(url string) error {
	var tried []string

	for _, candidate := range browserOpenerCommands(url) {
		path, err := exec.LookPath(candidate[0])
		if err != nil {
			tried = append(tried, candidate[0])
			continue
		}

		cmd := exec.Command(path, candidate[1:]...) // #nosec G204 -- opener from a fixed list or $BROWSER, URL is booth's own
		// The opener's own chatter (xdg-open warnings, a PowerShell banner)
		// would land in the middle of the booth's output. Whether the browser
		// opened is reported by the caller either way.
		cmd.Stdout, cmd.Stderr = nil, nil

		if err := cmd.Start(); err != nil {
			tried = append(tried, candidate[0])
			continue
		}
		// Reap it in the background: an opener exits as soon as the browser has
		// the URL, and nothing here waits on that.
		go func() { _ = cmd.Wait() }()
		return nil
	}

	if len(tried) == 0 {
		return fmt.Errorf("no browser opener is known for %s", runtime.GOOS)
	}
	return fmt.Errorf("none of these could be run: %s", strings.Join(tried, ", "))
}

// browserOpenerCommands is the ordered list of commands that might open a URL
// on this host, $BROWSER first when it is set.
func browserOpenerCommands(url string) [][]string {
	if cmd := browserEnvCommand(url); cmd != nil {
		return append([][]string{cmd}, platformOpenerCommands(url)...)
	}
	return platformOpenerCommands(url)
}

// platformOpenerCommands lists the openers to try for the host OS.
func platformOpenerCommands(url string) [][]string {
	switch runtime.GOOS {
	case "darwin":
		return [][]string{{"open", url}}

	case "windows":
		// rundll32 takes the URL as one argument, so a URL holding '&' survives.
		// `cmd /c start` would read it as a command separator instead.
		return [][]string{{"rundll32", "url.dll,FileProtocolHandler", url}}

	default:
		// Linux and the BSDs: the freedesktop opener, then the desktop-specific
		// ones, then the Debian browser alternatives.
		var cmds [][]string
		if isWSL() {
			// On WSL the browser is the Windows one; wslview is the packaged
			// bridge, PowerShell the fallback when it is not installed.
			cmds = append(cmds,
				[]string{"wslview", url},
				[]string{"powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Start-Process", url},
			)
		}
		return append(cmds,
			[]string{"xdg-open", url},
			[]string{"gio", "open", url},
			[]string{"gnome-open", url},
			[]string{"kde-open", url},
			[]string{"x-www-browser", url},
			[]string{"sensible-browser", url},
			[]string{"www-browser", url},
		)
	}
}

// browserEnvCommand honors $BROWSER, the Unix convention for "open links with
// this". The value is a colon-separated list of commands, each optionally
// holding a "%s" placeholder for the URL; an entry without one gets the URL
// appended. Only the first entry is used — if it cannot be run, the platform
// openers below it are tried anyway.
func browserEnvCommand(url string) []string {
	if runtime.GOOS == "windows" {
		return nil
	}
	spec := strings.TrimSpace(os.Getenv("BROWSER"))
	if spec == "" {
		return nil
	}

	first, _, _ := strings.Cut(spec, ":")
	fields := strings.Fields(first)
	if len(fields) == 0 {
		return nil
	}

	substituted := false
	for i, field := range fields {
		if strings.Contains(field, "%s") {
			fields[i] = strings.ReplaceAll(field, "%s", url)
			substituted = true
		}
	}
	if !substituted {
		fields = append(fields, url)
	}
	return fields
}

// isWSL reports whether this is a Linux running under the Windows Subsystem for
// Linux, where the browser to open lives on the Windows side.
func isWSL() bool {
	if runtime.GOOS != "linux" {
		return false
	}
	if os.Getenv("WSL_DISTRO_NAME") != "" || os.Getenv("WSL_INTEROP") != "" {
		return true
	}
	version, err := os.ReadFile("/proc/version")
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(version)), "microsoft")
}
