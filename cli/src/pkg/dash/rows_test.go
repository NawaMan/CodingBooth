// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"errors"
	"os/exec"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// A repository with a main checkout, a worktree inside it and one beside it.
func testRepos() []lifecycle.Repo {
	return []lifecycle.Repo{{
		Name: "proj", Root: "/home/u/dev/proj", Here: true,
		Worktrees: []lifecycle.Worktree{
			{Path: "/home/u/dev/proj", Branch: "main", Main: true},
			{Path: "/home/u/dev/proj/worktree/fix", Branch: "fix"},
			{Path: "/home/u/dev/proj.worktrees/idea", Branch: "idea"},
		},
	}}
}

func boothAt(name, path string) lifecycle.Booth {
	b := running(name)
	b.CodePath = path
	return b
}

func rowSummary(rows []row) []string {
	out := make([]string, len(rows))
	for i, r := range rows {
		switch {
		case r.header:
			out[i] = "# " + r.repo.Name
		case r.booth != nil && r.worktree != nil:
			out[i] = r.booth.Name + " @" + r.worktree.Name()
		case r.booth != nil:
			out[i] = r.booth.Name
		default:
			out[i] = "(none) @" + r.worktree.Name()
		}
	}
	return out
}

func TestBuildRowsGroupsBoothsUnderWorktrees(t *testing.T) {
	booths := []lifecycle.Booth{
		boothAt("fixer", "/home/u/dev/proj/worktree/fix"),
		boothAt("example", "/home/u/dev/proj/examples/x"), // in the main checkout, not in fix
		boothAt("proj", "/home/u/dev/proj"),
		boothAt("loose", "/tmp/scratch"),
	}
	got := rowSummary(buildRows(booths, testRepos()))
	want := []string{"# proj", "example @main", "proj @main", "fixer @fix", "(none) @idea", "# Other booths", "loose"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v\nwant %v", got, want)
	}
	if flat := rowSummary(buildRows(booths, nil)); !reflect.DeepEqual(flat, []string{"fixer", "example", "proj", "loose"}) {
		t.Errorf("without repositories = %v, want the plain list", flat)
	}
}

func TestGroupedViewSkipsHeadersAndShowsWorktrees(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f, boothAt("fixer", "/home/u/dev/proj/worktree/fix"))
	if r, _ := m.currentRow(); r.worktree == nil || r.worktree.Name() != "main" {
		t.Fatalf("first row selected = %+v, want the main checkout (not the header)", r)
	}
	m, _ = press(t, m, "up")
	if m.cursor != 1 {
		t.Errorf("up from the first row moved onto the header: cursor %d", m.cursor)
	}
	view := stripANSI(m.View())
	for _, want := range []string{"proj (here)  ~/dev/proj", "WORKTREE", "no booth  main (main checkout)", "fixer  Running   fix"} {
		if !strings.Contains(view, want) {
			t.Errorf("view lacks %q:\n%s", want, view)
		}
	}
}

func TestStartBoothOnWorktree(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f)
	m, _ = press(t, m, "down", "down") // main → fix → idea
	m, cmd := press(t, m, "s")
	// In the foreground: booth may build, and may ask before starting.
	if cmd == nil || len(f.ran) != 0 {
		t.Fatalf("s on a worktree: cmd %v ran in background %v", cmd != nil, f.ran)
	}
	if want := []string{"--worktree", "idea", "--daemon"}; len(f.execed) != 1 || !reflect.DeepEqual(f.execed[0], want) || f.execedIn[0] != "/home/u/dev/proj" {
		t.Fatalf("execed %v in %v, want %v in the repository", f.execed, f.execedIn, want)
	}
	next0, _ := m.Update(execDoneMsg{name: "idea", plan: plan{Done: "Started a booth on idea."}})
	if got := next0.(model).status; got != "Started a booth on idea." {
		t.Errorf("status after the start = %q", got)
	}

	// Once the booth shows up, the cursor stays on that worktree, now its booth.
	next, _ := m.Update(snapshotMsg{seq: 2, booths: []lifecycle.Booth{boothAt("idea", "/home/u/dev/proj.worktrees/idea")}, repos: f.repos})
	m = next.(model)
	if b, ok := m.current(); !ok || b.Name != "idea" {
		t.Errorf("cursor left the worktree that gained a booth: %+v", m.rows[m.cursor])
	}
}

func TestStartBoothOnMainCheckout(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f)
	press(t, m, "s")
	if want := []string{"--daemon"}; len(f.execed) != 1 || !reflect.DeepEqual(f.execed[0], want) || f.execedIn[0] != "/home/u/dev/proj" {
		t.Fatalf("execed %v in %v, want %v in the main checkout", f.execed, f.execedIn, want)
	}
}

func TestRemoveWorktreeAsksAndNeverForces(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f)
	m, _ = press(t, m, "d")
	if m.confirm != nil || !strings.Contains(m.status, "main checkout") {
		t.Fatalf("d on the main checkout: confirm %v status %q", m.confirm, m.status)
	}
	m, _ = press(t, m, "down", "d")
	if m.confirm == nil || !strings.Contains(m.confirm.plan.Confirm, "Remove worktree fix") {
		t.Fatalf("d on a worktree must ask: %+v", m.confirm)
	}
	_, cmd := press(t, m, "y")
	cmd()
	if want := []string{"worktree", "remove", "fix"}; !reflect.DeepEqual(f.ran[0], want) || f.ranIn[0] != "/home/u/dev/proj" {
		t.Fatalf("ran %v in %q, want %v", f.ran[0], f.ranIn[0], want)
	}
}

func TestBoothKeysOnBareWorktreeExplain(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f)
	for _, key := range []string{"x", "r", "enter", "o", "p", "m"} {
		m2, cmd := press(t, m, key)
		if cmd != nil || m2.compose != nil || m2.picker != nil || !strings.Contains(m2.status, "No booth on main; s starts one.") {
			t.Errorf("%s on a worktree without a booth: status %q", key, m2.status)
		}
	}
}

func TestNewWorktreePromptCreatesAndStarts(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f)
	m, _ = press(t, m, "n")
	if m.prompt == nil || !strings.Contains(stripANSI(m.View()), "New worktree in proj:") {
		t.Fatalf("n must ask for a name:\n%s", stripANSI(m.View()))
	}
	// Keys are text while the prompt is open.
	m = typeText(t, m, "has space")
	m, cmd := press(t, m, "enter")
	if cmd != nil || m.prompt == nil || m.prompt.err == "" {
		t.Fatalf("a name with a space must be refused: %+v", m.prompt)
	}
	m, _ = press(t, m, "ctrl+u")
	m = typeText(t, m, "feature/x")
	m, cmd = press(t, m, "enter")
	if m.prompt != nil || cmd == nil {
		t.Fatalf("enter: prompt %+v cmd %v", m.prompt, cmd != nil)
	}
	want := []string{"--worktree", "feature/x", "--daemon", "--worktree-keep"}
	if len(f.execed) != 1 || !reflect.DeepEqual(f.execed[0], want) || f.execedIn[0] != "/home/u/dev/proj" {
		t.Fatalf("execed %v in %v, want %v in the repository", f.execed, f.execedIn, want)
	}
	next, _ := m.Update(execDoneMsg{name: "feature/x", plan: newWorktreePlan(&f.repos[0], "feature/x")})
	m = next.(model)
	if m.status != "Created worktree feature/x and started its booth." {
		t.Errorf("status = %q", m.status)
	}

	m, _ = press(t, m, "n", "esc")
	if m.prompt != nil || m.status != "Cancelled." {
		t.Errorf("esc: prompt %+v status %q", m.prompt, m.status)
	}
}

func TestNewWorktreeNeedsARepository(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f, boothAt("loose", "/tmp/scratch"))
	m, _ = press(t, m, "end", "n")
	if m.prompt != nil || !strings.Contains(m.status, "repository") {
		t.Errorf("n under Other booths: prompt %+v status %q", m.prompt, m.status)
	}
}

func TestOpenInEditorAndGitKraken(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f, boothAt("fixer", "/home/u/dev/proj/worktree/fix"))
	m, _ = press(t, m, "down") // fixer
	_, cmd := press(t, m, "e")
	if cmd == nil || !reflect.DeepEqual(f.edited, []string{"/home/u/dev/proj/worktree/fix"}) {
		t.Fatalf("e: cmd %v edited %v", cmd != nil, f.edited)
	}
	m2, cmd := press(t, m, "K")
	next, _ := m2.Update(cmd())
	if got := next.(model).status; got != "Opened ~/dev/proj/worktree/fix in GitKraken." {
		t.Errorf("K status = %q", got)
	}
	if !reflect.DeepEqual(f.krakened, []string{"/home/u/dev/proj/worktree/fix"}) {
		t.Errorf("krakened = %v", f.krakened)
	}

	f.editorErr = errors.New("no editor: set $VISUAL (code is not installed)")
	m3, cmd := press(t, m, "e")
	if cmd != nil || !m3.statusErr || !strings.Contains(m3.status, "no editor") {
		t.Errorf("editor missing: cmd %v status %q", cmd != nil, m3.status)
	}
}

func TestScrollingKeepsGroupHeaderInView(t *testing.T) {
	repos := []lifecycle.Repo{
		{Name: "a", Root: "/a", Worktrees: []lifecycle.Worktree{{Path: "/a", Main: true}, {Path: "/a/w1", Branch: "w1"}, {Path: "/a/w2", Branch: "w2"}}},
		{Name: "b", Root: "/b", Worktrees: []lifecycle.Worktree{{Path: "/b", Main: true}, {Path: "/b/w1", Branch: "w1"}}},
	}
	f := &fakeDeps{repos: repos}
	m := loaded(f)
	next, _ := m.Update(tea.WindowSizeMsg{Width: 100, Height: chromeLines + 3})
	m = next.(model)
	m, _ = press(t, m, "end", "up") // b's main checkout, the first row of its group
	view := stripANSI(m.View())
	if !strings.Contains(view, "b  /b") || !strings.Contains(view, "›") {
		t.Errorf("the header of the cursor's group must show:\n%s", view)
	}
}

func TestGitKrakenKeyOnlyWhenInstalled(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f)
	if !strings.Contains(stripANSI(m.View()), "K GitKraken") {
		t.Errorf("with GitKraken, the hint must offer K:\n%s", stripANSI(m.View()))
	}
	m.deps.GitKraken = nil
	if strings.Contains(stripANSI(m.View()), "GitKraken") {
		t.Errorf("without GitKraken, no K hint:\n%s", stripANSI(m.View()))
	}
	if _, cmd := press(t, m, "K"); cmd != nil || len(f.krakened) != 0 {
		t.Error("K must do nothing without GitKraken")
	}
}

func TestHoldOnFailureWaitsForEnter(t *testing.T) {
	var out strings.Builder
	h := &holdOnFailure{cmd: exec.Command("false"), what: "start web"}
	h.SetStdin(strings.NewReader("\n"))
	h.SetStdout(&out)
	h.SetStderr(&out)
	if err := h.Run(); err == nil {
		t.Fatal("false must fail")
	}
	if !strings.Contains(out.String(), "Could not start web (exit status 1). Press Enter to return to booth dash.") {
		t.Errorf("out = %q", out.String())
	}

	out.Reset()
	ok := &holdOnFailure{cmd: exec.Command("true"), what: "start web"}
	ok.SetStdin(strings.NewReader(""))
	ok.SetStdout(&out)
	if err := ok.Run(); err != nil || out.Len() != 0 {
		t.Errorf("success must return at once: err %v out %q", err, out.String())
	}
}
