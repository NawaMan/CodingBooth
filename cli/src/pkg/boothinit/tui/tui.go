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
	Confirmed    bool
	SelectDSL    string
	StringFields map[string]string   // all string/cycle field values
	BoolFields   map[string]bool     // all bool field values
	ListFields   map[string][]string // all list field values (expose, env, mount)

	// SaveBeside is set when the user kept their hand-written files and asked for
	// the generated content to land alongside as "<name>.new", to merge by hand.
	// Only ever set when the booth had hand-written files to begin with.
	SaveBeside bool
}

// PreSelection holds values pre-populated from CLI flags.
type PreSelection struct {
	SelectedTemplates map[string]bool            // template names
	SelectedExts      map[string]map[string]bool // template name → extension names
	StringFields      map[string]string          // pre-set string values (variant, port, name, etc.)
	BoolFields        map[string]bool            // pre-set bool values (dind, keep-alive, etc.)
	ListFields        map[string][]string        // pre-set list values (expose, env, mount)
	ParamValues       map[string]string          // "tmplName:PARAM" or "tmplName/extName:PARAM" → value
}

// RunConfig launches the interactive TUI and returns the user's configuration choices.
// If warning is non-empty, it is shown as a dismissable dialog before the TUI starts.
//
// drifted names the .booth/ files holding hand-written content (see output.Drifted).
// Saving regenerates those files from scratch, destroying that content, so when the
// list is non-empty Ctrl+S opens a dialog rather than saving: the safe default writes
// the generated content beside them (ConfigResult.SaveBeside), and replacing them
// outright requires typing the confirmation word.
func RunConfig(registry *tmpl.TemplateRegistry, pre *PreSelection, warning string, drifted []string) (*ConfigResult, error) {
	m := newModel(registry, pre)
	m.drifted = drifted
	if warning != "" {
		m.warningDialog = true
		m.warningMessage = warning
	}

	// Mouse cell motion is the lightest reporting mode that still delivers clicks
	// and the wheel; motion events are ignored. Enabling it hands the mouse to the
	// TUI, so a terminal's own click-drag text selection needs Shift while this is
	// up — which is what the footer and BOOTH_CONFIG_TUI.md say.
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())
	result, err := p.Run()
	if err != nil {
		return nil, fmt.Errorf("TUI error: %w", err)
	}

	final := result.(model)
	if !final.confirmed {
		return &ConfigResult{Confirmed: false}, nil
	}

	return &ConfigResult{
		Confirmed:    true,
		SelectDSL:    final.buildSelectDSL(),
		StringFields: final.stringFields,
		BoolFields:   final.boolFields,
		ListFields:   final.listFields,
		SaveBeside:   final.saveBeside,
	}, nil
}
