// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// The "dind" tool template (and extensions like aws-sam-cli's "dind for sam
// local") set dind = true as a config default the moment they're selected,
// with no --set of their own to replay from a Boothfile header. The
// Container section's "Docker-in-Docker" checkbox has to be derived from the
// live selection instead, or it shows unchecked while config.toml already
// carries dind = true.

func boolPtr(b bool) *bool { return &b }

func dindRegistry() *tmpl.TemplateRegistry {
	trueVal := boolPtr(true)
	dind := &tmpl.Template{Name: "dind", DisplayName: "Docker-in-Docker", CategoryName: "tools", Dind: trueVal}
	kind := &tmpl.Template{Name: "kind", DisplayName: "kind", CategoryName: "tools", Requires: []string{"dind"}}
	samCLI := &tmpl.Template{
		Name: "aws-sam-cli", DisplayName: "AWS SAM CLI", CategoryName: "tools",
		Extensions: []*tmpl.Template{
			{Name: "dind", DisplayName: "Docker-in-Docker (for sam local)", Dind: trueVal},
		},
	}
	plain := &tmpl.Template{Name: "go", DisplayName: "Go", CategoryName: "tools"}

	return &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{
			Name:      "tools",
			Templates: []*tmpl.Template{dind, kind, samCLI, plain},
		}},
		ByName: map[string]*tmpl.Template{
			"dind":        dind,
			"kind":        kind,
			"aws-sam-cli": samCLI,
			"go":          plain,
		},
	}
}

func dindModel() model {
	reg := dindRegistry()
	items := []treeItem{
		{kind: kindTemplate, template: reg.ByName["dind"]},
		{kind: kindTemplate, template: reg.ByName["kind"]},
		{kind: kindTemplate, template: reg.ByName["aws-sam-cli"]},
		{kind: kindExtension, template: reg.ByName["aws-sam-cli"], extension: reg.ByName["aws-sam-cli"].Extensions[0]},
		{kind: kindTemplate, template: reg.ByName["go"]},
	}
	return model{
		registry:      reg,
		selected:      map[string]bool{},
		boolFields:    defaultBoolValues(),
		paramValues:   map[string]string{},
		tabNames:      []string{"Config", "Tools"},
		tabItems:      [][]treeItem{nil, items},
		activeTab:     1,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		width:         100,
		height:        40,
	}
}

func TestTemplateImpliesDind_UnselectedIsFalse(t *testing.T) {
	m := dindModel()
	if m.templateImpliesDind() {
		t.Error("nothing selected — should not imply dind")
	}
}

func TestTemplateImpliesDind_DindTemplateSelected(t *testing.T) {
	m := dindModel()
	m.selected["dind"] = true
	if !m.templateImpliesDind() {
		t.Error("dind template selected — should imply dind")
	}
}

func TestTemplateImpliesDind_UnrelatedTemplateSelected(t *testing.T) {
	m := dindModel()
	m.selected["go"] = true
	if m.templateImpliesDind() {
		t.Error("go template carries no dind default — should not imply dind")
	}
}

func TestTemplateImpliesDind_ExtensionSelected(t *testing.T) {
	m := dindModel()
	m.selected["aws-sam-cli"] = true
	m.selected["aws-sam-cli/dind"] = true
	if !m.templateImpliesDind() {
		t.Error("aws-sam-cli's dind extension selected — should imply dind")
	}
}

func TestTemplateImpliesDind_ParentWithoutExtensionIsFalse(t *testing.T) {
	m := dindModel()
	m.selected["aws-sam-cli"] = true
	if m.templateImpliesDind() {
		t.Error("aws-sam-cli alone (extension not selected) should not imply dind")
	}
}

// kind requires dind, so selecting kind in the TUI asks to pull dind in too —
// and once confirmed, the Container checkbox shows it, live, without
// reopening anything.
func TestKindSelection_AsksThenCascadesToDindAndChecksBox(t *testing.T) {
	m := dindModel()
	m.tabCursors[1] = 1 // kind
	m.toggleSelection()

	if m.confirmRequires == nil {
		t.Fatal("selecting kind should pose a requires confirmation")
	}
	if m.selected["kind"] || m.selected["dind"] {
		t.Fatal("nothing should be selected until the prompt is answered")
	}
	if !strings.Contains(m.notification, "kind") || !strings.Contains(m.notification, "Docker-in-Docker") {
		t.Errorf("prompt should name both kind and Docker-in-Docker, got %q", m.notification)
	}

	answerYes(&m)

	if !m.selected["kind"] {
		t.Fatal("kind should be selected")
	}
	if !m.selected["dind"] {
		t.Error("confirming should select its required dind template")
	}
	if !m.templateImpliesDind() {
		t.Error("Docker-in-Docker should read as implied once kind pulls in dind")
	}

	f := allConfigFields[fieldIndexByKey(t, "dind")]
	if got := m.renderBoolField(f, 30, false); !strings.Contains(got, "[x]") {
		t.Errorf("Docker-in-Docker checkbox should render checked, got %q", got)
	}
}

// Declining the prompt leaves kind unselected too — the whole thing is
// called off, not just the dind half of it.
func TestKindSelection_DecliningLeavesNothingSelected(t *testing.T) {
	m := dindModel()
	m.tabCursors[1] = 1 // kind
	m.toggleSelection()
	answerNo(&m)

	if m.confirmRequires != nil {
		t.Error("prompt should be dismissed")
	}
	if m.selected["kind"] || m.selected["dind"] {
		t.Error("declining should leave kind and dind both unselected")
	}
}

// Deselecting dind while kind (which requires it) is still selected asks
// first, naming kind as what would be orphaned; confirming takes kind down
// with it.
func TestDeselectingDind_AsksThenCascadesRemovesKind(t *testing.T) {
	m := dindModel()
	m.tabCursors[1] = 1 // kind
	m.toggleSelection()
	answerYes(&m) // kind + dind now both selected

	m.tabCursors[1] = 0 // dind
	m.toggleSelection()

	if m.confirmRequires == nil {
		t.Fatal("deselecting dind while kind needs it should pose a confirmation")
	}
	if !m.selected["kind"] || !m.selected["dind"] {
		t.Fatal("nothing should change until the prompt is answered")
	}
	if !strings.Contains(m.notification, "kind") {
		t.Errorf("prompt should name kind as the dependent, got %q", m.notification)
	}

	answerYes(&m)

	if m.selected["dind"] {
		t.Error("dind should be deselected")
	}
	if m.selected["kind"] {
		t.Error("confirming should deselect its dependent kind too")
	}
}

// Declining leaves both selected — the deselect of dind is called off too.
func TestDeselectingDind_DecliningLeavesBothSelected(t *testing.T) {
	m := dindModel()
	m.tabCursors[1] = 1 // kind
	m.toggleSelection()
	answerYes(&m)

	m.tabCursors[1] = 0 // dind
	m.toggleSelection()
	answerNo(&m)

	if !m.selected["kind"] || !m.selected["dind"] {
		t.Error("declining should leave both kind and dind selected")
	}
}

// answerYes drives a pending requires confirmation to "yes" in place.
func answerYes(m *model) {
	res, _ := m.handleRequiresConfirm(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'y'}})
	*m = res.(model)
}

// answerNo drives a pending requires confirmation to "no" in place.
func answerNo(m *model) {
	res, _ := m.handleRequiresConfirm(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'n'}})
	*m = res.(model)
}

func fieldIndexByKey(t *testing.T, key string) int {
	t.Helper()
	for i, f := range allConfigFields {
		if f.Key == key {
			return i
		}
	}
	t.Fatalf("no config field with key %q", key)
	return -1
}

// Checking "Docker-in-Docker" from the Config tab must select the "dind"
// tool in the catalog — the two are the same setting, so acting on either
// has to act on both.
func TestCheckingDockerInDocker_SelectsDindTool(t *testing.T) {
	m := dindModel()
	row := configRow{kind: configRowField, fieldIdx: fieldIndexByKey(t, "dind")}

	m.activateConfigRow(row)
	if !m.selected["dind"] {
		t.Fatal("checking Docker-in-Docker should select the dind tool")
	}
	if !m.boolFields["dind"] {
		t.Error("boolFields[dind] should be true after checking")
	}
}

func TestUncheckingDockerInDocker_DeselectsDindTool(t *testing.T) {
	m := dindModel()
	row := configRow{kind: configRowField, fieldIdx: fieldIndexByKey(t, "dind")}

	m.activateConfigRow(row) // check
	m.activateConfigRow(row) // uncheck

	if m.selected["dind"] {
		t.Error("unchecking Docker-in-Docker should deselect the dind tool")
	}
	if m.boolFields["dind"] {
		t.Error("boolFields[dind] should be false after unchecking")
	}
}

// Selecting kind (which requires dind) first, then checking the box, must
// not double-select or error — it's already on.
func TestCheckingDockerInDocker_NoOpWhenAlreadyImpliedByKind(t *testing.T) {
	m := dindModel()
	m.tabCursors[1] = 1 // kind
	m.toggleSelection()
	answerYes(&m)

	row := configRow{kind: configRowField, fieldIdx: fieldIndexByKey(t, "dind")}
	m.activateConfigRow(row)

	if !m.selected["dind"] || !m.selected["kind"] {
		t.Error("kind and dind should both remain selected")
	}
}
