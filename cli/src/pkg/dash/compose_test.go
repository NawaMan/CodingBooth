// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// typeText types s one key at a time, spaces as the space key.
func typeText(t *testing.T, m model, s string) model {
	t.Helper()
	for _, r := range s {
		m, _ = press(t, m, string(r))
	}
	return m
}

func TestTextFieldEditing(t *testing.T) {
	var f textField
	for _, msg := range []tea.KeyMsg{
		keyMsg("h"), keyMsg("e"), keyMsg("y"), keyMsg(" "), keyMsg("u"),
		keyMsg("left"), keyMsg("left"), keyMsg("backspace"), // "hey u": back over " u", delete the y
	} {
		f.update(msg)
	}
	if got := f.String(); got != "he u" || f.cursor != 2 {
		t.Fatalf("field = %q cursor %d, want \"he u\" cursor 2", got, f.cursor)
	}
	f.update(keyMsg("home"))
	f.update(keyMsg("X"))
	if got := f.String(); got != "Xhe u" || f.cursor != 1 {
		t.Fatalf("field = %q cursor %d", got, f.cursor)
	}
	f.update(tea.KeyMsg{Type: tea.KeyDelete})
	if got := f.String(); got != "Xe u" {
		t.Fatalf("delete: %q", got)
	}
	f.update(keyMsg("ctrl+u"))
	if f.String() != "" || f.cursor != 0 {
		t.Fatalf("ctrl+u: %q %d", f.String(), f.cursor)
	}
	if f.update(keyMsg("enter")) {
		t.Error("enter is not the field's key")
	}
}

func TestTextFieldPasteFlattensLines(t *testing.T) {
	var f textField
	f.update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("one\ntwo\tthree\x07"), Paste: true})
	if got := f.String(); got != "one two three" {
		t.Fatalf("pasted = %q", got)
	}
}

func TestTextFieldViewScrollsToCursor(t *testing.T) {
	f := textField{text: []rune("abcdefghij"), cursor: 10}
	if got := stripANSI(f.view(5, true)); got != "ghij " {
		t.Errorf("focused at end = %q, want \"ghij \"", got)
	}
	f.cursor = 0
	if got := stripANSI(f.view(5, true)); got != "abcd" {
		t.Errorf("focused at start = %q, want \"abcd\"", got)
	}
	if got := f.view(5, false); got != "abcde" {
		t.Errorf("unfocused = %q", got)
	}
}

func TestMessageToastSendsAndReports(t *testing.T) {
	f := &fakeDeps{messageOut: "msg-1\n"}
	m := loaded(f, running("web"))

	m, _ = press(t, m, "m")
	if m.compose == nil {
		t.Fatal("m must open the compose box")
	}
	view := stripANSI(m.View())
	for _, want := range []string{"Message to web", "Type", "toast", "esc cancel"} {
		if !strings.Contains(view, want) {
			t.Errorf("compose view lacks %q:\n%s", want, view)
		}
	}

	// Keys inside the box are text, not booth actions.
	m, _ = press(t, m, "tab")
	m = typeText(t, m, "Build done")
	m, _ = press(t, m, "enter")
	m = typeText(t, m, "x d s q")
	if m.confirm != nil || len(f.ran) != 0 {
		t.Fatal("letters typed into the box ran booth actions")
	}
	m, cmd := press(t, m, "enter")
	if m.compose != nil || cmd == nil {
		t.Fatalf("enter on body must send: compose %v cmd %v", m.compose, cmd != nil)
	}
	if len(m.asking) != 0 {
		t.Error("a toast is not a question")
	}
	next, _ := m.Update(cmd())
	m = next.(model)
	want := []string{"message", "send", "--name", "web", "--engine", "docker",
		"--type", "toast", "--title", "Build done", "--body", "x d s q"}
	if len(f.messaged) != 1 || !reflect.DeepEqual(f.messaged[0], want) {
		t.Fatalf("messaged = %v, want %v", f.messaged, want)
	}
	if m.status != "Sent toast to web." || m.statusErr {
		t.Errorf("status = %q", m.status)
	}
}

func TestMessageQuestionMarksRowUntilAnswered(t *testing.T) {
	f := &fakeDeps{messageOut: "msg-1\nWaiting for response (variant: base)...\nyes\n"}
	m := loaded(f, running("web"))

	m, _ = press(t, m, "m", "right", "right") // toast → banner → question
	if got := messageKinds[m.compose.kind].Type; got != "yes-no" {
		t.Fatalf("type = %s", got)
	}
	m, _ = press(t, m, "tab")
	m = typeText(t, m, "Deploy?")
	m, _ = press(t, m, "tab")
	m = typeText(t, m, "Ship it")
	m, cmd := press(t, m, "ctrl+s")
	if m.asking["web@docker"] != 1 {
		t.Fatalf("asking = %v", m.asking)
	}
	if !strings.Contains(stripANSI(m.View()), "Running ?") {
		t.Errorf("row lacks the question marker:\n%s", stripANSI(m.View()))
	}

	// The booth's other keys stay usable while it waits.
	m, _ = press(t, m, "x")
	if m.confirm == nil {
		t.Error("stop must still ask while a question is open")
	}
	m, _ = press(t, m, "n")

	next, _ := m.Update(cmd())
	m = next.(model)
	if f.messaged[0][7] != "yes-no" {
		t.Errorf("args = %v", f.messaged[0])
	}
	if len(m.asking) != 0 {
		t.Errorf("asking not cleared: %v", m.asking)
	}
	if m.status != "web answered: yes" {
		t.Errorf("status = %q", m.status)
	}
}

func TestMessageTimeoutAndFailure(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"))
	ask := messageKinds[2]

	next, _ := m.Update(messageDoneMsg{key: "web@docker", name: "web", kind: ask, output: "msg-1\ntimeout\n"})
	if got := next.(model).status; got != "web: no answer (timed out)." {
		t.Errorf("timeout status = %q", got)
	}
	next, _ = m.Update(messageDoneMsg{key: "web@docker", name: "web", kind: ask,
		output: "Error: no running booth named \"web\"\n", err: errors.New("exit status 1")})
	if got := next.(model); got.status != `Error: no running booth named "web"` || !got.statusErr {
		t.Errorf("failure status = %q (err %v)", got.status, got.statusErr)
	}
}

func TestMessageNeedsTitleAndBody(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"))

	m, cmd := press(t, m, "m", "ctrl+s")
	if cmd != nil || m.compose == nil || m.compose.focus != focusTitle {
		t.Fatalf("empty title must stay in the box on Title: cmd %v compose %+v", cmd != nil, m.compose)
	}
	if !strings.Contains(stripANSI(m.View()), "needs a title") {
		t.Errorf("no title error shown:\n%s", stripANSI(m.View()))
	}
	m = typeText(t, m, "Hi")
	m, cmd = press(t, m, "ctrl+s")
	if cmd != nil || m.compose.focus != focusBody || m.compose.err != "A message needs a body." {
		t.Fatalf("empty body: cmd %v compose %+v", cmd != nil, m.compose)
	}
	if len(f.messaged) != 0 {
		t.Error("nothing may be sent")
	}
}

func TestMessageEscCancelsAndStoppedBoothRefuses(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"), stopped("db"))

	m, _ = press(t, m, "m", "tab")
	m = typeText(t, m, "draft")
	m, _ = press(t, m, "esc")
	if m.compose != nil || m.status != "Cancelled." || len(f.messaged) != 0 {
		t.Fatalf("esc: compose %v status %q messaged %v", m.compose, m.status, f.messaged)
	}

	m, _ = press(t, m, "down", "m")
	if m.compose != nil || !strings.Contains(m.status, "not running") {
		t.Errorf("stopped booth: compose %v status %q", m.compose, m.status)
	}
}

func TestComposeShrinksTable(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("a"), running("b"), running("c"), running("d"), running("e"))
	next, _ := m.Update(tea.WindowSizeMsg{Width: 100, Height: chromeLines + composeLines + 2})
	m = next.(model)
	m, _ = press(t, m, "G", "m")
	if rows := m.tableRows(); rows != 2 {
		t.Fatalf("rows = %d", rows)
	}
	view := stripANSI(m.View())
	if !strings.Contains(view, "› e") || strings.Contains(view, " a ") {
		t.Errorf("cursor row must stay visible with the box open:\n%s", view)
	}
}
