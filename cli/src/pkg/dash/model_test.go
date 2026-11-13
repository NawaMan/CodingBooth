// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"context"
	"errors"
	"os/exec"
	"reflect"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

var testNow = time.Date(2026, 11, 10, 12, 0, 0, 0, time.UTC)

func running(name string) lifecycle.Booth {
	return lifecycle.Booth{Name: name, Engine: "docker", State: "running", Variant: "base",
		CodePath: "/home/u/dev/" + name, Port: "10000", CreatedAt: "2026-11-10T09:00:00Z", KeepAlive: true}
}

func stopped(name string) lifecycle.Booth {
	b := running(name)
	b.State = "exited"
	return b
}

// fakeDeps records what the dashboard runs.
type fakeDeps struct {
	ran      [][]string
	ranIn    []string
	execed   [][]string
	execedIn []string
	opened   []string
	openErr  error
	ports    []lifecycle.ExposedPort
	portsErr error
	portsFor []string
	runErr   error
	runOut   string
	snapshot []lifecycle.Booth

	messaged   [][]string
	messageOut string
	messageErr error

	stats    lifecycle.BoothStats
	statsErr error
	state    lifecycle.BoothState
	stateErr error
	pending  []lifecycle.PendingMessage
	logs     string
	detailed []string // "part:booth" for each detail part asked for

	repos     []lifecycle.Repo
	edited    []string
	editorErr error
	krakened  []string
	shelled   []string
	logViewed []string

	configs    map[string]ProjectConfig // by .booth dir
	configRead []string                 // each .booth dir read
}

func (f *fakeDeps) deps() Deps {
	return Deps{
		Snapshot: func() ([]lifecycle.Booth, []string, error) { return f.snapshot, nil, nil },
		Run: func(dir string, args []string) (string, error) {
			f.ran = append(f.ran, args)
			f.ranIn = append(f.ranIn, dir)
			return f.runOut, f.runErr
		},
		Command: func(dir string, args []string) *exec.Cmd {
			f.execed = append(f.execed, args)
			f.execedIn = append(f.execedIn, dir)
			return exec.Command("true")
		},
		Message: func(_ context.Context, args []string) (string, error) {
			f.messaged = append(f.messaged, args)
			return f.messageOut, f.messageErr
		},
		Open: func(url string) error {
			f.opened = append(f.opened, url)
			return f.openErr
		},
		Ports: func(b lifecycle.Booth) ([]lifecycle.ExposedPort, error) {
			f.portsFor = append(f.portsFor, b.Name+"@"+b.Engine)
			return f.ports, f.portsErr
		},
		Stats: func(b lifecycle.Booth) (lifecycle.BoothStats, error) {
			f.detailed = append(f.detailed, "stats:"+b.Name)
			return f.stats, f.statsErr
		},
		State: func(b lifecycle.Booth) (lifecycle.BoothState, error) {
			f.detailed = append(f.detailed, "state:"+b.Name)
			return f.state, f.stateErr
		},
		Pending: func(b lifecycle.Booth) ([]lifecycle.PendingMessage, error) {
			f.detailed = append(f.detailed, "pending:"+b.Name)
			return f.pending, nil
		},
		Logs: func(b lifecycle.Booth, lines int) (string, error) {
			f.detailed = append(f.detailed, "logs:"+b.Name)
			return f.logs, nil
		},
		Editor: func(path string) (*exec.Cmd, error) {
			f.edited = append(f.edited, path)
			if f.editorErr != nil {
				return nil, f.editorErr
			}
			return exec.Command("true"), nil
		},
		LogView: func(b lifecycle.Booth) (*exec.Cmd, *exec.Cmd) {
			f.logViewed = append(f.logViewed, b.Name)
			return exec.Command("true"), nil
		},
		HostShell: func(path string) *exec.Cmd {
			f.shelled = append(f.shelled, path)
			return exec.Command("true")
		},
		GitKraken: func(path string) error {
			f.krakened = append(f.krakened, path)
			return nil
		},
		Config: func(boothDir string) (ProjectConfig, error) {
			f.configRead = append(f.configRead, boothDir)
			return f.configs[boothDir], nil
		},
		Home: "/home/u",
		Now:  func() time.Time { return testNow },
	}
}

// loaded is a model that has shown booths once.
func loaded(f *fakeDeps, booths ...lifecycle.Booth) model {
	m := newModel(f.deps())
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: f.repos})
	return next.(model)
}

func press(t *testing.T, m model, keys ...string) (model, tea.Cmd) {
	t.Helper()
	var cmd tea.Cmd
	for _, key := range keys {
		var next tea.Model
		next, cmd = m.Update(keyMsg(key))
		m = next.(model)
	}
	return m, cmd
}

func keyMsg(key string) tea.KeyMsg {
	switch key {
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "down":
		return tea.KeyMsg{Type: tea.KeyDown}
	case "up":
		return tea.KeyMsg{Type: tea.KeyUp}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	case "tab":
		return tea.KeyMsg{Type: tea.KeyTab}
	case "shift+tab":
		return tea.KeyMsg{Type: tea.KeyShiftTab}
	case "left":
		return tea.KeyMsg{Type: tea.KeyLeft}
	case "right":
		return tea.KeyMsg{Type: tea.KeyRight}
	case "backspace":
		return tea.KeyMsg{Type: tea.KeyBackspace}
	case "home":
		return tea.KeyMsg{Type: tea.KeyHome}
	case "ctrl+s":
		return tea.KeyMsg{Type: tea.KeyCtrlS}
	case "ctrl+u":
		return tea.KeyMsg{Type: tea.KeyCtrlU}
	case "end":
		return tea.KeyMsg{Type: tea.KeyEnd}
	case " ":
		return tea.KeyMsg{Type: tea.KeySpace, Runes: []rune{' '}}
	}
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(key)}
}

func TestPlanForNamesBoothAndEngine(t *testing.T) {
	booth := running("web")
	booth.Engine = "podman"
	p, reason := planFor(keyStop, booth)
	if reason != "" {
		t.Fatalf("unexpected refusal: %s", reason)
	}
	want := []string{"stop", "--name", "web", "--engine", "podman"}
	if !reflect.DeepEqual(p.Args, want) {
		t.Errorf("args = %v, want %v", p.Args, want)
	}
}

func TestPlanForRules(t *testing.T) {
	notKept := running("tmp")
	notKept.KeepAlive = false
	daemon := stopped("svc")
	daemon.Daemon = true
	noPort := running("cli")
	noPort.Port = ""

	cases := []struct {
		label       string
		key         string
		booth       lifecycle.Booth
		args        string
		refused     bool
		confirm     string // a substring of the question; "" means none is asked
		interactive bool
	}{
		{label: "start a running booth", key: keyStart, booth: running("web"), refused: true},
		{label: "start an interactive booth attaches", key: keyStart, booth: stopped("web"), args: "start --name web --engine docker", interactive: true},
		{label: "start a daemon booth in the foreground", key: keyStart, booth: daemon, args: "start --name svc --engine docker --daemon", interactive: true},
		{label: "stop asks", key: keyStop, booth: running("web"), args: "stop --name web --engine docker", confirm: "Stop web?"},
		{label: "stop says a non-keep-alive container goes", key: keyStop, booth: notKept, confirm: "container is removed"},
		{label: "stop a stopped booth", key: keyStop, booth: stopped("web"), refused: true},
		{label: "restart asks", key: keyRestart, booth: running("web"), args: "restart --name web --engine docker", confirm: "Restart web?"},
		{label: "restart a stopped booth", key: keyRestart, booth: stopped("web"), refused: true},
		{label: "remove a stopped booth", key: keyRemove, booth: stopped("web"), args: "remove --name web --engine docker", confirm: "home volume"},
		{label: "remove a running booth forces, and says so", key: keyRemove, booth: running("web"), args: "remove --name web --engine docker --force", confirm: "Force-delete"},
		{label: "open a stopped booth", key: keyOpen, booth: stopped("web"), refused: true},
		{label: "open a booth with no port", key: keyOpen, booth: noPort, refused: true},
		{label: "shell", key: keyShell, booth: running("web"), args: "shell --name web --engine docker", interactive: true},
		{label: "shell into a stopped booth offers to start it", key: keyShell, booth: stopped("web"),
			args: "shell --name web --engine docker --run", confirm: "web is not running. Start it for a shell?", interactive: true},
	}
	for _, c := range cases {
		p, reason := planFor(c.key, c.booth)
		if c.refused {
			if reason == "" {
				t.Errorf("%s: not refused (plan %+v)", c.label, p)
			}
			continue
		}
		if reason != "" {
			t.Errorf("%s: refused: %s", c.label, reason)
			continue
		}
		if c.args != "" && strings.Join(p.Args, " ") != c.args {
			t.Errorf("%s: args = %q, want %q", c.label, strings.Join(p.Args, " "), c.args)
		}
		if (c.confirm == "") != (p.Confirm == "") || !strings.Contains(p.Confirm, c.confirm) {
			t.Errorf("%s: confirm = %q, want one containing %q", c.label, p.Confirm, c.confirm)
		}
		if p.Interactive != c.interactive {
			t.Errorf("%s: interactive = %v, want %v", c.label, p.Interactive, c.interactive)
		}
	}
}

func TestConfirmNoCancelsWithoutRunning(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"))

	m, cmd := press(t, m, "x")
	if m.confirm == nil || cmd != nil {
		t.Fatalf("x on a running booth must only ask (confirm %v, cmd %v)", m.confirm, cmd != nil)
	}
	if !strings.Contains(m.View(), "Stop web? It") && !strings.Contains(m.View(), "Stop web?") {
		t.Errorf("question not shown:\n%s", m.View())
	}

	m, cmd = press(t, m, "n")
	if m.confirm != nil || cmd != nil || len(f.ran) != 0 {
		t.Errorf("n must cancel: confirm %v, cmd %v, ran %v", m.confirm, cmd != nil, f.ran)
	}
	if m.status != "Cancelled." {
		t.Errorf("status = %q", m.status)
	}
}

func TestConfirmYesRunsAndMarksBusyUntilDone(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"))

	m, cmd := press(t, m, "x", "y")
	if cmd == nil {
		t.Fatal("y must run the stop")
	}
	if m.busy["web@docker"] != "stopping…" {
		t.Errorf("busy = %v, want web stopping", m.busy)
	}
	if !strings.Contains(m.View(), "stopping…") {
		t.Errorf("busy state not shown:\n%s", m.View())
	}

	// A second action on the same booth waits.
	m, again := press(t, m, "r")
	if again != nil || m.confirm != nil || !strings.Contains(m.status, "wait") {
		t.Errorf("action on a busy booth: cmd %v, confirm %v, status %q", again != nil, m.confirm, m.status)
	}

	done := cmd()
	if want := []string{"stop", "--name", "web", "--engine", "docker"}; len(f.ran) != 1 || !reflect.DeepEqual(f.ran[0], want) {
		t.Fatalf("ran = %v, want %v", f.ran, want)
	}
	next, refresh := m.Update(done)
	m = next.(model)
	if _, still := m.busy["web@docker"]; still {
		t.Error("busy not cleared")
	}
	if m.status != "Stopped web." || m.statusErr {
		t.Errorf("status = %q (err %v)", m.status, m.statusErr)
	}
	if refresh == nil {
		t.Error("a finished action must refresh the list")
	}
}

func TestFailedActionShowsCommandsError(t *testing.T) {
	f := &fakeDeps{runErr: errors.New("exit status 1"), runOut: "web\nError: booth \"web\" is running. Stop it first or use --force.\n"}
	m := loaded(f, stopped("web"))

	m, cmd := press(t, m, "d", "y")
	next, _ := m.Update(cmd())
	m = next.(model)
	if !m.statusErr || !strings.HasPrefix(m.status, "Error: booth \"web\" is running") {
		t.Errorf("status = %q (err %v), want the command's last line", m.status, m.statusErr)
	}
}

func TestShellTakesTheTerminal(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"))

	_, cmd := press(t, m, "enter")
	if cmd == nil {
		t.Fatal("enter on a running booth must open a shell")
	}
	if want := []string{"shell", "--name", "web", "--engine", "docker"}; len(f.execed) != 1 || !reflect.DeepEqual(f.execed[0], want) {
		t.Errorf("exec = %v, want %v", f.execed, want)
	}
	if len(f.ran) != 0 {
		t.Errorf("a shell must not run in the background: %v", f.ran)
	}
}

func TestOpenOpensTheBoothPage(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"))

	m, cmd := press(t, m, "o")
	if cmd == nil || m.confirm != nil {
		t.Fatalf("o must open at once (cmd %v, confirm %v)", cmd != nil, m.confirm)
	}
	if len(m.busy) != 0 {
		t.Errorf("opening a page marked the booth busy: %v", m.busy)
	}
	next, after := m.Update(cmd())
	m = next.(model)
	if !reflect.DeepEqual(f.opened, []string{"http://localhost:10000"}) {
		t.Errorf("opened = %v", f.opened)
	}
	if m.status != "Opened http://localhost:10000 in your browser." || after != nil {
		t.Errorf("status = %q, follow-up cmd %v", m.status, after != nil)
	}
	if len(f.ran)+len(f.execed) != 0 {
		t.Errorf("opening a page ran a command: %v %v", f.ran, f.execed)
	}
}

func TestOpenFailureShowsReason(t *testing.T) {
	f := &fakeDeps{openErr: errors.New("not opening a browser: no graphical session; open http://localhost:10000 yourself")}
	m := loaded(f, running("web"))
	m, cmd := press(t, m, "o")
	next, _ := m.Update(cmd())
	m = next.(model)
	if !m.statusErr || !strings.Contains(m.status, "open http://localhost:10000 yourself") {
		t.Errorf("status = %q (err %v)", m.status, m.statusErr)
	}
}

func TestRefusedKeyExplains(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, stopped("web"))
	m, cmd := press(t, m, "o")
	if cmd != nil || !strings.Contains(m.status, "not running") {
		t.Errorf("cmd %v, status %q", cmd != nil, m.status)
	}
}

func TestEnterOnStoppedBoothOffersToStartIt(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, stopped("web"))
	m, cmd := press(t, m, "enter")
	if cmd != nil || m.confirm == nil || !strings.Contains(stripANSI(m.View()), "web is not running. Start it for a shell?") {
		t.Fatalf("enter on a stopped booth must ask first: confirm %+v\n%s", m.confirm, stripANSI(m.View()))
	}
	m, cmd = press(t, m, "n")
	if cmd != nil || len(f.execed) != 0 || m.status != "Cancelled." {
		t.Fatalf("n must cancel: execed %v status %q", f.execed, m.status)
	}
	m, _ = press(t, m, "enter")
	if _, cmd = press(t, m, "y"); cmd == nil {
		t.Fatal("y must open the shell")
	}
	if want := []string{"shell", "--name", "web", "--engine", "docker", "--run"}; len(f.execed) != 1 || !reflect.DeepEqual(f.execed[0], want) {
		t.Fatalf("execed %v, want %v", f.execed, want)
	}
}

func TestCursorFollowsBoothAcrossRefresh(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("a"), running("b"), running("c"))
	m, _ = press(t, m, "down", "down") // on c

	m.fetchSeq = 2
	next, _ := m.Update(snapshotMsg{seq: 2, booths: []lifecycle.Booth{running("c"), running("d")}})
	m = next.(model)
	if booth, _ := m.current(); booth.Name != "c" {
		t.Errorf("cursor on %q, want c", booth.Name)
	}

	// c is gone: the cursor stays on the same row, clamped.
	m.fetchSeq = 3
	next, _ = m.Update(snapshotMsg{seq: 3, booths: []lifecycle.Booth{running("a")}})
	m = next.(model)
	if booth, _ := m.current(); booth.Name != "a" {
		t.Errorf("cursor on %q, want a", booth.Name)
	}
}

func TestLateSnapshotIsDropped(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("old"))
	m.fetchSeq = 3
	next, _ := m.Update(snapshotMsg{seq: 3, booths: []lifecycle.Booth{running("new")}})
	m = next.(model)
	next, _ = m.Update(snapshotMsg{seq: 2, booths: []lifecycle.Booth{running("old")}})
	m = next.(model)
	if len(m.booths) != 1 || m.booths[0].Name != "new" {
		t.Errorf("booths = %+v, a late snapshot replaced a newer one", m.booths)
	}
}

func TestRefreshFailureKeepsLastList(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"))
	m.fetchSeq = 2
	next, _ := m.Update(snapshotMsg{seq: 2, err: errors.New("daemon down")})
	m = next.(model)
	view := m.View()
	if !strings.Contains(view, "web") || !strings.Contains(view, "refresh failed: daemon down") {
		t.Errorf("view:\n%s", view)
	}
}

func TestTickDoesNotStackSnapshots(t *testing.T) {
	f := &fakeDeps{}
	m := newModel(f.deps()) // first snapshot in flight
	next, _ := m.Update(tickMsg{})
	if next.(model).fetchSeq != 1 {
		t.Errorf("fetchSeq = %d, a tick started a second snapshot while one was in flight", next.(model).fetchSeq)
	}
}

func TestViewTable(t *testing.T) {
	f := &fakeDeps{}
	other := stopped("lab")
	other.Engine = "podman"
	other.CodePath = "/srv/very/long/path/to/the/project/lab"
	m := loaded(f, running("web"), other)
	next, _ := m.Update(tea.WindowSizeMsg{Width: 80, Height: 20})
	m = next.(model)

	view := m.View()
	for _, want := range []string{"2 booths", "refreshed 12:00:00", "ENGINE", "podman", "~/dev/web", "Running", "Stopped", "3h", "…"} {
		if !strings.Contains(view, want) {
			t.Errorf("view lacks %q:\n%s", want, view)
		}
	}
	for i, line := range strings.Split(view, "\n") {
		if w := len([]rune(stripANSI(line))); w > 80 {
			t.Errorf("line %d is %d wide: %q", i, w, stripANSI(line))
		}
	}
	if !strings.Contains(view, "/project/lab") {
		t.Errorf("a cut path must keep its end:\n%s", view)
	}

	single := loaded(f, running("web"))
	if strings.Contains(single.View(), "ENGINE") {
		t.Error("ENGINE column shown for one engine")
	}
}

func TestViewScrollsToCursor(t *testing.T) {
	f := &fakeDeps{}
	var booths []lifecycle.Booth
	for _, name := range []string{"b01", "b02", "b03", "b04", "b05", "b06", "b07", "b08"} {
		booths = append(booths, running(name))
	}
	m := loaded(f, booths...)
	next, _ := m.Update(tea.WindowSizeMsg{Width: 100, Height: chromeLines + 3})
	m = next.(model)
	m, _ = press(t, m, "G")
	view := m.View()
	if !strings.Contains(view, "b08") || strings.Contains(view, "b01") {
		t.Errorf("view does not follow the cursor to the end:\n%s", view)
	}
}

func TestAge(t *testing.T) {
	for created, want := range map[string]string{
		"2026-11-10T11:59:30Z": "30s",
		"2026-11-10T11:15:00Z": "45m",
		"2026-11-09T00:00:00Z": "36h",
		"2026-11-01T12:00:00Z": "9d",
		"not a time":           "-",
	} {
		if got := age(created, testNow); got != want {
			t.Errorf("age(%q) = %q, want %q", created, got, want)
		}
	}
}

func TestTruncate(t *testing.T) {
	if got := truncateLeft("/a/b/c/project", 8); got != "…project" {
		t.Errorf("truncateLeft = %q", got)
	}
	if got := truncateRight("a-long-booth-name", 6); got != "a-lon…" {
		t.Errorf("truncateRight = %q", got)
	}
}

func stripANSI(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == 0x1b {
			for i < len(s) && s[i] != 'm' {
				i++
			}
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func TestPortPickerOpensChosenPort(t *testing.T) {
	f := &fakeDeps{ports: []lifecycle.ExposedPort{
		{ContainerPort: 10000, HostIP: "0.0.0.0", HostPort: 10000, Proto: "tcp", Kind: "front door", Live: true, Source: "booth front door"},
		{ContainerPort: 5353, HostPort: 5353, Proto: "udp", Kind: "published", Live: true},
		{ContainerPort: 8080, HostIP: "127.0.0.1", HostPort: 18080, Proto: "tcp", Kind: "tunnel", Live: true, Source: "booth--expose"},
	}}
	m := loaded(f, running("web"))

	m, cmd := press(t, m, "p")
	if m.picker == nil || !m.picker.loading || cmd == nil {
		t.Fatalf("p must open a loading picker (picker %+v, cmd %v)", m.picker, cmd != nil)
	}
	if !strings.Contains(m.View(), "Reading ports") {
		t.Errorf("loading not shown:\n%s", m.View())
	}
	next, _ := m.Update(cmd())
	m = next.(model)
	if !reflect.DeepEqual(f.portsFor, []string{"web@docker"}) {
		t.Errorf("ports asked for %v", f.portsFor)
	}
	if len(m.picker.ports) != 2 {
		t.Fatalf("picker ports = %+v, want the two TCP ports (UDP has no URL)", m.picker.ports)
	}
	view := m.View()
	for _, want := range []string{"Ports of web", "http://localhost:10000", "http://127.0.0.1:18080", "tunnel", "esc back"} {
		if !strings.Contains(view, want) {
			t.Errorf("picker lacks %q:\n%s", want, view)
		}
	}
	if strings.Contains(view, "5353") {
		t.Errorf("UDP port offered:\n%s", view)
	}

	m, cmd = press(t, m, "down", "enter")
	if m.picker != nil || cmd == nil {
		t.Fatalf("enter must close the picker and open (picker %v)", m.picker != nil)
	}
	next, _ = m.Update(cmd())
	m = next.(model)
	if !reflect.DeepEqual(f.opened, []string{"http://127.0.0.1:18080"}) {
		t.Errorf("opened = %v", f.opened)
	}
	if m.status != "Opened http://127.0.0.1:18080 in your browser." {
		t.Errorf("status = %q", m.status)
	}
}

func TestPortPickerEscGoesBackWithoutOpening(t *testing.T) {
	f := &fakeDeps{ports: []lifecycle.ExposedPort{{HostPort: 10000, Proto: "tcp", Live: true}}}
	m := loaded(f, running("web"))
	m, cmd := press(t, m, "p")
	next, _ := m.Update(cmd())
	m = next.(model)

	// Keys that act on booths do nothing while the picker is up.
	m, cmd = press(t, m, "x")
	if m.confirm != nil || cmd != nil || m.picker == nil {
		t.Errorf("x inside the picker acted (confirm %v, cmd %v, picker %v)", m.confirm, cmd != nil, m.picker != nil)
	}
	m, _ = press(t, m, "esc")
	if m.picker != nil || len(f.opened) != 0 {
		t.Errorf("esc: picker %v, opened %v", m.picker != nil, f.opened)
	}
	if !strings.Contains(m.View(), "NAME") {
		t.Errorf("table not back:\n%s", m.View())
	}
}

func TestPortPickerShowsErrorsAndEmpty(t *testing.T) {
	f := &fakeDeps{portsErr: errors.New("boom")}
	m := loaded(f, running("web"))
	m, cmd := press(t, m, "p")
	next, _ := m.Update(cmd())
	if !strings.Contains(next.(model).View(), "Could not read ports: boom") {
		t.Errorf("view:\n%s", next.(model).View())
	}

	f = &fakeDeps{}
	m = loaded(f, running("web"))
	m, cmd = press(t, m, "p")
	next, _ = m.Update(cmd())
	m = next.(model)
	if !strings.Contains(m.View(), "publishes no TCP port") {
		t.Errorf("view:\n%s", m.View())
	}
	if _, cmd = press(t, m, "enter"); cmd != nil {
		t.Error("enter on an empty picker did something")
	}
}

func TestPortPickerRefusesStoppedBooth(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, stopped("web"))
	m, cmd := press(t, m, "p")
	if m.picker != nil || cmd != nil || !strings.Contains(m.status, "not running") {
		t.Errorf("picker %v, cmd %v, status %q", m.picker != nil, cmd != nil, m.status)
	}
}

// A picker closed before its ports arrive ignores them.
func TestPortPickerIgnoresLateAnswer(t *testing.T) {
	f := &fakeDeps{ports: []lifecycle.ExposedPort{{HostPort: 10000, Proto: "tcp"}}}
	m := loaded(f, running("web"))
	m, cmd := press(t, m, "p")
	m, _ = press(t, m, "esc")
	next, _ := m.Update(cmd())
	if next.(model).picker != nil {
		t.Error("a late ports answer reopened the picker")
	}
}

// A refusal ends with what was kept and why; cut to one line, that end was lost.
func TestLongErrorWrapsAndTheTableMakesRoom(t *testing.T) {
	f := &fakeDeps{}
	var booths []lifecycle.Booth
	for _, name := range []string{"b01", "b02", "b03", "b04", "b05", "b06", "b07", "b08"} {
		booths = append(booths, running(name))
	}
	m := loaded(f, booths...)
	height := chromeLines + 5
	next, _ := m.Update(tea.WindowSizeMsg{Width: 60, Height: height})
	m = next.(model)
	m, _ = press(t, m, "G")
	m.setStatus("Kept worktree rescan-button: it has 22 uncommitted or untracked file(s): "+
		"docs/SETUP.md, server/cmd/server/main.go, server/x.go and 19 more. Nothing was removed.", true)

	view := stripANSI(m.View())
	for _, want := range []string{"docs/SETUP.md", "Nothing was removed.", "b08"} {
		if !strings.Contains(view, want) {
			t.Errorf("view lacks %q:\n%s", want, view)
		}
	}
	lines := strings.Split(view, "\n")
	if len(lines) > height {
		t.Errorf("view is %d lines, taller than the %d-line screen:\n%s", len(lines), height, view)
	}
	for _, line := range lines {
		if lipgloss.Width(line) > 60 {
			t.Errorf("line wider than the screen: %q", line)
		}
	}
}

func TestVeryLongErrorStopsAtThreeLines(t *testing.T) {
	m := loaded(&fakeDeps{}, running("web"))
	next, _ := m.Update(tea.WindowSizeMsg{Width: 40, Height: 30})
	m = next.(model)
	m.setStatus(strings.Repeat("word ", 100), true)
	got := m.wrapStatus(m.status)
	if len(got) != maxStatusLines || !strings.HasSuffix(got[len(got)-1], "…") {
		t.Errorf("wrapped = %q, want %d lines ending in …", got, maxStatusLines)
	}
	if m.statusHeight() != maxStatusLines {
		t.Errorf("statusHeight = %d", m.statusHeight())
	}
}

func TestPlainStatusStaysOneLine(t *testing.T) {
	m := loaded(&fakeDeps{}, running("web"))
	next, _ := m.Update(tea.WindowSizeMsg{Width: 40, Height: 30})
	m = next.(model)
	m.setStatus(strings.Repeat("word ", 100), false)
	if m.statusHeight() != 1 || strings.Contains(m.statusLine(), "\n") {
		t.Errorf("a plain status wrapped: %q", m.statusLine())
	}
}
