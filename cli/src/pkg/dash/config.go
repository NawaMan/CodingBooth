// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"path/filepath"
	"slices"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// ProjectConfig is what c shows about a row's .booth: the selection booth
// config generated it from.
type ProjectConfig struct {
	// Exists: the .booth directory is there.
	Exists bool
	// Generated: its Boothfile or config.toml carries the "# Configured by:"
	// header booth config writes. Without it there is no selection to show.
	Generated bool
	// Items is the select DSL the header records, split into its items: one
	// template with its extensions each (none = no templates).
	Items []string
}

// configPane is what c shows below the table, in the place of i's pane: the
// selected row's project config. It is a few local files, so it loads once
// per row (and again on R), with no ticking.
type configPane struct {
	name     string // the row's name, for the header
	boothDir string
	config   ProjectConfig
	err      error
	loaded   bool
}

// configMsg is a row's project config, read.
type configMsg struct {
	boothDir string
	config   ProjectConfig
	err      error
}

// configBoothDir is the .booth directory of r: the one its booth reads, else
// the one in its folder; "" for a row with no folder.
func configBoothDir(r row) string {
	if r.booth != nil && r.booth.BoothDir != "" {
		return r.booth.BoothDir
	}
	if path := r.path(); path != "" {
		return filepath.Join(path, ".booth")
	}
	return ""
}

func (m model) toggleConfig() (model, tea.Cmd) {
	if m.configOpen {
		m.configOpen, m.config = false, nil
		m.clampOffset()
		return m, nil
	}
	if m.deps.Config == nil {
		return m, nil
	}
	// One pane at a time: c takes i's place.
	m.detailOpen, m.detail = false, nil
	m.configOpen = true
	return m, nil // syncConfig loads it
}

// syncConfig points the open pane at the selected row, loading it when the
// selection moved to another .booth.
func (m model) syncConfig() (model, tea.Cmd) {
	if !m.configOpen {
		return m, nil
	}
	r, ok := m.currentRow()
	dir := ""
	if ok {
		dir = configBoothDir(r)
	}
	if dir == "" {
		m.config = nil
		return m, nil
	}
	if m.config != nil && m.config.boothDir == dir {
		pane := *m.config
		pane.name = configName(r)
		m.config = &pane
		return m, nil
	}
	m.config = &configPane{name: configName(r), boothDir: dir}
	m.clampOffset()
	return m, m.loadConfig()
}

// reloadConfig reads the open pane's config again (R).
func (m model) reloadConfig() (model, tea.Cmd) {
	if m.config == nil {
		return m, nil
	}
	return m, m.loadConfig()
}

func (m model) loadConfig() tea.Cmd {
	read, dir := m.deps.Config, m.config.boothDir
	return func() tea.Msg {
		config, err := read(dir)
		return configMsg{boothDir: dir, config: config, err: err}
	}
}

func (m model) applyConfig(msg configMsg) model {
	if m.config == nil || m.config.boothDir != msg.boothDir {
		return m // the pane moved on, or closed
	}
	pane := *m.config
	pane.config, pane.err, pane.loaded = msg.config, msg.err, true
	m.config = &pane
	m.clampOffset()
	return m
}

// configName names the row in the pane's header as its NAME cell does: its
// booth, else its repository for a main checkout, else its worktree.
func configName(r row) string {
	switch {
	case r.booth != nil:
		return r.booth.Name
	case r.main && r.repo != nil:
		return r.repo.Name
	case r.worktree != nil:
		return r.worktree.Name()
	}
	return "-"
}

func (m model) configShown() bool {
	return m.configOpen && m.config != nil && m.compose == nil
}

func (m model) configLines() int {
	if !m.configShown() {
		return 0
	}
	return 2 + len(m.configBody()) // a blank and the header, then the body
}

// configLabel is the label the select DSL is shown under.
const configLabel = "  Select    "

// configBody is the pane's lines below its header.
func (m model) configBody() []string {
	p := m.config
	switch {
	case !p.loaded:
		return []string{dimStyle.Render("  Reading the config…")}
	case p.err != nil:
		return []string{errorStyle.Render(m.fit("  Could not read the config: " + p.err.Error()))}
	case !p.config.Exists:
		return []string{dimStyle.Render(m.fit("  There is no .booth in this folder; booth config creates one."))}
	case !p.config.Generated:
		return []string{warnStyle.Render(m.fit("  This .booth was not written by booth config, so there is no selection to show."))}
	case len(p.config.Items) == 0:
		return []string{dimStyle.Render(configLabel) + "(no templates selected)"}
	}
	// Alphabetically, to find one at a glance; the DSL's order is the
	// header's to keep, not the pane's.
	items := slices.Clone(p.config.Items)
	slices.SortStableFunc(items, func(a, b string) int {
		return strings.Compare(strings.ToLower(a), strings.ToLower(b))
	})
	more := 0
	if fit := m.configItemsFit(); len(items) > fit {
		// The last line that fits says how many more there are.
		more = len(items) - (fit - 1)
		items = items[:fit-1]
	}
	out := make([]string, 0, len(items)+1)
	for i, item := range items {
		label := dimStyle.Render(configLabel)
		if i > 0 {
			label = strings.Repeat(" ", len(configLabel))
		}
		out = append(out, label+m.fitTo(item, len(configLabel)))
	}
	if more > 0 {
		label := strings.Repeat(" ", len(configLabel))
		if len(out) == 0 {
			label = dimStyle.Render(configLabel)
		}
		out = append(out, label+dimStyle.Render(fmt.Sprintf("… and %d more", more)))
	}
	return out
}

// configItemsFit is how many lines the pane's items may take: what is left
// once the table keeps a few rows (all of them before the first WindowSizeMsg).
func (m model) configItemsFit() int {
	if m.height <= 0 {
		return len(m.config.config.Items)
	}
	keep := max(1, min(len(m.rows), 3))
	return max(1, m.height-chromeLines-len(m.warnings)-2-keep)
}

// configView is the pane.
func (m model) configView() string {
	p := m.config
	var out strings.Builder
	out.WriteString(headerStyle.Render(m.fit(p.name+" · Config · "+m.shortPath(p.boothDir))) + "\n")
	for _, line := range m.configBody() {
		out.WriteString(line + "\n")
	}
	return out.String()
}
