// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"strings"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/tui"
)

// The Web UI marks templates already in the variant image from two pieces of
// data: each item's inVariants in the catalog, and the canonical variant in the
// session state. Selecting one says so, as the TUI does.

func variantRegistry() *tmpl.TemplateRegistry {
	glow := &tmpl.Template{Name: "glow", InVariants: []string{"base"}}
	firefox := &tmpl.Template{Name: "firefox", InVariants: []string{"desktop-xfce"}}
	lazygit := &tmpl.Template{Name: "lazygit", InVariants: []string{"base"}, Remove: "run rm -f /usr/local/bin/lazygit"}
	return &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{Name: "tools", DisplayName: "Tools", Templates: []*tmpl.Template{glow, firefox, lazygit}}},
		ByName:     map[string]*tmpl.Template{"glow": glow, "firefox": firefox, "lazygit": lazygit},
	}
}

func TestCatalog_CarriesInVariants(t *testing.T) {
	catalog := BuildCatalog(variantRegistry(), "amd64")
	views := catalog.Categories[0].Templates
	if got := strings.Join(views[0].InVariants, ","); got != "base" {
		t.Errorf("glow inVariants = %q, want base", got)
	}
	if views[1].InVariants == nil {
		t.Error("inVariants should be an empty list, never null, for the page to read")
	}
}

func TestSession_StateResolvesVariant(t *testing.T) {
	session := NewSession(variantRegistry(), nil, "", nil)
	if got := session.CurrentState().Variant; got != "base" {
		t.Errorf("default variant = %q, want base", got)
	}
	pre := &tui.PreSelection{StringFields: map[string]string{"variant": "xfce"}}
	session = NewSession(variantRegistry(), pre, "", nil)
	if got := session.CurrentState().Variant; got != "desktop-xfce" {
		t.Errorf("xfce variant = %q, want desktop-xfce", got)
	}
}

func TestSession_SelectInVariantSaysSo(t *testing.T) {
	session := NewSession(variantRegistry(), nil, "", nil)
	if err := session.Toggle("glow"); err != nil {
		t.Fatal(err)
	}
	if got := session.CurrentState().Notification; !strings.Contains(got, "glow is already in the base image") {
		t.Errorf("notification = %q, want the already-in-image note", got)
	}
	if err := session.Toggle("firefox"); err != nil {
		t.Fatal(err)
	}
	if got := session.CurrentState().Notification; strings.Contains(got, "already in") {
		t.Errorf("firefox is not in base, notification = %q", got)
	}
}

func TestSession_RemovableCyclesThroughRemoved(t *testing.T) {
	session := NewSession(variantRegistry(), nil, "", nil)
	want := []string{"~lazygit", "lazygit", ""}
	for i, dsl := range want {
		if err := session.Toggle("lazygit"); err != nil {
			t.Fatal(err)
		}
		if got := session.Result(false).SelectDSL; got != dsl {
			t.Fatalf("after %d toggles DSL = %q, want %q", i+1, got, dsl)
		}
	}
}

func TestSession_StateNamesRemoved(t *testing.T) {
	session := NewSession(variantRegistry(), nil, "", nil)
	_ = session.Toggle("lazygit")
	state := session.CurrentState()
	if !state.Removed["lazygit"] || !state.Dirty {
		t.Errorf("removed = %v dirty = %v, want lazygit removed and a change to save", state.Removed, state.Dirty)
	}
	if views := BuildCatalog(variantRegistry(), "amd64").Categories[0].Templates; !views[2].Removable || views[0].Removable {
		t.Errorf("catalog removable flags wrong: glow=%v lazygit=%v", views[0].Removable, views[2].Removable)
	}
}

func TestSession_PreSelectedRemovalReopens(t *testing.T) {
	pre := &tui.PreSelection{Removed: map[string]bool{"lazygit": true}}
	session := NewSession(variantRegistry(), pre, "", nil)
	if got := session.Result(false).SelectDSL; got != "~lazygit" {
		t.Errorf("DSL = %q, want ~lazygit", got)
	}
	if session.CurrentState().Dirty {
		t.Error("a removal read back from the booth is not a change")
	}
}
