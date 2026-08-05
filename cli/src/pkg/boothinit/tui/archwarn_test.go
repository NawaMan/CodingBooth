// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// A template with no build on this architecture is still selectable — the booth
// builds, the setup warns and skips — so the TUI's job is to make sure nobody
// ticks the box without knowing the tool will be missing. Three places carry
// that: the list marker, the detail panel, and the notification on select.

const testArch = "arm64"

func archRegistry() *tmpl.TemplateRegistry {
	chrome := &tmpl.Template{
		Name:                "google-chrome",
		DisplayName:         "Google Chrome",
		CategoryName:        "browsers",
		DisplayDesc:         "Google Chrome browser",
		UnsupportedArch:     []string{testArch},
		UnsupportedArchNote: "No linux/arm64 build. Use chromium, or Chrome on your Mac.",
	}
	chromium := &tmpl.Template{
		Name:         "chromium",
		DisplayName:  "Chromium",
		CategoryName: "browsers",
		DisplayDesc:  "Chromium browser",
	}
	return &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{
			Name:      "browsers",
			Templates: []*tmpl.Template{chrome, chromium},
		}},
		ByName: map[string]*tmpl.Template{"google-chrome": chrome, "chromium": chromium},
	}
}

func archModel(hostArch string) model {
	reg := archRegistry()
	items := []treeItem{
		{kind: kindTemplate, template: reg.ByName["google-chrome"]},
		{kind: kindTemplate, template: reg.ByName["chromium"]},
	}
	return model{
		registry:      reg,
		hostArch:      hostArch,
		selected:      map[string]bool{},
		paramValues:   map[string]string{},
		tabNames:      []string{"Config", "Browsers"},
		tabItems:      [][]treeItem{nil, items},
		activeTab:     1,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		width:         100,
		height:        40,
	}
}

// --- detail panel ---

func TestArchWarning_DetailShowsNoteOnAffectedArch(t *testing.T) {
	m := archModel(testArch)
	out := strings.Join(m.renderArchWarning(m.registry.ByName["google-chrome"], 60), "\n")

	for _, want := range []string{"Not available on arm64", "Use chromium", "Chrome on your Mac"} {
		if !strings.Contains(out, want) {
			t.Errorf("detail warning missing %q\ngot:\n%s", want, out)
		}
	}
}

func TestArchWarning_DetailSilentOnSupportedArch(t *testing.T) {
	m := archModel("amd64")
	if got := m.renderArchWarning(m.registry.ByName["google-chrome"], 60); got != nil {
		t.Errorf("expected no warning on amd64, got %q", got)
	}
}

func TestArchWarning_DetailSilentForUnaffectedTemplate(t *testing.T) {
	m := archModel(testArch)
	if got := m.renderArchWarning(m.registry.ByName["chromium"], 60); got != nil {
		t.Errorf("expected no warning for chromium, got %q", got)
	}
}

func TestArchWarning_TemplateDetailIncludesWarningBeforeDescription(t *testing.T) {
	m := archModel(testArch)
	lines, _, _ := m.renderTemplateDetail(m.registry.ByName["google-chrome"], 60)
	out := strings.Join(lines, "\n")

	warnAt := strings.Index(out, "Not available on")
	descAt := strings.Index(out, "Google Chrome browser")
	if warnAt < 0 {
		t.Fatalf("detail pane has no arch warning:\n%s", out)
	}
	if descAt >= 0 && warnAt > descAt {
		t.Errorf("warning should come before the description\ngot:\n%s", out)
	}
}

// --- list marker ---

func TestArchWarning_ListMarksAffectedTemplate(t *testing.T) {
	m := archModel(testArch)
	line := m.renderTemplateLine(m.tabItems[1][0], 60, false)
	if !strings.Contains(line, "!") {
		t.Errorf("google-chrome row should carry the ! marker, got %q", line)
	}
}

func TestArchWarning_ListLeavesOtherTemplatesUnmarked(t *testing.T) {
	m := archModel(testArch)
	line := m.renderTemplateLine(m.tabItems[1][1], 60, false)
	if strings.Contains(line, "!") {
		t.Errorf("chromium row should carry no marker, got %q", line)
	}
}

// The marker occupies a fixed-width ASCII slot so every row still lines up.
func TestArchWarning_ListRowsStayAligned(t *testing.T) {
	m := archModel(testArch)
	marked := m.renderTemplateLine(m.tabItems[1][0], 60, false)
	plain := m.renderTemplateLine(m.tabItems[1][1], 60, false)
	if len(marked) != len(plain) {
		t.Errorf("rows must be equal width: marked=%d plain=%d\n%q\n%q",
			len(marked), len(plain), marked, plain)
	}
}

// --- selection notification ---

func TestArchWarning_SelectingAffectedTemplateNotifies(t *testing.T) {
	m := archModel(testArch)
	m.tabCursors[1] = 0 // google-chrome
	m.toggleSelection()

	if !m.selected["google-chrome"] {
		t.Fatal("template should still be selectable — the warning informs, it does not block")
	}
	if !strings.Contains(m.notification, "google-chrome") ||
		!strings.Contains(m.notification, "NOT be installed") {
		t.Errorf("expected an arch warning notification, got %q", m.notification)
	}
}

func TestArchWarning_SelectingSupportedTemplateIsQuiet(t *testing.T) {
	m := archModel(testArch)
	m.tabCursors[1] = 1 // chromium
	m.toggleSelection()

	if strings.Contains(m.notification, "NOT be installed") {
		t.Errorf("chromium should not warn, got %q", m.notification)
	}
}

func TestArchWarning_SelectingOnSupportedArchIsQuiet(t *testing.T) {
	m := archModel("amd64")
	m.tabCursors[1] = 0 // google-chrome, but on amd64 where it installs fine
	m.toggleSelection()

	if strings.Contains(m.notification, "NOT be installed") {
		t.Errorf("no warning expected on amd64, got %q", m.notification)
	}
}
