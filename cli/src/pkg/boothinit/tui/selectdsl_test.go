// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// goRegistry builds a registry shaped like the real one: a "go" template with a
// version param and a variadic go-pkg extension, plus a second template so the
// DSL has to put a "/" after the package list.
func goRegistry() *tmpl.TemplateRegistry {
	goPkg := &tmpl.Template{
		Name:       "go-pkg",
		Params:     map[string]tmpl.Param{"GO_PKGS": {Default: "", Variadic: true}},
		ParamOrder: []string{"GO_PKGS"},
	}
	goTmpl := &tmpl.Template{
		Name:       "go",
		Params:     map[string]tmpl.Param{"GO_VERSION": {Default: "1.25.7"}},
		ParamOrder: []string{"GO_VERSION"},
		Extensions: []*tmpl.Template{goPkg},
	}
	claude := &tmpl.Template{Name: "claude-code"}

	return &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{
			Name:      "all",
			Templates: []*tmpl.Template{goTmpl, claude},
		}},
		ByName: map[string]*tmpl.Template{"go": goTmpl, "claude-code": claude},
	}
}

func goModel(pkgs string) model {
	return model{
		registry:    goRegistry(),
		selected:    map[string]bool{"go": true, "go/go-pkg": true, "claude-code": true},
		paramValues: map[string]string{"go/go-pkg:GO_PKGS": pkgs},
	}
}

// A module path is all slashes, and an unquoted slash starts a new template — the
// DSL the TUI saved could not be read back, and `booth config` on a booth pinning
// GO_PKGS died with `template "pocketbase" selected more than once`.
func TestBuildSelectDSL_ModulePathRoundTrips(t *testing.T) {
	const pkgs = "github.com/pocketbase/pocketbase/examples/base@latest"
	dsl := goModel(pkgs).buildSelectDSL()

	parsed, err := selection.ParseSelectDSL(dsl)
	if err != nil {
		t.Fatalf("re-parsing %q: %v", dsl, err)
	}
	if len(parsed.Items) != 2 {
		t.Fatalf("want 2 items from %q, got %d: %+v", dsl, len(parsed.Items), parsed.Items)
	}
	if parsed.Items[0].Name != "go" || parsed.Items[1].Name != "claude-code" {
		t.Fatalf("items from %q: %q, %q", dsl, parsed.Items[0].Name, parsed.Items[1].Name)
	}
	got := parsed.Items[0].Extensions[0].Params
	if len(got) != 1 || got[0] != pkgs {
		t.Fatalf("go-pkg params from %q: %q", dsl, got)
	}
}

func TestBuildSelectDSL_MultiplePackagesRoundTrip(t *testing.T) {
	dsl := goModel("github.com/a/b@v1,github.com/c/d@v2").buildSelectDSL()

	parsed, err := selection.ParseSelectDSL(dsl)
	if err != nil {
		t.Fatalf("re-parsing %q: %v", dsl, err)
	}
	got := parsed.Items[0].Extensions[0].Params
	if len(got) != 2 || got[0] != "github.com/a/b@v1" || got[1] != "github.com/c/d@v2" {
		t.Fatalf("go-pkg params from %q: %q", dsl, got)
	}
}

// A package name with nothing special in it must not gain quotes: the DSL goes
// into the header of every generated file, and churning those is its own problem.
func TestBuildSelectDSL_PlainValueIsNotQuoted(t *testing.T) {
	m := goModel("")
	m.paramValues["go:GO_VERSION"] = "1.24.0"

	if got, want := m.buildSelectDSL(), "go:1.24.0+go-pkg/claude-code"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

// A value left at its default still drops out of the DSL entirely — quoting must
// not make an unset param look pinned.
func TestBuildSelectDSL_DefaultsStayOut(t *testing.T) {
	if got, want := goModel("").buildSelectDSL(), "go+go-pkg/claude-code"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}
