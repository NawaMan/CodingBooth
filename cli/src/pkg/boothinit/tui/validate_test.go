// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// aptSnapshotEdit opens the Apt Snapshot field the way Enter does, with a value
// already in it, and then types over it.
func aptSnapshotEdit(t *testing.T, before, typed string) model {
	t.Helper()
	m := configModelAt(t, "apt-snapshot")
	m.stringFields["apt-snapshot"] = before
	m, _ = sendKey(m, keyOf(tea.KeyEnter))
	if !m.editing {
		t.Fatal("Enter should open the field for editing")
	}
	for range before {
		m, _ = sendKey(m, keyOf(tea.KeyBackspace))
	}
	for _, ch := range typed {
		m, _ = sendKey(m, keyMsg(ch))
	}
	return m
}

// Enter on a value apt cannot use keeps the edit open, so the value is still
// there to fix, and the panel says why — in the field's own words.
func TestValidatedField_EnterOnBadValueStaysOpenAndSaysWhy(t *testing.T) {
	m := aptSnapshotEdit(t, "20250101T000000Z", "2026-01-01")
	m, _ = sendKey(m, keyOf(tea.KeyEnter))

	if !m.editing {
		t.Fatal("Enter on an invalid value must keep the edit open")
	}
	if got := m.stringFields["apt-snapshot"]; got != "2026-01-01" {
		t.Fatalf("the typed value should stay to be fixed, got %q", got)
	}
	view := m.View()
	for _, want := range []string{
		`✗ "2026-01-01" is not a snapshot id`,
		"YYYYMMDDTHHMMSSZ",
		"leave it empty for no freeze",
		"Esc puts back 20250101T000000Z",
	} {
		if !strings.Contains(view, want) {
			t.Errorf("the panel should say %q:\n%s", want, view)
		}
	}
}

// Typing again clears the error — it quoted a value that is no longer there —
// and a value the field accepts then commits.
func TestValidatedField_FixingTheValueCommits(t *testing.T) {
	m := aptSnapshotEdit(t, "20250101T000000Z", "bad")
	m, _ = sendKey(m, keyOf(tea.KeyEnter))
	if m.editErr == "" {
		t.Fatal("expected an error for \"bad\"")
	}

	for range "bad" {
		m, _ = sendKey(m, keyOf(tea.KeyBackspace))
	}
	if m.editErr != "" {
		t.Fatalf("changing the value should clear the old error, still %q", m.editErr)
	}
	for _, ch := range "TODAY" {
		m, _ = sendKey(m, keyMsg(ch))
	}
	m, _ = sendKey(m, keyOf(tea.KeyEnter))
	if m.editing || m.editErr != "" {
		t.Fatalf("TODAY should commit: editing=%v err=%q", m.editing, m.editErr)
	}
}

// Esc backs out of a value that cannot be kept, to what the field held before.
func TestValidatedField_EscPutsBackThePreviousValue(t *testing.T) {
	m := aptSnapshotEdit(t, "20250101T000000Z", "nope")
	m, _ = sendKey(m, keyOf(tea.KeyEsc))

	if m.editing || m.editErr != "" {
		t.Fatalf("Esc should close the edit: editing=%v err=%q", m.editing, m.editErr)
	}
	if got := m.stringFields["apt-snapshot"]; got != "20250101T000000Z" {
		t.Fatalf("Esc should put back the previous value, got %q", got)
	}
}

// Emptying the field is a choice (no freeze), not an error.
func TestValidatedField_EmptyIsAccepted(t *testing.T) {
	m := aptSnapshotEdit(t, "20250101T000000Z", "")
	m, _ = sendKey(m, keyOf(tea.KeyEnter))
	if m.editing || m.stringFields["apt-snapshot"] != "" {
		t.Fatalf("an empty value should commit: editing=%v value=%q", m.editing, m.stringFields["apt-snapshot"])
	}
}

// Ctrl+S works from inside an edit, so it is a second way out with a bad value;
// it must not save one. The same holds for a bad value that came in preloaded.
func TestValidatedField_SaveRefusesBadValue(t *testing.T) {
	m := aptSnapshotEdit(t, "20250101T000000Z", "20991301T000000Z")
	m, cmd := sendKey(m, tea.KeyMsg{Type: tea.KeyCtrlS})
	if m.confirmed || cmd != nil {
		t.Fatal("Ctrl+S must not save an invalid value")
	}
	if !m.editing || m.editErr == "" {
		t.Fatalf("the refused field should be open with its error: editing=%v err=%q", m.editing, m.editErr)
	}

	m = configModelAt(t, "name") // cursor elsewhere, field not being edited
	m.stringFields["apt-snapshot"] = "garbage"
	m, cmd = sendKey(m, tea.KeyMsg{Type: tea.KeyCtrlS})
	if m.confirmed || cmd != nil {
		t.Fatal("Ctrl+S must not save a preloaded invalid value")
	}
	if f := m.currentConfigField(); f == nil || f.Key != "apt-snapshot" || !m.editing {
		t.Fatal("the save should land on the refused field, open for editing")
	}
}

// Clicking away accepts a value the way Enter would — but not one the field
// refuses: that click backs out, like Esc.
func TestValidatedField_ClickAwayBacksOutOfBadValue(t *testing.T) {
	m := aptSnapshotEdit(t, "20250101T000000Z", "nope")
	m, _, _ = clickConfigField(t, m, "name")
	if got := m.stringFields["apt-snapshot"]; got != "20250101T000000Z" {
		t.Fatalf("clicking away should put back the previous value, got %q", got)
	}
	if m.editErr != "" {
		t.Fatalf("no error should linger after leaving the field: %q", m.editErr)
	}
}

// imageSnapshotModel parks the cursor on Apt Snapshot, holding value, with an
// image built at imageSnap ("" = not known).
func imageSnapshotModel(t *testing.T, value, imageSnap string) model {
	t.Helper()
	m := configModelAt(t, "apt-snapshot")
	m.stringFields["apt-snapshot"] = value
	m.imageAptSnapshot = func(settings map[string]string) (string, string) {
		return "nawaman/codingbooth:" + settings["variant"] + "-0.80.0", imageSnap
	}
	m.stringFields["variant"] = "base"
	return m
}

// The panel says what the booth's image was built at, and warns — without
// refusing — when the field holds an older snapshot.
func TestAptSnapshotPanel_WarnsWhenOlderThanTheImage(t *testing.T) {
	view := imageSnapshotModel(t, "20250101T000000Z", "20261004T000000Z").View()
	for _, want := range []string{
		"  nawaman/codingbooth:base-0.80.0",
		"was built at 20261004T000000Z.",
		"⚠ 20250101T000000Z is older than the image.",
		"Use 20261004T000000Z, or TODAY.",
	} {
		if !strings.Contains(view, want) {
			t.Errorf("the panel should say %q:\n%s", want, view)
		}
	}

	m := imageSnapshotModel(t, "20250101T000000Z", "20261004T000000Z")
	m, cmd := sendKey(m, tea.KeyMsg{Type: tea.KeyCtrlS})
	if !m.confirmed || cmd == nil {
		t.Fatal("an older snapshot is a warning, not a reason to refuse the save")
	}
}

func TestAptSnapshotPanel_NoWarningWhenNotOlder(t *testing.T) {
	for name, value := range map[string]string{
		"the image's own": "20261004T000000Z",
		"newer":           "20261010T000000Z",
		"TODAY":           "TODAY",
		"no freeze":       "",
	} {
		view := imageSnapshotModel(t, value, "20261004T000000Z").View()
		if !strings.Contains(view, "was built at 20261004T000000Z.") {
			t.Errorf("%s: the image's snapshot should still be shown", name)
		}
		if strings.Contains(view, "older than the image") {
			t.Errorf("%s: no warning expected:\n%s", name, view)
		}
	}
}

func TestAptSnapshotPanel_SilentWhenTheImageIsUnknown(t *testing.T) {
	view := imageSnapshotModel(t, "20250101T000000Z", "").View()
	if strings.Contains(view, "was built at") || strings.Contains(view, "older than the image") {
		t.Errorf("with no image snapshot there is nothing to say:\n%s", view)
	}
}
