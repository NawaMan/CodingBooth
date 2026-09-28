// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"strings"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// LiftParams rewrites the explicit params of sel to the values the Boothfile's
// `arg` lines hold, for every one that differs, and reports whether any changed.
//
// A param the selection leaves unset already follows the Boothfile: the resolver
// takes it from the existing args (see resolveParams). An explicit one does not —
// `go:1.25` wins over an `arg GO_VERSION=1.26.1` edited by hand — so reading such
// an edit back means moving it into the selection itself.
func LiftParams(sel *ParsedSelection, registry *tmpl.TemplateRegistry, args map[string]string) bool {
	if sel == nil || registry == nil || len(args) == 0 {
		return false
	}

	changed := false
	for i := range sel.Items {
		item := &sel.Items[i]
		t, ok := registry.ByName[item.Name]
		if !ok {
			continue
		}
		if lifted, did := liftPositional(t, item.Params, args); did {
			item.Params = lifted
			changed = true
		}

		for j := range item.Extensions {
			ext := &item.Extensions[j]
			extTemplate := findExtension(t, ext.Name)
			if extTemplate == nil {
				continue
			}
			if lifted, did := liftPositional(extTemplate, ext.Params, args); did {
				ext.Params = lifted
				changed = true
			}
		}
	}
	return changed
}

func findExtension(t *tmpl.Template, name string) *tmpl.Template {
	for _, ext := range t.Extensions {
		if ext.Name == name {
			return ext
		}
	}
	return nil
}

// liftPositional returns positional with each explicitly-given value replaced by
// the matching arg, when the two differ. Params left empty are skipped: those
// already follow the args through the resolver.
func liftPositional(t *tmpl.Template, positional []string, args map[string]string) ([]string, bool) {
	names := orderedParamNames(t)
	lifted := append([]string{}, positional...)
	changed := false

	for i, name := range names {
		if i >= len(lifted) {
			break
		}
		value, ok := args[name]
		if !ok {
			continue
		}

		isLast := i == len(names)-1
		if isLast && t.Params[name].Variadic {
			// A variadic param absorbs the rest, and its arg holds the canonical
			// (deduped, sorted) join — compare in that form, or a reordered list
			// would read as an edit.
			if CanonicalizeVariadic(lifted[i:]) != value {
				lifted = append(lifted[:i], strings.Split(value, ",")...)
				changed = true
			}
			break
		}

		if lifted[i] != "" && lifted[i] != value {
			lifted[i] = value
			changed = true
		}
	}
	return lifted, changed
}
