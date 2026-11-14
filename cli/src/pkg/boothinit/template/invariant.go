// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"fmt"
	"sort"
	"strings"
)

// BaseVariant is the variant every other variant image is built FROM, so a
// template listed as in "base" is in every variant.
const BaseVariant = "base"

// InVariant reports whether the image of the given canonical variant already
// holds what this template installs (see Template.InVariants). An empty variant
// matches nothing: the caller could not tell which image the booth runs.
func (t *Template) InVariant(variant string) bool {
	if t == nil || variant == "" {
		return false
	}
	for _, v := range t.InVariants {
		v = strings.TrimSpace(v)
		if v == BaseVariant || v == variant {
			return true
		}
	}
	return false
}

// InVariantsText says which images hold this template, for a detail panel:
// "every variant (base image)" or the variants by name. Empty when none do.
func (t *Template) InVariantsText() string {
	if t == nil || len(t.InVariants) == 0 {
		return ""
	}
	var names []string
	for _, v := range t.InVariants {
		v = strings.TrimSpace(v)
		if v == BaseVariant {
			return "every variant (base image)"
		}
		if v != "" {
			names = append(names, v)
		}
	}
	sort.Strings(names)
	return strings.Join(names, ", ")
}

// InVariantNote is the one-line "already in the image" message shown when the
// template is selected, in the TUI and the Web UI alike.
func (t *Template) InVariantNote(variant string) string {
	return fmt.Sprintf("= %s is already in the %s image — selecting it installs the template's own release over it",
		t.Name, variant)
}
