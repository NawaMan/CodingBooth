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
	return &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{Name: "tools", DisplayName: "Tools", Templates: []*tmpl.Template{glow, firefox}}},
		ByName:     map[string]*tmpl.Template{"glow": glow, "firefox": firefox},
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
