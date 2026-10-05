// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// openHandWritten opens the hand-written dialog the way Ctrl+S does.
func openHandWritten(t *testing.T) model {
	t.Helper()
	m := model{drifted: []string{"Boothfile"}}
	res, cmd := m.Update(tea.KeyMsg{Type: tea.KeyCtrlS})
	m = res.(model)
	if !m.overwriteDialog || m.confirmed || cmd != nil {
		t.Fatalf("Ctrl+S should open the hand-written dialog, not save")
	}
	return m
}

func sendKey(m model, msg tea.KeyMsg) (model, tea.Cmd) {
	res, cmd := m.Update(msg)
	return res.(model), cmd
}

// The dialog opens on "save as new" — the choice that loses nothing — so a
// reflex Enter writes .new files and touches nothing of the user's.
func TestHandWrittenDefaultsToSaveBeside(t *testing.T) {
	m := openHandWritten(t)
	if m.overwriteChoice != overwriteBeside {
		t.Fatalf("choice = %d, want save beside (%d)", m.overwriteChoice, overwriteBeside)
	}
	m, cmd := sendKey(m, keyOf(tea.KeyEnter))
	if !m.confirmed || !m.saveBeside || m.noBackup || cmd == nil {
		t.Fatalf("Enter should save beside: confirmed=%v saveBeside=%v noBackup=%v", m.confirmed, m.saveBeside, m.noBackup)
	}
}

// Apply replaces the files with a .bak kept, so it takes no typed word.
func TestHandWrittenApplyNeedsNoWord(t *testing.T) {
	m := openHandWritten(t)
	m, _ = sendKey(m, keyMsg('1'))
	m, cmd := sendKey(m, keyOf(tea.KeyEnter))
	if !m.confirmed || m.saveBeside || m.noBackup || cmd == nil {
		t.Fatalf("1 + Enter should apply with a backup: confirmed=%v saveBeside=%v noBackup=%v", m.confirmed, m.saveBeside, m.noBackup)
	}
}

// Overwriting with no backup waits for the word typed in full.
func TestHandWrittenOutrightNeedsTheWord(t *testing.T) {
	m := openHandWritten(t)
	m, _ = sendKey(m, keyOf(tea.KeyDown)) // 2 → 3
	if m.overwriteChoice != overwriteOutright {
		t.Fatalf("Down should move to choice 3, got %d", m.overwriteChoice)
	}
	for _, ch := range "overwrit" {
		m, _ = sendKey(m, keyMsg(ch))
	}
	m, cmd := sendKey(m, keyOf(tea.KeyEnter))
	if m.confirmed || cmd != nil {
		t.Fatal("a half-typed word must not overwrite")
	}
	m, _ = sendKey(m, keyMsg('e'))
	m, cmd = sendKey(m, keyOf(tea.KeyEnter))
	if !m.confirmed || !m.noBackup || m.saveBeside || cmd == nil {
		t.Fatalf("the full word should overwrite with no backup: confirmed=%v noBackup=%v", m.confirmed, m.noBackup)
	}
}

// Letters typed while another choice is focused go nowhere — only the outright
// overwrite has a field.
func TestHandWrittenTypingNeedsChoiceThree(t *testing.T) {
	m := openHandWritten(t)
	for _, ch := range overwriteConfirmWord {
		m, _ = sendKey(m, keyMsg(ch))
	}
	if m.overwriteInput != "" {
		t.Fatalf("input = %q, want empty while choice 2 is focused", m.overwriteInput)
	}
}

func TestHandWrittenEscBacksOut(t *testing.T) {
	m := openHandWritten(t)
	m, cmd := sendKey(m, keyOf(tea.KeyEsc))
	if m.overwriteDialog || m.confirmed || cmd != nil {
		t.Fatal("Esc should close the dialog with nothing saved")
	}
}

// The dialog names the risk first, says why the edits were not read back, and
// lists all three choices.
func TestHandWrittenDialogText(t *testing.T) {
	m := openHandWritten(t)
	m.width, m.height = 140, 60
	m.adoptReasons = []string{"Boothfile `run make` — no selection or flag produces this line"}
	view := m.renderOverwriteDialog()
	for _, want := range []string{
		"Your booth files have changes booth config did not make",
		"You are at risk of losing your hand-written booth configuration",
		"run make",
		"Apply, and back up your files",
		".booth/Boothfile.bak",
		"Save as new, to compare",
		".booth/Boothfile.new",
		"Overwrite, with no backup",
	} {
		if !strings.Contains(view, want) {
			t.Errorf("dialog does not show %q", want)
		}
	}
	if strings.Contains(view, "HAND-WRITTEN") {
		t.Error("the title should not shout")
	}
}

// adoptedModel is a TUI opened on a booth edited outside booth config, whose
// edits were read back, as RunConfig sets it up.
func adoptedModel(refreshed *bool) model {
	return model{
		adoptedFiles:       []string{"config.toml"},
		adoptedChanges:     []string{"+ --set timezone=Asia/Bangkok"},
		adoptedModified:    map[string]string{"config.toml": "2026-10-04 12:14:54 +07"},
		adoptedDialog:      true,
		refreshFingerprint: func() error { *refreshed = true; return nil },
	}
}

func TestAdoptedOKAcceptsAndMovesOn(t *testing.T) {
	refreshed := false
	m, cmd := sendKey(adoptedModel(&refreshed), keyOf(tea.KeyEnter))
	if !refreshed || m.adoptedDialog || m.review || cmd != nil {
		t.Fatalf("OK should accept and carry on: refreshed=%v open=%v", refreshed, m.adoptedDialog)
	}
}

// Cancel leaves to review: nothing is refreshed, nothing saved.
func TestAdoptedCancelQuitsToReview(t *testing.T) {
	for _, keys := range [][]tea.KeyMsg{{keyOf(tea.KeyRight), keyOf(tea.KeyEnter)}, {keyOf(tea.KeyEsc)}, {keyMsg('c')}} {
		refreshed := false
		m := adoptedModel(&refreshed)
		var cmd tea.Cmd
		for _, k := range keys {
			m, cmd = sendKey(m, k)
		}
		if refreshed || !m.review || m.confirmed || cmd == nil {
			t.Fatalf("Cancel should quit for review: refreshed=%v review=%v confirmed=%v", refreshed, m.review, m.confirmed)
		}
	}
}

// The question says what changed, and comes before the startup warning.
func TestAdoptedDialogShowsChangesFirst(t *testing.T) {
	refreshed := false
	m := adoptedModel(&refreshed)
	m.warningDialog = true
	m.width, m.height = 120, 40
	view := m.View()
	for _, want := range []string{"changed outside booth config", ".booth/config.toml", "+ --set timezone=Asia/Bangkok", "modified 2026-10-04 12:14:54 +07", "Cancel: quit and review first"} {
		if !strings.Contains(view, want) {
			t.Errorf("question does not show %q", want)
		}
	}
	m, _ = sendKey(m, keyMsg('o'))
	if !m.warningDialog {
		t.Fatal("after accepting, the startup warning should still be up")
	}
}
