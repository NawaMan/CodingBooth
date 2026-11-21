// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// namePrompt asks, on the status line, for a name: a new worktree's (n), or
// the one a separator gives the rows below it (enter on the separator).
type namePrompt struct {
	repo *lifecycle.Repo
	// sep, when set, is the separator being named; repo is nil then.
	sep   string
	field textField
	err   string
}

// promptHelp is the help lines while the prompt is open.
func (m model) promptHelp() []string {
	if m.prompt != nil && m.prompt.sep != "" {
		return []string{
			"the name heads the rows below the line, down to the next line",
			"enter save it (no name: a plain line) · ctrl+u clear · esc cancel",
		}
	}
	return []string{
		"the name is the new branch; it starts at the repository's current commit",
		"enter create it and start its booth · esc cancel",
	}
}

func (m model) handlePromptKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	p := *m.prompt
	p.err = ""
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "esc":
		m.prompt = nil
		m.setStatus("Cancelled.", false)
		return m, nil
	case "enter":
		name := strings.TrimSpace(p.field.String())
		if p.sep != "" {
			m.prompt = nil
			return m.nameSeparator(p.sep, name)
		}
		switch {
		case name == "":
			p.err = "A worktree needs a name."
		case strings.ContainsAny(name, " \t"):
			p.err = "A branch name has no spaces."
		case strings.HasPrefix(name, "-"):
			p.err = "A branch name does not start with -."
		}
		if p.err != "" {
			m.prompt = &p
			return m, nil
		}
		m.prompt = nil
		return m.execute("new:"+p.repo.Root+":"+name, name, newWorktreePlan(p.repo, name))
	default:
		p.field.update(msg)
	}
	m.prompt = &p
	return m, nil
}

// promptLine is the prompt, in the status line's place.
func (m model) promptLine() string {
	p := m.prompt
	label := "Name of the rows below this line: "
	if p.sep == "" {
		label = "New worktree in " + p.repo.Name + ": "
	}
	line := confirmStyle.Render(label) + p.field.view(max(10, m.width-len(label)-1), true)
	if p.err != "" {
		line += "  " + errorStyle.Render(p.err)
	}
	return line
}

// openIn opens path in the user's editor (e) or in GitKraken (K).
func (m model) openIn(key, path string) (tea.Model, tea.Cmd) {
	if key == keyEditor {
		if m.deps.Editor == nil {
			return m, nil
		}
		cmd, err := m.deps.Editor(path)
		if err != nil {
			m.setStatus(err.Error(), true)
			return m, nil
		}
		m.setStatus("", false)
		p := plan{Verb: "open an editor on", Interactive: true}
		return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
			return execDoneMsg{name: path, plan: p, err: err}
		})
	}
	if m.deps.GitKraken == nil {
		return m, nil
	}
	m.setStatus("", false)
	open := m.deps.GitKraken
	p := plan{Verb: "open GitKraken on", Done: "Opened " + m.shortPath(path) + " in GitKraken."}
	return m, func() tea.Msg { return openDoneMsg{name: path, plan: p, err: open(path)} }
}
