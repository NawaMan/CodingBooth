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

	// NoBackup is set when the user chose to overwrite hand-written files outright,
	// without the <name>.bak copy the plain "apply" choice keeps.
	NoBackup bool

	// Review is set when the user cancelled on the edits-made-outside question
	// to review the files before going on. Nothing was saved (Confirmed is false).
	Review bool
}

// SaveGuard is what the TUI must know about the booth's existing files before a
// save regenerates them.
type SaveGuard struct {
	// Drifted names the .booth/ files holding hand-written content
	// (see output.Drifted) that could not be read back.
	Drifted []string

	// AdoptReasons says why the edits in Drifted could not be read back into
	// the selection. Empty when that was never tried — a file with no
	// "# Configured by:" header was written by hand from the start.
	AdoptReasons []string

	// LostComments lists comments a save would remove from files whose hand
	// edits were read back ("<file>:<line>  <text>").
	LostComments []string

	// Adopted lists the files edited outside booth config whose edits were read
	// back; AdoptedChanges says what they became, as flags (empty when only the
	// fingerprint disagrees). The TUI asks on open: OK accepts them and carries
	// on — calling RefreshFingerprint when set — while Cancel quits with nothing
	// changed (ConfigResult.Review), for the user to look at the files first.
	Adopted        []string
	AdoptedChanges []string
	// AdoptedModified maps each file in Adopted to when it was last modified,
	// already formatted for display.
	AdoptedModified    map[string]string
	RefreshFingerprint func() error
}

// PreSelection holds values pre-populated from CLI flags.
type PreSelection struct {
	SelectedTemplates map[string]bool            // template names
	SelectedExts      map[string]map[string]bool // template name → extension names
	StringFields      map[string]string          // pre-set string values (variant, port, name, etc.)
	BoolFields        map[string]bool            // pre-set bool values (dind, keep-alive, etc.)
	ListFields        map[string][]string        // pre-set list values (expose, env, mount)
	ParamValues       map[string]string          // "tmplName:PARAM" or "tmplName/extName:PARAM" → value

	// ImageAptSnapshot names the image a booth with these settings builds FROM
	// and the apt snapshot it was built at ("" when unknown — not on this
	// machine, or not a catalog image). settings are the Config tab's values,
	// so the answer follows a variant change. Nil: the panel shows nothing.
	ImageAptSnapshot func(settings map[string]string) (ref, snapshot string)
}

// RunConfig launches the interactive TUI and returns the user's configuration choices.
// If warning is non-empty, it is shown as a dismissable dialog before the TUI starts.
//
// guard describes the booth's existing files. Saving regenerates the files in
// guard.Drifted from scratch, destroying their hand-written content, so when the
// list is non-empty Ctrl+S opens a dialog rather than saving. It offers three
// choices: apply and keep a <name>.bak (the default), write the generated content
// beside them as <name>.new (ConfigResult.SaveBeside), or overwrite outright with
// no backup (ConfigResult.NoBackup), which requires typing the confirmation word.
//
// When guard.LostComments is non-empty, Ctrl+S shows them and waits for Enter
// before saving. When guard.Adopted is non-empty, the TUI opens on a question:
// accept the edits made outside booth config (OK) or quit to review them (Cancel).
//
// binaryVersion and buildDate identify the running codingbooth binary (main.version /
// main.buildDate) and are shown in the header — purely so a rebuilt-but-unbumped dev
// binary is distinguishable from whatever a project's wrapper/cache already resolved.
func RunConfig(registry *tmpl.TemplateRegistry, pre *PreSelection, warning string, guard SaveGuard, binaryVersion, buildDate string) (*ConfigResult, error) {
	m := newModel(registry, pre)
	m.drifted = guard.Drifted
	m.adoptReasons = guard.AdoptReasons
	m.lostComments = guard.LostComments
	m.adoptedFiles = guard.Adopted
	m.adoptedChanges = guard.AdoptedChanges
	m.adoptedModified = guard.AdoptedModified
	m.refreshFingerprint = guard.RefreshFingerprint
	m.adoptedDialog = len(guard.Adopted) > 0
	m.binaryVersion = binaryVersion
	m.buildDate = buildDate
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
		return &ConfigResult{Confirmed: false, Review: final.review}, nil
	}

	return &ConfigResult{
		Confirmed:    true,
		SelectDSL:    final.buildSelectDSL(),
		StringFields: final.stringFields,
		BoolFields:   final.boolFields,
		ListFields:   final.listFields,
		SaveBeside:   final.saveBeside,
		NoBackup:     final.noBackup,
	}, nil
}
