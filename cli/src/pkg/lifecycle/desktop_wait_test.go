package lifecycle

import (
	"bytes"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestContainerFromInspectReadsDesktopLabel(t *testing.T) {
	var data inspectData
	data.Name = "/demo"
	data.Config.Labels = map[string]string{DesktopLabel: "x11"}
	if got := containerFromInspect(data, "demo").Desktop; got != "x11" {
		t.Fatalf("Desktop = %q, want x11", got)
	}

	data.Config.Labels = map[string]string{"cb.variant": "base"}
	if got := containerFromInspect(data, "demo").Desktop; got != "" {
		t.Fatalf("Desktop = %q for a booth without the label, want empty", got)
	}
}

func exitWith(t *testing.T, code string) error {
	t.Helper()
	err := exec.Command("sh", "-c", "exit "+code).Run()
	if err == nil {
		t.Fatalf("sh exit %s returned no error", code)
	}
	return err
}

func TestDesktopProbeFromExit(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want desktopProbeResult
	}{
		{"display up", nil, desktopReady},
		{"not yet", exitWith(t, "1"), desktopNotReady},
		{"helper says no display", exitWith(t, "2"), desktopNone},
		{"helper not executable", exitWith(t, "126"), desktopNone},
		{"image has no helper", exitWith(t, "127"), desktopNone},
		{"engine call failed", exitWith(t, "125"), desktopNotReady},
		{"engine binary missing", exec.Command("/nonexistent/docker").Run(), desktopNotReady},
	}
	for _, tc := range cases {
		if got := desktopProbeFromExit(tc.err); got != tc.want {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
		}
	}
}

// probeSequence answers results in order, then repeats the last one. A ready
// answer carries readyEnv.
func probeSequence(results ...desktopProbeResult) (func() (desktopProbeResult, []string), *int) {
	return probeSequenceEnv([]string{"DISPLAY=:1"}, results...)
}

func probeSequenceEnv(readyEnv []string, results ...desktopProbeResult) (func() (desktopProbeResult, []string), *int) {
	calls := 0
	return func() (desktopProbeResult, []string) {
		r := results[len(results)-1]
		if calls < len(results) {
			r = results[calls]
		}
		calls++
		if r == desktopReady {
			return r, readyEnv
		}
		return r, nil
	}, &calls
}

func TestPollDesktopReadyAtOnceIsSilent(t *testing.T) {
	probe, calls := probeSequence(desktopReady)
	var stderr bytes.Buffer
	slept := 0
	_, err := pollDesktop("demo", probe, 10, time.Second, func(time.Duration) { slept++ }, false, &stderr)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if *calls != 1 || slept != 0 {
		t.Fatalf("calls=%d slept=%d, want one probe and no sleep", *calls, slept)
	}
	if stderr.Len() != 0 {
		t.Fatalf("printed %q for a desktop that was already up", stderr.String())
	}
}

func TestPollDesktopWaitsUntilReady(t *testing.T) {
	probe, calls := probeSequence(desktopNotReady, desktopNotReady, desktopNotReady, desktopReady)
	var stderr bytes.Buffer
	slept := 0
	_, err := pollDesktop("demo", probe, 10, time.Second, func(time.Duration) { slept++ }, false, &stderr)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if *calls != 4 || slept != 3 {
		t.Fatalf("calls=%d slept=%d, want 4 probes and 3 sleeps", *calls, slept)
	}
	if n := strings.Count(stderr.String(), "Waiting for the desktop"); n != 1 {
		t.Fatalf("progress line printed %d times, want once: %q", n, stderr.String())
	}
}

func TestPollDesktopQuietHidesProgress(t *testing.T) {
	probe, _ := probeSequence(desktopNotReady, desktopReady)
	var stderr bytes.Buffer
	if _, err := pollDesktop("demo", probe, 10, time.Second, func(time.Duration) {}, true, &stderr); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if stderr.Len() != 0 {
		t.Fatalf("quiet wait printed %q", stderr.String())
	}
}

func TestPollDesktopNoneStopsWaiting(t *testing.T) {
	probe, calls := probeSequence(desktopNotReady, desktopNone)
	if _, err := pollDesktop("demo", probe, 10, time.Second, func(time.Duration) {}, true, &bytes.Buffer{}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if *calls != 2 {
		t.Fatalf("calls=%d, want 2 (stop at the helper's no-display answer)", *calls)
	}
}

func TestPollDesktopTimesOut(t *testing.T) {
	probe, calls := probeSequence(desktopNotReady)
	slept := 0
	_, err := pollDesktop("demo", probe, 4, 500*time.Millisecond, func(time.Duration) { slept++ }, true, &bytes.Buffer{})
	if err == nil {
		t.Fatal("expected a timeout error")
	}
	if *calls != 4 || slept != 3 {
		t.Fatalf("calls=%d slept=%d, want 4 probes and 3 sleeps (no sleep after the last)", *calls, slept)
	}
	if ExitCode(err) != 1 {
		t.Fatalf("exit code %d, want 1", ExitCode(err))
	}
	msg := err.Error()
	for _, want := range []string{`"demo"`, "within 2s", "was not run", "booth logs --name demo"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error %q lacks %q", msg, want)
		}
	}
}

func TestWaitForDesktopSkipsBoothWithoutLabel(t *testing.T) {
	// No label: returns before touching any engine, so this runs without Docker.
	var stderr bytes.Buffer
	if _, err := waitForDesktop(managedContainer{Name: "demo", Engine: "docker"}, false, &stderr); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if stderr.Len() != 0 {
		t.Fatalf("printed %q", stderr.String())
	}
}

func TestPollDesktopReturnsReadyEnv(t *testing.T) {
	want := []string{"XDG_RUNTIME_DIR=/tmp/xdg-1000", "WAYLAND_DISPLAY=wayland-0", "DISPLAY=:0"}
	probe, _ := probeSequenceEnv(want, desktopNotReady, desktopReady)
	env, err := pollDesktop("demo", probe, 10, time.Second, func(time.Duration) {}, true, &bytes.Buffer{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Join(env, " ") != strings.Join(want, " ") {
		t.Fatalf("env = %q, want %q", env, want)
	}
}

func TestPollDesktopNoneAddsNoEnv(t *testing.T) {
	probe, _ := probeSequence(desktopNone)
	env, err := pollDesktop("demo", probe, 10, time.Second, func(time.Duration) {}, true, &bytes.Buffer{})
	if err != nil || env != nil {
		t.Fatalf("env=%q err=%v, want no env and no error", env, err)
	}
}

func TestParseDesktopEnv(t *testing.T) {
	out := "XDG_RUNTIME_DIR=/tmp/xdg-1000\r\nWAYLAND_DISPLAY=wayland-0\nnot an env line\n=nokey\n9BAD=x\nDISPLAY=:0\n\n"
	got := strings.Join(parseDesktopEnv(out), " ")
	want := "XDG_RUNTIME_DIR=/tmp/xdg-1000 WAYLAND_DISPLAY=wayland-0 DISPLAY=:0"
	if got != want {
		t.Fatalf("parseDesktopEnv = %q, want %q", got, want)
	}
	if env := parseDesktopEnv(""); env != nil {
		t.Fatalf("an older helper's empty output should add nothing, got %q", env)
	}
}

func TestMergeDesktopEnvUserWins(t *testing.T) {
	desktop := []string{"XDG_RUNTIME_DIR=/tmp/xdg-1000", "WAYLAND_DISPLAY=wayland-0", "DISPLAY=:0"}
	user := stringSliceFlag{"DISPLAY=:5", "WAYLAND_DISPLAY", "FOO=bar"}
	got := strings.Join(mergeDesktopEnv(desktop, user), " ")
	want := "XDG_RUNTIME_DIR=/tmp/xdg-1000 DISPLAY=:5 WAYLAND_DISPLAY FOO=bar"
	if got != want {
		t.Fatalf("merge = %q, want %q", got, want)
	}
	if got := mergeDesktopEnv(nil, user); strings.Join(got, " ") != strings.Join(user, " ") {
		t.Fatalf("no desktop env should leave the user's -e as is, got %q", got)
	}
}
