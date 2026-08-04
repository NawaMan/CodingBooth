// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// cancelKey is what a user presses to leave; both Ctrl+C and Ctrl+E arrive here.
func cancelKey() tea.KeyMsg { return tea.KeyMsg{Type: tea.KeyCtrlE} }

// quitsImmediately reports how a cancel resolved: quitting outright, or asking.
func quitsImmediately(t *testing.T, m model) (quit bool, asked bool) {
	t.Helper()
	res, cmd := m.Update(cancelKey())
	after := res.(model)
	return cmd != nil, after.quitting
}

// An untouched session has nothing to confirm — opening the TUI and leaving it
// should not cost a keystroke.
func TestCancelOnAnUntouchedSessionQuitsWithoutAsking(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})

	quit, asked := quitsImmediately(t, m)
	if !quit {
		t.Fatal("cancel on an untouched session should quit")
	}
	if asked {
		t.Fatal("there is nothing to lose, so nothing to ask about")
	}
}

func TestCancelAfterAChangeAsksFirst(t *testing.T) {
	cases := []struct {
		name   string
		change func(m model) model
	}{
		{"a selection", func(m model) model {
			return click(m, 1, contentTop)
		}},
		{"a param value", func(m model) model {
			m.paramValues["go:GO_VERSION"] = "1.24.13"
			return m
		}},
		{"a config bool", func(m model) model {
			m.boolFields["dind"] = true
			return m
		}},
		{"a config string", func(m model) model {
			m.stringFields["port"] = "18080"
			return m
		}},
		{"a list field", func(m model) model {
			m.listFields["expose"] = []string{"8080"}
			return m
		}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			m := c.change(mouseModel([]treeItem{templateItem("go")}))
			quit, asked := quitsImmediately(t, m)
			if quit {
				t.Fatalf("%s is unsaved work — cancel must not quit on it", c.name)
			}
			if !asked {
				t.Fatalf("%s should raise the confirmation", c.name)
			}
		})
	}
}

// Undoing by hand really is no change: the comparison sees the state, not a flag
// that some mutation left set on the way through.
func TestCancelAfterUndoingEveryChangeQuitsWithoutAsking(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go"), templateItem("python")})

	m = click(m, 1, contentTop)   // select go
	m = click(m, 1, contentTop+1) // select python
	if quit, _ := quitsImmediately(t, m); quit {
		t.Fatal("two selections in, cancel should be asking")
	}

	m = click(m, 1, contentTop)   // deselect go
	m = click(m, 1, contentTop+1) // deselect python

	quit, asked := quitsImmediately(t, m)
	if !quit || asked {
		t.Fatalf("back at the opening state, cancel should just quit: quit=%v asked=%v", quit, asked)
	}
}

// A value being typed has not reached the maps yet, which is exactly when losing it
// would hurt most.
func TestCancelWhileTypingAsksFirst(t *testing.T) {
	items := goItems()
	m := mouseModel(items)
	m.setCursor(1)
	m.selected["go"] = true
	m.selected["go/go-pkg"] = true
	m.baseline = m.snapshot() // opened with these already selected
	m.paramFocused = true
	m.beginVariadicEdit("go/go-pkg:GO_PKGS", 0, "", true)
	m.variadicEditBuf = "gopls@latest"

	quit, asked := quitsImmediately(t, m)
	if quit {
		t.Fatal("a half-typed value must not be dropped without asking")
	}
	if !asked {
		t.Fatal("cancel mid-edit should raise the confirmation")
	}
}

// The footer buttons act while a field is being edited, so the keys behind them
// must too — they used to fall through to the "insert a character" branch and do
// nothing, leaving no way out of an edit but Enter or Esc.
func TestSaveAndCancelKeysWorkWhileEditing(t *testing.T) {
	newEditing := func() model {
		items := goItems()
		m := mouseModel(items)
		m.setCursor(1)
		m.selected["go"] = true
		m.selected["go/go-pkg"] = true
		m.baseline = m.snapshot()
		m.paramFocused = true
		m.beginVariadicEdit("go/go-pkg:GO_PKGS", 0, "", true)
		m.variadicEditBuf = "gopls@latest"
		return m
	}

	// Ctrl+S commits the value and saves it, rather than being swallowed.
	res, cmd := newEditing().Update(tea.KeyMsg{Type: tea.KeyCtrlS})
	saved := res.(model)
	if !saved.confirmed || cmd == nil {
		t.Fatalf("Ctrl+S mid-edit should save: confirmed=%v cmd=%v", saved.confirmed, cmd)
	}
	if got := saved.paramValues["go/go-pkg:GO_PKGS"]; got != "gopls@latest" {
		t.Fatalf("the in-progress value should be committed, got %q", got)
	}

	// Ctrl+E asks, because that value would otherwise be lost.
	res, cmd = newEditing().Update(cancelKey())
	asked := res.(model)
	if cmd != nil || !asked.quitting {
		t.Fatalf("Ctrl+E mid-edit should ask: cmd=%v quitting=%v", cmd, asked.quitting)
	}

	// A config-tab string field behaves the same way: the key reaches the handler
	// rather than being typed into the field.
	m := mouseModel(nil)
	m.activeTab = 0
	m.editing = true
	m.stringFields["port"] = "18080" // something worth asking about
	res, cmd = m.Update(cancelKey())
	cfg := res.(model)
	if cmd != nil || !cfg.quitting {
		t.Fatalf("Ctrl+E while editing a config field should ask: cmd=%v quitting=%v", cmd, cfg.quitting)
	}

	// And with nothing typed and nothing changed, the same key just leaves — an
	// open editor is not by itself unsaved work.
	idle := mouseModel(nil)
	idle.activeTab = 0
	idle.editing = true
	res, cmd = idle.Update(cancelKey())
	if cmd == nil || res.(model).quitting {
		t.Fatalf("an untouched field should not raise a question: cmd=%v quitting=%v",
			cmd, res.(model).quitting)
	}
}

// Flags are not the user's edits: a booth opened with --select and left alone has
// nothing to confirm.
func TestPreSelectedFlagsCountAsUnchanged(t *testing.T) {
	pre := &PreSelection{
		SelectedTemplates: map[string]bool{"go": true},
		SelectedExts:      map[string]map[string]bool{"go": {"go-pkg": true}},
		StringFields:      map[string]string{"port": "10080"},
		ParamValues:       map[string]string{"go:GO_VERSION": "1.24.13"},
	}
	m := newModel(goRegistry(), pre)
	m.width, m.height = 100, 30

	if m.hasUnsavedChanges() {
		t.Fatal("pre-populated state is what the session opened with, not a change")
	}
	quit, asked := quitsImmediately(t, m)
	if !quit || asked {
		t.Fatalf("cancel should quit: quit=%v asked=%v", quit, asked)
	}

	// One real edit on top, and it asks again.
	m.paramValues["go:GO_VERSION"] = "1.23.12"
	if !m.hasUnsavedChanges() {
		t.Fatal("editing a pre-populated value is still an edit")
	}
}

// An existing booth reopened and left alone is the common case for this: reading a
// configuration must not turn into a prompt about discarding it.
func TestReopenedBoothWithNoEditsQuitsWithoutAsking(t *testing.T) {
	pre := &PreSelection{
		SelectedTemplates: map[string]bool{"go": true},
		ListFields:        map[string][]string{"expose": {"8080", "9090"}},
		BoolFields:        map[string]bool{"dind": true},
	}
	m := newModel(goRegistry(), pre)
	m.width, m.height = 100, 30

	quit, asked := quitsImmediately(t, m)
	if !quit || asked {
		t.Fatalf("nothing was touched: quit=%v asked=%v", quit, asked)
	}

	// Removing one entry of a pre-populated list is a change — the snapshot compares
	// contents, not just which keys are present.
	m.listFields["expose"] = []string{"8080"}
	if !m.hasUnsavedChanges() {
		t.Fatal("dropping a list entry is a change")
	}
}

func TestSnapshotIsACopy(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	snap := m.snapshot()

	m.selected["go"] = true
	m.listFields["expose"] = []string{"8080"}
	m.paramValues["go:GO_VERSION"] = "1.24.13"

	if snap.equal(m.snapshot()) {
		t.Fatal("a snapshot that aliases the live maps can never report a change")
	}
}

// The whole point of comparing rather than flagging: a handler that mutates state
// cannot forget to mark it.
func TestEveryEditableFieldIsWatched(t *testing.T) {
	base := mouseModel([]treeItem{templateItem("go")})
	for _, c := range []struct {
		field  string
		mutate func(m *model)
	}{
		{"selected", func(m *model) { m.selected["go"] = true }},
		{"paramValues", func(m *model) { m.paramValues["go:GO_VERSION"] = "x" }},
		{"stringFields", func(m *model) { m.stringFields["variant"] = "codeserver" }},
		{"boolFields", func(m *model) { m.boolFields["sudo"] = true }},
		{"listFields", func(m *model) { m.listFields["env"] = []string{"A=1"} }},
	} {
		m := base
		m.selected = map[string]bool{}
		m.paramValues = map[string]string{}
		m.stringFields = map[string]string{}
		m.boolFields = map[string]bool{}
		m.listFields = map[string][]string{}
		m.baseline = m.snapshot()

		c.mutate(&m)
		if !m.hasUnsavedChanges() {
			t.Fatalf("a change to %s went unnoticed", c.field)
		}
	}
}

// Navigating is not editing.
func TestLookingAroundIsNotAChange(t *testing.T) {
	items := []treeItem{templateItem("go"), templateItem("python")}
	m := mouseModel(items)
	m.registry = &tmpl.TemplateRegistry{ByName: map[string]*tmpl.Template{}}

	m = click(m, 30, contentTop+1) // move the cursor
	res, _ := m.Update(clickAt(10, rowSearch))
	m = res.(model)
	res, _ = m.Update(runesMsg("go"))
	m = res.(model)
	res, _ = m.Update(wheelAt(10, contentTop+1, tea.MouseButtonWheelDown))
	m = res.(model)

	if m.hasUnsavedChanges() {
		t.Fatal("moving the cursor, searching and scrolling change nothing")
	}
}
