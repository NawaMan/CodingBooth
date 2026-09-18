// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/charmbracelet/lipgloss"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// Regression coverage for two bugs found in the same list-row rendering code:
//
//  1. renderTemplateLine/renderExtensionLine measured a description's length
//     with len() (bytes) instead of display width, so a description holding a
//     multi-byte rune (an em dash, an ellipsis, a curly quote) came up short by
//     the byte/column difference and the right-panel divider shifted left for
//     that row only — first noticed on the flutter template's own description
//     ("...codebase — brings...").
//  2. A template row reserved a fixed 2-column slot after "[ ]" even with no
//     arch warning to show, so the name sat 3 spaces from the checkbox instead
//     of 1 — the same gap an extension row (or the "*" auto-select marker)
//     already used.

func lineWidthRegistry() *tmpl.TemplateRegistry {
	plain := &tmpl.Template{
		Name:         "plain",
		DisplayName:  "Plain",
		CategoryName: "widgets",
		DisplayDesc:  "An ordinary all-ASCII description",
	}
	wideRune := &tmpl.Template{
		Name:         "widerune",
		DisplayName:  "WideRune",
		CategoryName: "widgets",
		// An em dash (—) and ellipsis (…): each is one display column but two
		// or three UTF-8 bytes, exactly the mismatch len() got wrong.
		DisplayDesc: "Builds apps from one codebase — supports smart quotes… really",
	}
	extPlain := &tmpl.Template{
		Name:        "ext-plain",
		DisplayName: "ExtPlain",
		DisplayDesc: "An ordinary extension description",
	}
	extWideRune := &tmpl.Template{
		Name:        "ext-widerune",
		DisplayName: "ExtWideRune",
		DisplayDesc: "Generates code — including gRPC services",
	}
	plain.Extensions = []*tmpl.Template{extPlain, extWideRune}
	wideRune.Extensions = []*tmpl.Template{extPlain, extWideRune}

	return &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{
			Name:      "widgets",
			Templates: []*tmpl.Template{plain, wideRune},
		}},
		ByName: map[string]*tmpl.Template{
			"plain":    plain,
			"widerune": wideRune,
		},
	}
}

func lineWidthModel() model {
	reg := lineWidthRegistry()
	return model{
		registry:      reg,
		hostArch:      "amd64",
		selected:      map[string]bool{},
		paramValues:   map[string]string{},
		tabNames:      []string{"Config", "Widgets"},
		tabItems:      [][]treeItem{nil},
		activeTab:     1,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		width:         100,
		height:        40,
	}
}

// Every rendered row must occupy exactly the same number of display columns
// (not bytes) up to where the caller appends the " │ " divider, regardless of
// what punctuation the description holds — otherwise the divider visibly
// zig-zags from row to row.
func TestTemplateLine_WideRuneDescriptionStaysAligned(t *testing.T) {
	m := lineWidthModel()
	const width = 60

	plainLine := m.renderTemplateLine(treeItem{kind: kindTemplate, template: m.registry.ByName["plain"]}, width, false)
	wideLine := m.renderTemplateLine(treeItem{kind: kindTemplate, template: m.registry.ByName["widerune"]}, width, false)

	if got := lipgloss.Width(plainLine); got != width {
		t.Errorf("plain-description row: want %d display columns, got %d\nline=%q", width, got, plainLine)
	}
	if got := lipgloss.Width(wideLine); got != width {
		t.Errorf("wide-rune-description row: want %d display columns, got %d\nline=%q", width, got, wideLine)
	}
}

func TestExtensionLine_WideRuneDescriptionStaysAligned(t *testing.T) {
	m := lineWidthModel()
	const width = 60
	parent := m.registry.ByName["plain"]

	plainLine := m.renderExtensionLine(treeItem{kind: kindExtension, template: parent, extension: parent.Extensions[0]}, width, false)
	wideLine := m.renderExtensionLine(treeItem{kind: kindExtension, template: parent, extension: parent.Extensions[1]}, width, false)

	if got := lipgloss.Width(plainLine); got != width {
		t.Errorf("plain-description extension row: want %d display columns, got %d\nline=%q", width, got, plainLine)
	}
	if got := lipgloss.Width(wideLine); got != width {
		t.Errorf("wide-rune-description extension row: want %d display columns, got %d\nline=%q", width, got, wideLine)
	}
}

// A truncated wide-rune description must still cut on a rune boundary, never
// splitting a multi-byte character into an invalid partial one.
func TestTemplateLine_WideRuneDescriptionTruncatesOnRuneBoundary(t *testing.T) {
	m := lineWidthModel()
	// Narrow enough that "widerune"'s description must be cut.
	line := m.renderTemplateLine(treeItem{kind: kindTemplate, template: m.registry.ByName["widerune"]}, 40, false)
	if !utf8.ValidString(line) {
		t.Errorf("truncated line is not valid UTF-8: %q", line)
	}
}

// A plain template row (no arch warning) puts exactly one space between the
// checkbox and the name — the same gap an extension row already used for its
// own name (or "*name" when auto-selected).
func TestTemplateLine_OneSpaceGapAfterCheckbox(t *testing.T) {
	m := lineWidthModel()
	line := m.renderTemplateLine(treeItem{kind: kindTemplate, template: m.registry.ByName["plain"]}, 60, false)

	const want = "[ ] plain"
	if !strings.HasPrefix(stripANSI(line), want) {
		t.Errorf("want line to start with %q, got %q", want, stripANSI(line))
	}
}

func TestExtensionLine_OneSpaceGapAfterCheckbox(t *testing.T) {
	m := lineWidthModel()
	parent := m.registry.ByName["plain"]
	line := m.renderExtensionLine(treeItem{kind: kindExtension, template: parent, extension: parent.Extensions[0]}, 60, false)

	const want = "    [ ] ext-plain"
	if !strings.HasPrefix(stripANSI(line), want) {
		t.Errorf("want line to start with %q, got %q", want, stripANSI(line))
	}
}
