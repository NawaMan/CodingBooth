// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// A template whose tool the variant image already holds is marked "=" in the
// list, explained in the detail panel, and named in the message on select. The
// mark follows the Config tab's Variant field.

func variantModel(variant string) model {
	lsp := &tmpl.Template{Name: "lsp", DisplayName: "LSP", InVariants: []string{"base"}}
	ttt := &tmpl.Template{Name: "ttt", DisplayName: "TTT", CategoryName: "tools",
		InVariants: []string{"base"}, Extensions: []*tmpl.Template{lsp}}
	firefox := &tmpl.Template{Name: "firefox", DisplayName: "Firefox", CategoryName: "tools",
		InVariants: []string{"desktop-xfce"}}
	plain := &tmpl.Template{Name: "htop", DisplayName: "htop", CategoryName: "tools"}
	reg := &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{Name: "tools", Templates: []*tmpl.Template{ttt, firefox, plain}}},
		ByName:     map[string]*tmpl.Template{"ttt": ttt, "firefox": firefox, "htop": plain},
	}
	items := []treeItem{
		{kind: kindTemplate, template: ttt},
		{kind: kindExtension, template: ttt, extension: lsp},
		{kind: kindTemplate, template: firefox},
		{kind: kindTemplate, template: plain},
	}
	return model{
		registry:      reg,
		hostArch:      "amd64",
		selected:      map[string]bool{},
		paramValues:   map[string]string{},
		stringFields:  map[string]string{"variant": variant},
		tabNames:      []string{"Config", "Tools"},
		tabItems:      [][]treeItem{nil, items},
		activeTab:     1,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		width:         100,
		height:        40,
	}
}

// rowPrefix is a row's plain text up to the name, where the marker sits.
func rowPrefix(line string) string {
	plain := stripANSI(line)
	return strings.TrimRight(plain[:min(len(plain), 14)], " ")
}

func TestInVariant_DefaultVariantIsBase(t *testing.T) {
	m := variantModel("")
	if got := m.currentVariant(); got != "base" {
		t.Errorf("an empty Variant field should resolve to base, got %q", got)
	}
	if got := variantModel("xfce").currentVariant(); got != "desktop-xfce" {
		t.Errorf("the xfce alias should resolve to desktop-xfce, got %q", got)
	}
	if got := variantModel("no-such").currentVariant(); got != "" {
		t.Errorf("an unknown variant should resolve to nothing, got %q", got)
	}
}

func TestInVariant_ListMarksTemplateInImage(t *testing.T) {
	m := variantModel("")
	if got := rowPrefix(m.renderTemplateLine(m.tabItems[1][0], 60, false)); !strings.HasPrefix(got, "[ ] =ttt") {
		t.Errorf("ttt is in base and should be marked, got %q", got)
	}
	if got := rowPrefix(m.renderTemplateLine(m.tabItems[1][3], 60, false)); !strings.HasPrefix(got, "[ ] htop") {
		t.Errorf("htop is in no image and should be unmarked, got %q", got)
	}
}

func TestInVariant_ListMarksExtensionInImage(t *testing.T) {
	m := variantModel("")
	if got := stripANSI(m.renderExtensionLine(m.tabItems[1][1], 60, false)); !strings.HasPrefix(got, "    [ ] =lsp") {
		t.Errorf("ttt+lsp is in base and should be marked, got %q", got)
	}
}

func TestInVariant_MarkFollowsVariantField(t *testing.T) {
	firefox := func(m model) string { return rowPrefix(m.renderTemplateLine(m.tabItems[1][2], 60, false)) }

	if got := firefox(variantModel("")); strings.Contains(got, "=") {
		t.Errorf("firefox is not in base, got %q", got)
	}
	m := variantModel("")
	m.stringFields["variant"] = "desktop-xfce"
	if got := firefox(m); !strings.HasPrefix(got, "[ ] =firefox") {
		t.Errorf("after switching to desktop-xfce, firefox should be marked, got %q", got)
	}
}

func TestInVariant_ArchWarningWinsTheSlot(t *testing.T) {
	m := variantModel("")
	m.tabItems[1][0].template.UnsupportedArch = []string{"amd64"}
	if got := rowPrefix(m.renderTemplateLine(m.tabItems[1][0], 60, false)); !strings.HasPrefix(got, "[ ] !ttt") {
		t.Errorf("the arch warning should take the marker slot, got %q", got)
	}
}

func TestInVariant_DetailPanelExplains(t *testing.T) {
	m := variantModel("")
	lines, _, _ := m.renderTemplateDetail(m.registry.ByName["ttt"], 60)
	if out := stripANSI(strings.Join(lines, "\n")); !strings.Contains(out, "Already in the base image") {
		t.Errorf("ttt's detail panel should say it is in the base image:\n%s", out)
	}
	lines, _, _ = m.renderTemplateDetail(m.registry.ByName["htop"], 60)
	if out := stripANSI(strings.Join(lines, "\n")); strings.Contains(out, "Already in") {
		t.Errorf("htop's detail panel should not claim it is in the image:\n%s", out)
	}
}

func TestInVariant_SelectSaysSo(t *testing.T) {
	m := variantModel("")
	m.applySelectItem(m.tabItems[1][0])
	if !strings.Contains(m.notification, "ttt is already in the base image") {
		t.Errorf("selecting ttt should say it is already in the image, got %q", m.notification)
	}

	m = variantModel("")
	m.applySelectItem(m.tabItems[1][3])
	if strings.Contains(m.notification, "already in") {
		t.Errorf("selecting htop should not say it is in the image, got %q", m.notification)
	}
}
