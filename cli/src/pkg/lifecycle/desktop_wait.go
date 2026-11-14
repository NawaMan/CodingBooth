package lifecycle

import (
	"errors"
	"fmt"
	"io"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// DesktopLabel marks an image whose booths run a desktop, and which kind: the
// X11 desktop variants set it to "x11", desktop-wayland to "wayland", and
// images built FROM them inherit it. exec reads it from the container (Docker
// copies image labels into the container's), waits for the desktop before
// running the command, and runs the command with the env the desktop reports,
// so a GUI app started by `booth exec --run` neither races the display nor
// starts without one.
const DesktopLabel = "com.codingbooth.desktop"

// desktopReadyHelper is the in-booth probe (variants/base/booth--desktop-ready
// <kind>): exit 0 up (stdout: KEY=VALUE lines for the command's env), 1 not
// yet, 2 nothing to wait for.
const desktopReadyHelper = "booth--desktop-ready"

// How long exec waits for a desktop's display. A cold desktop booth, startup
// hooks included, comes up well inside this; a desktop that never does is
// reported rather than handed a GUI command it cannot open.
const (
	desktopWaitTimeout  = 90 * time.Second
	desktopWaitInterval = 500 * time.Millisecond
)

// desktopProbeResult is one answer from booth--desktop-ready.
type desktopProbeResult int

const (
	desktopNotReady desktopProbeResult = iota // still starting, or down: ask again
	desktopReady                              // the display answers
	desktopNone                               // nothing to wait for: stop asking
)

// desktopProbeFromExit maps the helper's exit to a probe result. 2 is the
// helper's own "no display here"; 126/127 mean the image has no helper at all
// (built before it existed), which is not worth waiting out either. Any other
// failure, including the exec itself failing, is "not yet". Pure for unit tests.
func desktopProbeFromExit(err error) desktopProbeResult {
	if err == nil {
		return desktopReady
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		switch exitErr.ExitCode() {
		case 2, 126, 127:
			return desktopNone
		}
	}
	return desktopNotReady
}

var desktopEnvLine = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*=`)

// parseDesktopEnv keeps the KEY=VALUE lines of the helper's output and drops
// anything else (an older helper prints nothing; a stray line is not an env
// entry to hand on). Pure for unit tests.
func parseDesktopEnv(out string) []string {
	var env []string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimRight(line, "\r")
		if desktopEnvLine.MatchString(line) {
			env = append(env, line)
		}
	}
	return env
}

// mergeDesktopEnv is the -e list exec runs the command with: the desktop's
// entries first, minus any key the user set with -e (bare `-e KEY` included),
// then the user's own. The user's value always wins, without relying on how an
// engine orders duplicate -e flags. Pure for unit tests.
func mergeDesktopEnv(desktop []string, user stringSliceFlag) stringSliceFlag {
	if len(desktop) == 0 {
		return user
	}
	userKeys := map[string]bool{}
	for _, entry := range user {
		key, _, _ := strings.Cut(entry, "=")
		userKeys[key] = true
	}
	var merged stringSliceFlag
	for _, entry := range desktop {
		key, _, _ := strings.Cut(entry, "=")
		if !userKeys[key] {
			merged = append(merged, entry)
		}
	}
	return append(merged, user...)
}

// waitForDesktop holds an exec session until the target booth's desktop is up,
// and returns the env the desktop reports for the command (nil when there is
// nothing to add). A booth without the desktop label returns at once, and so
// does one whose desktop is already up (a single probe), so it is cheap on
// every exec. quiet hides the progress line; the timeout error is always shown.
func waitForDesktop(target managedContainer, quiet bool, stderr io.Writer) ([]string, error) {
	if target.Desktop == "" {
		return nil, nil
	}
	probe := func() (desktopProbeResult, []string) {
		// Same user as the command exec is about to run: the X server's auth
		// cookie and the Wayland socket are coder's.
		args := []string{"exec", "-u", "coder", target.Name}
		if target.AppleLowPorts {
			args = []string{"exec", "-u", "root", target.Name}
		}
		args = append(args, coderCommand(target.AppleLowPorts, desktopReadyHelper, target.Desktop)...)
		out, err := exec.Command(docker.EngineBinary(target.Engine), args...).Output()
		result := desktopProbeFromExit(err)
		if result != desktopReady {
			return result, nil
		}
		return result, parseDesktopEnv(string(out))
	}
	attempts := int(desktopWaitTimeout / desktopWaitInterval)
	return pollDesktop(target.Name, probe, attempts, desktopWaitInterval, time.Sleep, quiet, stderr)
}

// pollDesktop asks probe until it answers ready or none, up to attempts times
// with interval between asks, and returns the env of the ready answer. The
// progress line is printed once, and only when the first ask finds the desktop
// not up yet. Pure apart from probe and sleep, for unit tests.
func pollDesktop(name string, probe func() (desktopProbeResult, []string), attempts int, interval time.Duration, sleep func(time.Duration), quiet bool, stderr io.Writer) ([]string, error) {
	for attempt := 0; attempt < attempts; attempt++ {
		switch result, env := probe(); result {
		case desktopReady:
			return env, nil
		case desktopNone:
			return nil, nil
		}
		if attempt == 0 && !quiet {
			fmt.Fprintf(stderr, "Waiting for the desktop of booth %q to come up...\n", name)
		}
		if attempt < attempts-1 {
			sleep(interval)
		}
	}
	waited := time.Duration(attempts) * interval
	return nil, commandExit(1, fmt.Sprintf(
		"Error: the desktop of booth %q did not come up within %s, so the command was not run.\n"+
			"       See `booth logs --name %s` for why.",
		name, waited.Round(time.Second), name,
	))
}
