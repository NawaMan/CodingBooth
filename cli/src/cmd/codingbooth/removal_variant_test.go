// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// A "~name" only makes sense when the booth's variant image ships the tool.
func TestCheckRemovalsInVariant(t *testing.T) {
	firefox := &tmpl.Template{Name: "firefox", InVariants: []string{"desktop-xfce"}, Remove: "run x"}
	glow := &tmpl.Template{Name: "glow", InVariants: []string{"base"}, Remove: "run x"}
	resolved := func(ts ...*tmpl.Template) *selection.ResolvedSelection {
		return &selection.ResolvedSelection{Removed: ts}
	}

	for _, ok := range []struct {
		variant string
		removed *tmpl.Template
	}{
		{"", glow}, {"notebook", glow}, {"xfce", firefox}, {"desktop-xfce", firefox},
	} {
		if err := checkRemovalsInVariant(resolved(ok.removed), ok.variant); err != nil {
			t.Errorf("~%s on %q: unexpected error %v", ok.removed.Name, ok.variant, err)
		}
	}

	err := checkRemovalsInVariant(resolved(firefox), "")
	if err == nil || !strings.Contains(err.Error(), "not in the base image") {
		t.Errorf("~firefox on base should be refused, got %v", err)
	}
	if err := checkRemovalsInVariant(resolved(firefox), "no-such"); err != nil {
		t.Errorf("an unknown variant is left for ValidateVariant to report, got %v", err)
	}
	if err := checkRemovalsInVariant(nil, ""); err != nil {
		t.Errorf("nil selection: %v", err)
	}
}
