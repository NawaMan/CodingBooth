// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	tea "github.com/charmbracelet/bubbletea"
)

// Hiding (h) takes a row out of the table; H shows the hidden rows instead,
// where h brings one back. A row is hidden by its key: a booth row hides that
// booth, a worktree row with no booth hides that worktree (a booth started on
// it later shows). The keys are kept by Deps.Hide, so they stay hidden the
// next time the dashboard opens.

// layout lays out the table from the booths and repositories: the rows not
// hidden, or under H only the hidden ones. The cursor stays on its row.
func (m *model) layout() {
	all := buildRows(m.booths, m.repos)
	m.hiddenRows = 0
	rows := all[:0:0]
	for _, r := range all {
		hidden := m.hidden[r.key()]
		if hidden {
			m.hiddenRows++
		}
		if hidden == m.showHidden {
			rows = append(rows, r)
		}
	}
	m.rows = rows
	m.reselect()
}

// rowName is how the status line names a row.
func rowName(r row) string {
	if r.booth != nil {
		return r.booth.Name
	}
	if r.worktree != nil {
		return r.worktree.Name()
	}
	return ""
}

// toggleHide hides the selected row, or under H shows it again. The file is
// written here, before any later snapshot starts, so none reads it old.
func (m model) toggleHide() (tea.Model, tea.Cmd) {
	if m.deps.Hide == nil {
		return m, nil
	}
	r, ok := m.currentRow()
	if !ok {
		return m, nil
	}
	key, name, hide := r.key(), rowName(r), !m.showHidden
	if err := m.deps.Hide(key, r.path(), hide); err != nil {
		verb := "hide"
		if !hide {
			verb = "unhide"
		}
		m.setStatus("Could not "+verb+" "+name+": "+err.Error(), true)
		return m, nil
	}
	hidden := make(map[string]bool, len(m.hidden)+1)
	for k, v := range m.hidden {
		hidden[k] = v
	}
	if hide {
		hidden[key] = true
	} else {
		delete(hidden, key)
	}
	m.hidden = hidden
	m.hiddenGen++
	m.layout()
	if hide {
		m.setStatus("Hid "+name+". H shows the hidden rows.", false)
	} else {
		m.setStatus("Unhid "+name+".", false)
	}
	return m, nil
}

// toggleHiddenView switches the table between the rows shown and the rows
// hidden.
func (m model) toggleHiddenView() (tea.Model, tea.Cmd) {
	if m.deps.Hide == nil {
		return m, nil
	}
	m.showHidden = !m.showHidden
	m.layout()
	m.setStatus("", false)
	return m, nil
}
