// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// A template whose tool the variant image already holds shows [=]: kept without
// being selected. A removable one cycles [=] → [ ] (saved as ~name) → [x] → [=];
// one that cannot be removed cycles [=] ↔ [x]. The state follows the Config
// tab's Variant field.

func variantModel(variant string) model {
	lsp := &tmpl.Template{Name: "lsp", DisplayName: "LSP", InVariants: []string{"base"}}
	ttt := &tmpl.Template{Name: "ttt", DisplayName: "TTT", CategoryName: "tools",
		InVariants: []string{"base"}, Remove: "run rm -f /usr/local/bin/ttt", Extensions: []*tmpl.Template{lsp}}
	gnupg := &tmpl.Template{Name: "gnupg", DisplayName: "GnuPG", CategoryName: "tools",
		InVariants: []string{"base"}} // in the image, no remove step
	firefox := &tmpl.Template{Name: "firefox", DisplayName: "Firefox", CategoryName: "tools",
		InVariants: []string{"desktop-xfce"}, Remove: "run apt-get purge -y firefox"}
	plain := &tmpl.Template{Name: "htop", DisplayName: "htop", CategoryName: "tools"}
	reg := &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{Name: "tools", Templates: []*tmpl.Template{ttt, gnupg, firefox, plain}}},
		ByName:     map[string]*tmpl.Template{"ttt": ttt, "gnupg": gnupg, "firefox": firefox, "htop": plain},
	}
	items := []treeItem{
		{kind: kindTemplate, template: ttt},
		{kind: kindExtension, template: ttt, extension: lsp},
		{kind: kindTemplate, template: gnupg},
		{kind: kindTemplate, template: firefox},
		{kind: kindTemplate, template: plain},
	}
	return model{
		registry:      reg,
		hostArch:      "amd64",
		selected:      map[string]bool{},
		removed:       map[string]bool{},
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

const (
	rowTTT = iota
	rowLSP
	rowGnupg
	rowFirefox
	rowHtop
)

// row is the plain text of a list row, trimmed.
func row(m model, idx int) string {
	item := m.tabItems[1][idx]
	if item.kind == kindExtension {
		return strings.TrimSpace(stripANSI(m.renderExtensionLine(item, 60, false)))
	}
	return strings.TrimSpace(stripANSI(m.renderTemplateLine(item, 60, false)))
}

// space presses Space on a row, answering yes to any requires prompt.
func space(m *model, idx int) {
	m.setCursor(idx)
	m.toggleSelection()
	if m.confirmRequires != nil {
		next, _ := m.handleRequiresConfirm(keyMsg('y'))
		*m = next.(model)
	}
}

func TestInVariant_DefaultVariantIsBase(t *testing.T) {
	if got := variantModel("").currentVariant(); got != "base" {
		t.Errorf("an empty Variant field should resolve to base, got %q", got)
	}
	if got := variantModel("xfce").currentVariant(); got != "desktop-xfce" {
		t.Errorf("the xfce alias should resolve to desktop-xfce, got %q", got)
	}
	if got := variantModel("no-such").currentVariant(); got != "" {
		t.Errorf("an unknown variant should resolve to nothing, got %q", got)
	}
}

func TestInVariant_CheckboxShowsEquals(t *testing.T) {
	m := variantModel("")
	for idx, want := range map[int]string{
		rowTTT:   "[=] ttt",
		rowLSP:   "[=] lsp",
		rowGnupg: "[=] gnupg",
		rowHtop:  "[ ] htop",
	} {
		if got := row(m, idx); !strings.HasPrefix(got, want) {
			t.Errorf("row %d = %q, want prefix %q", idx, got, want)
		}
	}
}

func TestInVariant_FollowsVariantField(t *testing.T) {
	m := variantModel("")
	if got := row(m, rowFirefox); !strings.HasPrefix(got, "[ ] firefox") {
		t.Errorf("firefox is not in base, got %q", got)
	}
	m.stringFields["variant"] = "desktop-xfce"
	if got := row(m, rowFirefox); !strings.HasPrefix(got, "[=] firefox") {
		t.Errorf("on desktop-xfce firefox is in the image, got %q", got)
	}
}

func TestInVariant_ArchWarningKeepsItsSlot(t *testing.T) {
	m := variantModel("")
	m.tabItems[1][rowTTT].template.UnsupportedArch = []string{"amd64"}
	if got := row(m, rowTTT); !strings.HasPrefix(got, "[=] !ttt") {
		t.Errorf("got %q, want [=] with the ! marker", got)
	}
}

func TestInVariant_RemovableCyclesThroughRemoved(t *testing.T) {
	m := variantModel("")

	space(&m, rowTTT)
	if got := row(m, rowTTT); !strings.HasPrefix(got, "[ ] ttt") {
		t.Fatalf("first Space should remove ttt, got %q", got)
	}
	if got := m.buildSelectDSL(); got != "~ttt" {
		t.Errorf("DSL = %q, want ~ttt", got)
	}
	if got := row(m, rowLSP); !strings.HasPrefix(got, "[ ] lsp") {
		t.Errorf("ttt+lsp goes with its removed parent, got %q", got)
	}
	if !strings.Contains(m.notification, "~ttt") {
		t.Errorf("notification should name ~ttt, got %q", m.notification)
	}

	space(&m, rowTTT)
	if got := row(m, rowTTT); !strings.HasPrefix(got, "[x] ttt") {
		t.Fatalf("second Space should select ttt, got %q", got)
	}
	if got := m.buildSelectDSL(); strings.Contains(got, "~") {
		t.Errorf("a selected template is not removed, DSL = %q", got)
	}

	space(&m, rowTTT)
	if got := row(m, rowTTT); !strings.HasPrefix(got, "[=] ttt") {
		t.Fatalf("third Space should return ttt to [=], got %q", got)
	}
	if got := m.buildSelectDSL(); got != "" {
		t.Errorf("back at [=] the DSL is empty, got %q", got)
	}
}

func TestInVariant_NotRemovableSkipsRemoved(t *testing.T) {
	m := variantModel("")
	space(&m, rowGnupg)
	if got := row(m, rowGnupg); !strings.HasPrefix(got, "[x] gnupg") {
		t.Fatalf("gnupg has no remove step, so Space selects it, got %q", got)
	}
	space(&m, rowGnupg)
	if got := row(m, rowGnupg); !strings.HasPrefix(got, "[=] gnupg") {
		t.Errorf("and Space again returns it to [=], got %q", got)
	}
}

func TestInVariant_RemovalDroppedWhenVariantLacksIt(t *testing.T) {
	m := variantModel("desktop-xfce")
	space(&m, rowFirefox)
	if got := m.buildSelectDSL(); got != "~firefox" {
		t.Fatalf("DSL = %q, want ~firefox", got)
	}
	m.stringFields["variant"] = ""
	if got := m.buildSelectDSL(); got != "" {
		t.Errorf("base has no Firefox, so the removal is dropped, DSL = %q", got)
	}
}

func TestInVariant_RemovalIsAnUnsavedChange(t *testing.T) {
	m := variantModel("")
	m.baseline = m.snapshot()
	space(&m, rowTTT)
	if !m.hasUnsavedChanges() {
		t.Error("removing ttt is a change to save")
	}
}

func TestInVariant_PreSelectionRemoved(t *testing.T) {
	base := variantModel("")
	m := newModel(base.registry, &PreSelection{Removed: map[string]bool{"ttt": true}})
	if got := m.buildSelectDSL(); got != "~ttt" {
		t.Errorf("a ~ttt header should reopen removed, DSL = %q", got)
	}
}

func TestInVariant_RecipeAppliesAndMatchesRemoval(t *testing.T) {
	m := variantModel("")
	parsed, err := selection.ParseSelectDSL("~ttt")
	if err != nil {
		t.Fatal(err)
	}
	m.applyRecipeItem(parsed.Items[0])
	if got := m.buildSelectDSL(); got != "~ttt" {
		t.Errorf("DSL = %q, want ~ttt", got)
	}
	if !m.recipeItemMatches(parsed.Items[0]) {
		t.Error("the applied removal should match its recipe item")
	}
}

func TestInVariant_DetailPanelSaysWhatSpaceDoes(t *testing.T) {
	m := variantModel("")
	detail := func(name string) string {
		lines, _, _ := m.renderTemplateDetail(m.registry.ByName[name], 60)
		return stripANSI(strings.Join(lines, "\n"))
	}
	if out := detail("ttt"); !strings.Contains(out, "Already in the base image") || !strings.Contains(out, "Space removes it") {
		t.Errorf("ttt's panel should say it is in the image and removable:\n%s", out)
	}
	if out := detail("gnupg"); !strings.Contains(out, "cannot be removed") {
		t.Errorf("gnupg's panel should say it cannot be removed:\n%s", out)
	}
	space(&m, rowTTT)
	if out := detail("ttt"); !strings.Contains(out, "Removed from the base image") {
		t.Errorf("after removing, ttt's panel should say so:\n%s", out)
	}
	if out := detail("htop"); strings.Contains(out, "image") {
		t.Errorf("htop's panel should not mention the image:\n%s", out)
	}
}

func TestInVariant_SelectSaysSo(t *testing.T) {
	m := variantModel("")
	m.applySelectItem(m.tabItems[1][rowTTT])
	if !strings.Contains(m.notification, "ttt is already in the base image") {
		t.Errorf("selecting ttt should say it is already in the image, got %q", m.notification)
	}
	m = variantModel("")
	m.applySelectItem(m.tabItems[1][rowHtop])
	if strings.Contains(m.notification, "already in") {
		t.Errorf("selecting htop should not say it is in the image, got %q", m.notification)
	}
}
