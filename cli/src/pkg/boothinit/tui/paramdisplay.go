// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"sort"
	"strings"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// A param default may reference another param — an expose extension's host port
// defaults to "${SVC_PORT}" so it follows the port the service actually listens on.
// paramValues stores that reference verbatim, which is what keeps the link alive: it
// still equals the declared default, so buildParamDSL omits it from the selection and
// the compiler resolves it against whatever the service port ends up being. Only the
// display is resolved, so the user sees the port rather than the raw "${SVC_PORT}".

// flatParamValues collapses paramValues ("itemKey:NAME" → value) into the flat
// name → value namespace the compiler merges params into. If two selected items declare
// the same param name, the lowest item key wins — the compiler rejects genuinely
// conflicting values later; here we only need a stable value to show.
func (m model) flatParamValues() map[string]string {
	keys := make([]string, 0, len(m.paramValues))
	for k := range m.paramValues {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	flat := make(map[string]string, len(keys))
	for _, k := range keys {
		sep := strings.LastIndex(k, ":")
		if sep < 0 {
			continue
		}
		name := k[sep+1:]
		if _, exists := flat[name]; !exists {
			flat[name] = m.paramValues[k]
		}
	}
	return flat
}

// paramDisplay returns the value to show for a param: any ${OTHER} references resolved
// against the current selection, plus the param names it follows (nil when it holds no
// references). A circular default falls back to showing the value raw — the compiler
// reports the cycle on save, and the TUI has nowhere useful to say it.
func (m model) paramDisplay(val string) (display string, follows []string) {
	refs := tmpl.ParamRefNames(val)
	if len(refs) == 0 {
		return val, nil
	}

	flat := m.flatParamValues()
	resolved, err := tmpl.ResolveParamRefs(flat)
	if err != nil {
		return val, nil
	}

	for _, ref := range refs {
		if _, isParam := flat[ref]; isParam {
			follows = append(follows, ref)
		}
	}
	return tmpl.ExpandRefs(val, resolved), follows
}

// followsHint renders the "(follows X)" suffix for a param that references another.
func followsHint(follows []string) string {
	if len(follows) == 0 {
		return ""
	}
	return " (follows " + strings.Join(follows, ", ") + ")"
}
