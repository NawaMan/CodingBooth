// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/tui"
)

func sessionRegistry() *tmpl.TemplateRegistry {
	auto := true
	linter := &tmpl.Template{Name: "linter", AutoSelect: &auto}
	goPkg := &tmpl.Template{
		Name:       "go-pkg",
		Params:     map[string]tmpl.Param{"GO_PKGS": {Default: "", Variadic: true}},
		ParamOrder: []string{"GO_PKGS"},
	}
	goTmpl := &tmpl.Template{
		Name:       "go",
		Primary:    true,
		Params:     map[string]tmpl.Param{"GO_VERSION": {Default: "1.25.7"}},
		ParamOrder: []string{"GO_VERSION"},
		Extensions: []*tmpl.Template{linter, goPkg},
	}
	python := &tmpl.Template{Name: "python", Requires: []string{"go"}}
	claude := &tmpl.Template{Name: "claude-code"}
	return &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{
			{Name: "languages", DisplayName: "Languages", Templates: []*tmpl.Template{goTmpl, python}},
			{Name: "tools", DisplayName: "Tools", Templates: []*tmpl.Template{claude}},
		},
		ByName: map[string]*tmpl.Template{
			"go":          goTmpl,
			"python":      python,
			"claude-code": claude,
		},
	}
}

func TestSession_ToggleAutoSelectsExtension(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	if err := session.Toggle("go"); err != nil {
		t.Fatal(err)
	}
	state := session.CurrentState()
	if !state.Selected["go"] || !state.Selected["go/linter"] {
		t.Fatalf("selected = %v, want go and go/linter", state.Selected)
	}
	if got := session.Result(false).SelectDSL; got != "go+linter" {
		t.Fatalf("DSL = %q, want go+linter", got)
	}
}

func TestSession_DeselectDropsExtensions(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	_ = session.Toggle("go")
	_ = session.Toggle("go")
	state := session.CurrentState()
	if state.Selected["go"] || state.Selected["go/linter"] {
		t.Fatalf("deselecting go should drop extensions, got %v", state.Selected)
	}
}

func TestSession_ToggleSelectsDependencies(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	if err := session.Toggle("python"); err != nil {
		t.Fatal(err)
	}
	state := session.CurrentState()
	if !state.Selected["python"] || !state.Selected["go"] || !state.Selected["go/linter"] {
		t.Fatalf("python should pull go+linter, got %v", state.Selected)
	}
	if got := session.Result(false).SelectDSL; got != "go+linter/python" {
		t.Fatalf("DSL = %q, want go+linter/python", got)
	}
}

func TestSession_ExcludeAutoSelectInDSL(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	_ = session.Toggle("go")
	_ = session.Toggle("go/linter")
	if got := session.Result(false).SelectDSL; got != "go~linter" {
		t.Fatalf("DSL = %q, want go~linter", got)
	}
}

func TestSession_ParamPinRoundTripsInDSL(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	_ = session.Toggle("go")
	session.SetParam("go:GO_VERSION", "1.24.0")
	if got := session.Result(false).SelectDSL; got != "go:1.24.0+linter" {
		t.Fatalf("DSL = %q, want go:1.24.0+linter", got)
	}
}

func TestSession_PreSelectionIsBaselineNotDirty(t *testing.T) {
	pre := &tui.PreSelection{
		SelectedTemplates: map[string]bool{"go": true},
		SelectedExts:      map[string]map[string]bool{"go": {"linter": true}},
		StringFields:      map[string]string{"port": "18000"},
	}
	session := NewSession(sessionRegistry(), pre, "", nil)
	state := session.CurrentState()
	if !state.Selected["go"] || state.StringFields["port"] != "18000" {
		t.Fatalf("pre-selection not applied: %+v", state)
	}
	if state.Dirty {
		t.Fatal("opening on an existing booth should not look dirty")
	}
	_ = session.Toggle("python")
	if !session.CurrentState().Dirty {
		t.Fatal("selecting python should mark dirty")
	}
}

func TestSession_UnknownToggleErrors(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	if err := session.Toggle("nope"); err == nil {
		t.Fatal("unknown template should error")
	}
}
