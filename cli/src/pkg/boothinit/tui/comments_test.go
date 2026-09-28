// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

const lostComment = ".booth/config.toml:3  # team port"

// A booth whose hand edits were read back saves normally — except that the
// comments it holds cannot be carried, so the save names them and waits.
func TestSaveWithLostCommentsAsksFirst(t *testing.T) {
	m := model{lostComments: []string{lostComment}}

	res, cmd := m.Update(tea.KeyMsg{Type: tea.KeyCtrlS})
	m = res.(model)
	if !m.commentsDialog || m.confirmed || cmd != nil {
		t.Fatalf("Ctrl+S should open the comments dialog, not save: open=%v confirmed=%v cmd=%v",
			m.commentsDialog, m.confirmed, cmd)
	}

	// Esc goes back to configuring, nothing written.
	res, cmd = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	back := res.(model)
	if back.commentsDialog || back.confirmed || cmd != nil {
		t.Fatalf("Esc should close the dialog without saving: open=%v confirmed=%v", back.commentsDialog, back.confirmed)
	}

	// Enter saves.
	res, cmd = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	saved := res.(model)
	if !saved.confirmed || cmd == nil {
		t.Fatalf("Enter should save: confirmed=%v cmd=%v", saved.confirmed, cmd)
	}
	if saved.saveBeside {
		t.Fatal("an adopted booth is written in place, not beside")
	}
}

func TestSaveWithoutLostCommentsSavesDirectly(t *testing.T) {
	res, cmd := model{}.Update(tea.KeyMsg{Type: tea.KeyCtrlS})
	m := res.(model)
	if !m.confirmed || m.commentsDialog || cmd == nil {
		t.Fatalf("with nothing to lose, Ctrl+S saves: confirmed=%v dialog=%v", m.confirmed, m.commentsDialog)
	}
}

// Hand-written files take the overwrite dialog; the comments dialog is only for
// edits that were read back.
func TestHandWrittenTakesPrecedenceOverComments(t *testing.T) {
	m := model{drifted: []string{"Boothfile"}, lostComments: []string{lostComment}}
	res, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlS})
	m = res.(model)
	if !m.overwriteDialog || m.commentsDialog {
		t.Fatalf("drifted files must route to the overwrite dialog: overwrite=%v comments=%v",
			m.overwriteDialog, m.commentsDialog)
	}
}

func TestCommentsDialogIgnoresClicks(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	m.lostComments = []string{lostComment}
	m.commentsDialog = true
	m = click(m, 10, 10)
	if !m.commentsDialog || m.confirmed {
		t.Fatalf("a click must not answer the comments dialog: open=%v confirmed=%v", m.commentsDialog, m.confirmed)
	}
}

func TestCommentsDialogListsTheComments(t *testing.T) {
	m := model{width: 100, height: 40, lostComments: []string{lostComment}, commentsDialog: true}
	view := m.View()
	if !strings.Contains(view, "# team port") || !strings.Contains(view, "Esc: back") {
		t.Fatalf("the dialog should list the comment and how to back out:\n%s", view)
	}
}
