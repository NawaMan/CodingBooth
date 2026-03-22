// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package tui provides an interactive terminal UI for browsing and selecting
// booth templates and configuration options.
package tui

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// ConfigResult holds the user's selections from the TUI.
type ConfigResult struct {
	Confirmed bool // true if user pressed Ctrl+S, false if quit
	SelectDSL string
	Variant   string
	Port      string
}

// PreSelection holds values pre-populated from CLI flags.
type PreSelection struct {
	SelectedTemplates map[string]bool            // template names
	SelectedExts      map[string]map[string]bool // template name → extension names
	Variant           string
	Port              string
}

// RunConfig launches the interactive TUI and returns the user's configuration choices.
func RunConfig(registry *tmpl.TemplateRegistry, pre *PreSelection) (*ConfigResult, error) {
	m := newModel(registry, pre)

	p := tea.NewProgram(m, tea.WithAltScreen())
	result, err := p.Run()
	if err != nil {
		return nil, fmt.Errorf("TUI error: %w", err)
	}

	final := result.(model)
	if !final.confirmed {
		return &ConfigResult{Confirmed: false}, nil
	}

	return &ConfigResult{
		Confirmed: true,
		SelectDSL: final.buildSelectDSL(),
		Variant:   final.variant,
		Port:      final.port,
	}, nil
}
