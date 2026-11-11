// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// messageKind is one choice of the compose box's Type field.
type messageKind struct {
	Label string // shown in the form
	Type  string // `booth message send --type`
	// Ask: the command waits for the booth user's answer (up to 10 minutes),
	// which comes back to the status line.
	Ask bool
}

var messageKinds = []messageKind{
	{Label: "toast", Type: "toast"},
	{Label: "banner", Type: "banner"},
	{Label: "question (yes/no)", Type: "yes-no", Ask: true},
	{Label: "ok", Type: "ok", Ask: true},
	{Label: "text", Type: "text", Ask: true},
}

// The compose box's fields, in tab order.
const (
	focusType = iota
	focusTitle
	focusBody
	focusCount
)

// composeLines is how many lines the compose box takes below the table:
// a blank, its header, and one line per field.
const composeLines = 2 + focusCount

const composeHelpLine = "tab next field · ←/→ change type · enter send · esc cancel"

// compose is the message being written to a booth with m.
type compose struct {
	booth lifecycle.Booth
	kind  int
	focus int
	title textField
	body  textField
	err   string
}

// textField is a one-line text input: typing, paste, ←/→, home/end,
// backspace/delete, ctrl+u to clear.
type textField struct {
	text   []rune
	cursor int
}

func (f textField) String() string { return string(f.text) }

// update applies a key to the field, and says whether the key was its to use.
func (f *textField) update(msg tea.KeyMsg) bool {
	switch msg.Type {
	case tea.KeyRunes, tea.KeySpace:
		runes := msg.Runes
		if msg.Type == tea.KeySpace && len(runes) == 0 {
			runes = []rune{' '}
		}
		f.insert(runes)
	case tea.KeyBackspace:
		if f.cursor > 0 {
			f.text = append(f.text[:f.cursor-1], f.text[f.cursor:]...)
			f.cursor--
		}
	case tea.KeyDelete:
		if f.cursor < len(f.text) {
			f.text = append(f.text[:f.cursor], f.text[f.cursor+1:]...)
		}
	case tea.KeyLeft:
		f.cursor = max(0, f.cursor-1)
	case tea.KeyRight:
		f.cursor = min(len(f.text), f.cursor+1)
	case tea.KeyHome, tea.KeyCtrlA:
		f.cursor = 0
	case tea.KeyEnd, tea.KeyCtrlE:
		f.cursor = len(f.text)
	case tea.KeyCtrlU:
		f.text, f.cursor = nil, 0
	default:
		return false
	}
	return true
}

// insert puts runes at the cursor. A pasted line break becomes a space: the
// field is one line, and the message body is shown as one paragraph anyway.
func (f *textField) insert(runes []rune) {
	clean := make([]rune, 0, len(runes))
	for _, r := range runes {
		switch {
		case r == '\n' || r == '\r' || r == '\t':
			clean = append(clean, ' ')
		case r < ' ' || r == 0x7f:
			// other control characters are dropped
		default:
			clean = append(clean, r)
		}
	}
	text := make([]rune, 0, len(f.text)+len(clean))
	text = append(text, f.text[:f.cursor]...)
	text = append(text, clean...)
	text = append(text, f.text[f.cursor:]...)
	f.text = text
	f.cursor += len(clean)
}

// view shows the field in width cells. A focused field shows its cursor, and
// a text too long to fit scrolls so the cursor stays visible.
func (f textField) view(width int, focused bool) string {
	runes := f.text
	cursor := f.cursor
	if width > 1 && len(runes)+1 > width {
		start := 0
		if cursor >= width {
			start = cursor - width + 1
		}
		end := min(len(runes), start+width)
		if focused {
			end = min(len(runes), start+width-1)
		}
		runes = runes[start:end]
		cursor -= start
	}
	if !focused {
		return string(runes)
	}
	before := string(runes[:cursor])
	at, after := " ", ""
	if cursor < len(runes) {
		at, after = string(runes[cursor]), string(runes[cursor+1:])
	}
	return before + fieldCursorStyle.Render(at) + after
}

var fieldCursorStyle = lipgloss.NewStyle().Reverse(true)

// handleComposeKey is every key while the compose box is open.
func (m model) handleComposeKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	c := *m.compose
	c.err = ""
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "esc":
		m.compose = nil
		m.setStatus("Cancelled.", false)
		return m, nil
	case "tab", "down":
		c.focus = (c.focus + 1) % focusCount
	case "shift+tab", "up":
		c.focus = (c.focus + focusCount - 1) % focusCount
	case "ctrl+s":
		return m.send(c)
	case "enter":
		if c.focus == focusBody {
			return m.send(c)
		}
		c.focus++
	default:
		switch c.focus {
		case focusType:
			switch msg.String() {
			case "left", "h":
				c.kind = (c.kind + len(messageKinds) - 1) % len(messageKinds)
			case "right", "l", " ":
				c.kind = (c.kind + 1) % len(messageKinds)
			}
		case focusTitle:
			c.title.update(msg)
		case focusBody:
			c.body.update(msg)
		}
	}
	m.compose = &c
	return m, nil
}

// send runs `booth message send` for the composed message, in the background.
// A question keeps running until the booth user answers it; its row is marked
// meanwhile, and the booth's other keys stay usable.
func (m model) send(c compose) (tea.Model, tea.Cmd) {
	title := strings.TrimSpace(c.title.String())
	body := strings.TrimSpace(c.body.String())
	switch {
	case title == "":
		c.err, c.focus = "A message needs a title.", focusTitle
	case body == "":
		c.err, c.focus = "A message needs a body.", focusBody
	}
	if c.err != "" {
		m.compose = &c
		return m, nil
	}
	m.compose = nil

	kind := messageKinds[c.kind]
	key, name := boothKey(c.booth), c.booth.Name
	args := messageArgs(c.booth, kind, title, body)
	if kind.Ask {
		m.asking[key]++
		m.setStatus("Asked "+name+"; the answer will show here.", false)
	} else {
		m.setStatus("", false)
	}
	message, ctx := m.deps.Message, m.ctx
	return m, func() tea.Msg {
		output, err := message(ctx, args)
		return messageDoneMsg{key: key, name: name, kind: kind, output: output, err: err}
	}
}

// messageDone reports a finished `message send`: sent, the user's answer, or
// why it failed.
func (m model) messageDone(msg messageDoneMsg) (tea.Model, tea.Cmd) {
	if msg.kind.Ask {
		if m.asking[msg.key]--; m.asking[msg.key] <= 0 {
			delete(m.asking, msg.key)
		}
	}
	switch {
	case msg.err != nil:
		m.setStatus(failure("send a message to", msg.name, msg.output, msg.err), true)
	case !msg.kind.Ask:
		m.setStatus("Sent "+msg.kind.Label+" to "+msg.name+".", false)
	default:
		answer := lastLine(msg.output)
		switch answer {
		case "timeout":
			m.setStatus(msg.name+": no answer (timed out).", false)
		case "":
			m.setStatus(msg.name+" answered with nothing.", false)
		default:
			m.setStatus(msg.name+" answered: "+answer, false)
		}
	}
	return m, nil
}

func lastLine(output string) string {
	lines := strings.Split(strings.TrimRight(output, "\n"), "\n")
	return strings.TrimSpace(lines[len(lines)-1])
}

// composeView is the compose box, shown below the table.
func (m model) composeView() string {
	c := m.compose
	var b strings.Builder
	b.WriteString(headerStyle.Render(m.fit("Message to "+c.booth.Name)) + "\n")

	const label = 8 // "  Title " and friends
	width := 60
	if m.width > 0 {
		width = max(10, m.width-label-1)
	}
	row := func(focus int, name, value string) {
		marker := "  "
		if c.focus == focus {
			marker = "› "
		}
		b.WriteString(marker + headerStyle.Render(name) + strings.Repeat(" ", label-2-len(name)) + value + "\n")
	}

	kind := messageKinds[c.kind].Label
	if c.focus == focusType {
		kind = "‹ " + cursorStyle.Render(kind) + " ›"
	}
	row(focusType, "Type", kind)
	row(focusTitle, "Title", c.title.view(width, c.focus == focusTitle))
	row(focusBody, "Body", c.body.view(width, c.focus == focusBody))
	return b.String()
}
