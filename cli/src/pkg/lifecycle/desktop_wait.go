package lifecycle

import (
	"errors"
	"fmt"
	"io"
	"os/exec"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// DesktopLabel marks an image whose booths run a desktop: the X11 desktop
// variants set it to "x11", and images built FROM them inherit it. exec reads
// it from the container (Docker copies image labels into the container's) and
// waits for the desktop's display before running the command, so a GUI app
// started by `booth exec --run` does not race the X server.
const DesktopLabel = "com.codingbooth.desktop"

// desktopReadyHelper is the in-booth probe (variants/base/booth--desktop-ready):
// exit 0 the display is up, 1 not yet, 2 nothing to wait for.
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

// waitForDesktop holds an exec session until the target booth's desktop
// display is up. A booth without the desktop label returns at once, and so does
// one whose desktop is already up (a single probe), so it is cheap on every
// exec. quiet hides the progress line; the timeout error is always shown.
func waitForDesktop(target managedContainer, quiet bool, stderr io.Writer) error {
	if target.Desktop == "" {
		return nil
	}
	probe := func() desktopProbeResult {
		// Same user as the command exec is about to run: the X server's auth
		// cookie is in coder's ~/.Xauthority.
		args := []string{"exec", "-u", "coder", target.Name}
		if target.AppleLowPorts {
			args = []string{"exec", "-u", "root", target.Name}
		}
		args = append(args, coderCommand(target.AppleLowPorts, desktopReadyHelper)...)
		return desktopProbeFromExit(exec.Command(docker.EngineBinary(target.Engine), args...).Run())
	}
	attempts := int(desktopWaitTimeout / desktopWaitInterval)
	return pollDesktop(target.Name, probe, attempts, desktopWaitInterval, time.Sleep, quiet, stderr)
}

// pollDesktop asks probe until it answers ready or none, up to attempts times
// with interval between asks. The progress line is printed once, and only when
// the first ask finds the desktop not up yet. Pure apart from probe and sleep,
// for unit tests.
func pollDesktop(name string, probe func() desktopProbeResult, attempts int, interval time.Duration, sleep func(time.Duration), quiet bool, stderr io.Writer) error {
	for attempt := 0; attempt < attempts; attempt++ {
		switch probe() {
		case desktopReady, desktopNone:
			return nil
		}
		if attempt == 0 && !quiet {
			fmt.Fprintf(stderr, "Waiting for the desktop of booth %q to come up...\n", name)
		}
		if attempt < attempts-1 {
			sleep(interval)
		}
	}
	waited := time.Duration(attempts) * interval
	return commandExit(1, fmt.Sprintf(
		"Error: the desktop of booth %q did not come up within %s, so the command was not run.\n"+
			"       See `booth logs --name %s` for why.",
		name, waited.Round(time.Second), name,
	))
}
