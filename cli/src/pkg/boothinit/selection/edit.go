// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"strings"
)

// SerializeSelection renders a ParsedSelection back to DSL text, in item order,
// joined with "/". Used by `booth config`'s --add-select/--remove-select to turn
// a merged or filtered ParsedSelection back into text ParseSelectDSL can read
// again on the next reconfigure.
func SerializeSelection(sel *ParsedSelection) string {
	if sel == nil || len(sel.Items) == 0 {
		return ""
	}
	parts := make([]string, len(sel.Items))
	for i, item := range sel.Items {
		parts[i] = SerializeItem(item)
	}
	return strings.Join(parts, "/")
}

// SerializeItem renders a single ParsedItem back to DSL text:
// name[:p1,p2][+ext1[:e1p1,...]]...[~exc1][~exc2]
//
// A param reset ("go:") is written as an empty param list, so it survives the
// trip to the compiler; StripParamResets drops it before the header is written.
func SerializeItem(item ParsedItem) string {
	if item.Remove {
		return "~" + item.Name
	}
	var b strings.Builder
	b.WriteString(item.Name)
	writeParamList(&b, item.Params, item.ResetParams)
	for _, ext := range item.Extensions {
		b.WriteByte('+')
		b.WriteString(ext.Name)
		writeParamList(&b, ext.Params, ext.ResetParams)
	}
	for _, exc := range item.Excludes {
		b.WriteByte('~')
		b.WriteString(exc)
	}
	return b.String()
}

// writeParamList appends ":p1,p2,..." to b, quoting each param independently
// (rather than joining first and re-splitting) so a param that itself contains a
// comma round-trips instead of being torn in two.
func writeParamList(b *strings.Builder, params []string, reset bool) {
	if len(params) == 0 {
		if reset {
			b.WriteByte(':')
		}
		return
	}
	b.WriteByte(':')
	for i, p := range params {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(QuoteParam(p))
	}
}

// A selection is a shallow tree. The root holds templates; each template holds
// its extensions. Every node sits in a slot keyed by (parent, name), and a slot
// is in one of three states: absent, selected (with its params), or "~"
// (a root ~glow takes glow out of the image; go~lsp excludes go's default lsp
// extension). Editing a selection writes slots: the later write to a slot wins,
// and a slot nobody writes keeps what it had.

// MergeSelections writes each node of add into base. A node add names that base
// lacks is appended (base order is kept; new nodes follow in add's order). A
// node both have is replaced only in what add says about it: params written
// ("go:1.25") replace the params, an empty list ("go:") resets them to the
// defaults, and a node written without params ("go" in "go+lsp") is only the way
// to its children, so it keeps its params. "+x" and "~x" share a slot, so one
// replaces the other.
//
// Either argument may be nil (an empty existing booth, or no --add-select given).
func MergeSelections(base, add *ParsedSelection) *ParsedSelection {
	if add == nil || len(add.Items) == 0 {
		return base
	}
	if base == nil || len(base.Items) == 0 {
		return add
	}

	items := make([]ParsedItem, len(base.Items))
	copy(items, base.Items)

	for _, addItem := range add.Items {
		if idx := indexOfItem(items, addItem.Name); idx >= 0 {
			items[idx] = mergeItem(items[idx], addItem)
		} else {
			items = append(items, addItem)
		}
	}
	return &ParsedSelection{Items: items}
}

func mergeItem(base, add ParsedItem) ParsedItem {
	// A root slot flips between selected and removed: the later word wins, and
	// it brings nothing of the old state with it.
	if base.Remove || add.Remove {
		return add
	}
	merged := base
	merged.Extensions = append([]ParsedExtension(nil), base.Extensions...)
	merged.Excludes = append([]string(nil), base.Excludes...)
	switch {
	case add.ResetParams:
		merged.Params, merged.ResetParams = nil, true
	case len(add.Params) > 0:
		merged.Params, merged.ResetParams = add.Params, false
	}
	for _, ext := range add.Extensions {
		merged.Excludes = withoutName(merged.Excludes, ext.Name)
		merged.Extensions = mergeExtension(merged.Extensions, ext)
	}
	for _, exc := range add.Excludes {
		merged.Extensions = withoutExtension(merged.Extensions, exc)
		if !containsName(merged.Excludes, exc) {
			merged.Excludes = append(merged.Excludes, exc)
		}
	}
	return merged
}

func mergeExtension(exts []ParsedExtension, add ParsedExtension) []ParsedExtension {
	for i, ext := range exts {
		if ext.Name != add.Name {
			continue
		}
		switch {
		case add.ResetParams:
			exts[i].Params, exts[i].ResetParams = nil, true
		case len(add.Params) > 0:
			exts[i].Params, exts[i].ResetParams = add.Params, false
		}
		return exts
	}
	return append(exts, add)
}

func withoutName(names []string, name string) []string {
	out := names[:0:0]
	for _, n := range names {
		if n != name {
			out = append(out, n)
		}
	}
	return out
}

func withoutExtension(exts []ParsedExtension, name string) []ParsedExtension {
	out := exts[:0:0]
	for _, ext := range exts {
		if ext.Name != name {
			out = append(out, ext)
		}
	}
	return out
}

func containsName(names []string, name string) bool {
	for _, n := range names {
		if n == name {
			return true
		}
	}
	return false
}

func indexOfItem(items []ParsedItem, name string) int {
	for i, it := range items {
		if it.Name == name {
			return i
		}
	}
	return -1
}

// StripParamResets returns sel without its param-reset markers. A reset is an
// instruction to this run's resolver ("ignore the pin the old Boothfile holds"),
// not a node: the header records the node, which then simply has no params.
func StripParamResets(sel *ParsedSelection) *ParsedSelection {
	if sel == nil {
		return nil
	}
	items := make([]ParsedItem, len(sel.Items))
	for i, item := range sel.Items {
		item.ResetParams = false
		exts := make([]ParsedExtension, len(item.Extensions))
		for j, ext := range item.Extensions {
			ext.ResetParams = false
			exts[j] = ext
		}
		item.Extensions = exts
		items[i] = item
	}
	return &ParsedSelection{Items: items}
}

// NoMatchError is a --remove-select path that names a slot holding nothing.
type NoMatchError struct {
	Path   string
	Reason string
}

func (e *NoMatchError) Error() string {
	if e.Reason == "" {
		return "did not match anything in the existing selection"
	}
	return "did not match anything in the existing selection: " + e.Reason
}

// RemovePath clears the slot path names and returns the selection without it.
//
//	go        the template go, with its extensions; also a root ~go
//	~glow     a root ~glow only (glow is not taken out of the image any more)
//	go+lsp    the extension lsp under go
//	go~lsp    the exclusion of lsp under go
//
// A path names exactly one node, so it carries no params, no second extension,
// and no "/". A bare extension name is not a path — the same extension name sits
// under several templates — so it is refused with the paths that would match. A
// recipe (@name) is refused too: it expands into nodes when it is used, and
// nothing records which nodes those were.
//
// A path whose slot is empty returns a *NoMatchError; any other refusal is a
// plain error. sel is not modified.
func RemovePath(sel *ParsedSelection, path string) (*ParsedSelection, error) {
	path = strings.TrimSpace(path)
	switch {
	case path == "":
		return sel, fmt.Errorf("empty path")
	case strings.HasPrefix(path, "@"):
		return sel, fmt.Errorf("%s is a recipe, not a node: a recipe is expanded into templates when it is used, so remove those by path (e.g. --remove-select go)", path)
	case strings.Contains(path, "/"):
		return sel, fmt.Errorf("a path names one node; give each its own --remove-select")
	case strings.Contains(path, ":"):
		return sel, fmt.Errorf("a path names a node, not its params; to put params back to their defaults, use --add-select with an empty list (go:)")
	}

	var items []ParsedItem
	if sel != nil {
		items = make([]ParsedItem, len(sel.Items))
		copy(items, sel.Items)
	}
	result := func() *ParsedSelection {
		if len(items) == 0 {
			return nil
		}
		return &ParsedSelection{Items: items}
	}

	// ~glow: a root removal.
	if strings.HasPrefix(path, "~") {
		name := path[1:]
		if name == "" || strings.ContainsAny(name, "+~") {
			return sel, fmt.Errorf("a root removal is ~ and a template name only, as in ~glow")
		}
		idx := indexOfItem(items, name)
		if idx < 0 {
			return sel, &NoMatchError{Path: path}
		}
		if !items[idx].Remove {
			return sel, &NoMatchError{Path: path, Reason: fmt.Sprintf("%s is selected, not removed from the image; --remove-select %s drops it", name, name)}
		}
		items = append(items[:idx], items[idx+1:]...)
		return result(), nil
	}

	sep := strings.IndexAny(path, "+~")
	if sep < 0 {
		if idx := indexOfItem(items, path); idx >= 0 {
			items = append(items[:idx], items[idx+1:]...)
			return result(), nil
		}
		if paths := extensionPaths(items, path); len(paths) > 0 {
			return sel, fmt.Errorf("%s is an extension, not a template: name it with its template — %s", path, strings.Join(paths, " or "))
		}
		return sel, &NoMatchError{Path: path}
	}

	parent, op, name := path[:sep], path[sep], path[sep+1:]
	if parent == "" || name == "" || strings.ContainsAny(name, "+~") {
		return sel, fmt.Errorf("a path is a template, template+extension or template~extension")
	}
	idx := indexOfItem(items, parent)
	if idx < 0 || items[idx].Remove {
		return sel, &NoMatchError{Path: path, Reason: parent + " is not selected"}
	}
	item := items[idx]
	hasExt := false
	for _, ext := range item.Extensions {
		if ext.Name == name {
			hasExt = true
		}
	}
	hasExc := containsName(item.Excludes, name)

	if op == '+' {
		if !hasExt {
			reason := ""
			if hasExc {
				reason = fmt.Sprintf("%s~%s is what the selection holds; --remove-select %s~%s drops it", parent, name, parent, name)
			}
			return sel, &NoMatchError{Path: path, Reason: reason}
		}
		item.Extensions = withoutExtension(item.Extensions, name)
	} else {
		if !hasExc {
			reason := ""
			if hasExt {
				reason = fmt.Sprintf("%s+%s is what the selection holds; --remove-select %s+%s drops it", parent, name, parent, name)
			}
			return sel, &NoMatchError{Path: path, Reason: reason}
		}
		item.Excludes = withoutName(item.Excludes, name)
	}
	items[idx] = item
	return result(), nil
}

// extensionPaths lists the paths at which an extension called name sits in
// items, in item order: "go+lsp" for a selected one, "go~lsp" for an excluded one.
func extensionPaths(items []ParsedItem, name string) []string {
	var paths []string
	for _, item := range items {
		for _, ext := range item.Extensions {
			if ext.Name == name {
				paths = append(paths, item.Name+"+"+name)
			}
		}
		if containsName(item.Excludes, name) {
			paths = append(paths, item.Name+"~"+name)
		}
	}
	return paths
}

// SelectionEditor applies --add-select and --remove-select to a selection in
// command-line order, so that the later write to a slot wins.
//
// A node removed in this run and then added back without params comes back new:
// at its defaults, not at the pin the existing Boothfile still holds for it.
// Removing go takes go's whole subtree, so its extensions come back new too.
type SelectionEditor struct {
	sel     *ParsedSelection
	removed map[string]bool // "go" (a template and its subtree) or "go+lsp"
}

// NewSelectionEditor starts editing base, which may be nil.
func NewSelectionEditor(base *ParsedSelection) *SelectionEditor {
	return &SelectionEditor{sel: base, removed: map[string]bool{}}
}

// Add writes add's nodes into the selection (see MergeSelections).
func (e *SelectionEditor) Add(add *ParsedSelection) {
	if add == nil {
		return
	}
	marked := &ParsedSelection{Items: make([]ParsedItem, len(add.Items))}
	for i, item := range add.Items {
		if !item.Remove {
			if e.removed[item.Name] && len(item.Params) == 0 {
				item.ResetParams = true
			}
			exts := make([]ParsedExtension, len(item.Extensions))
			for j, ext := range item.Extensions {
				if (e.removed[item.Name] || e.removed[item.Name+"+"+ext.Name]) && len(ext.Params) == 0 {
					ext.ResetParams = true
				}
				exts[j] = ext
			}
			item.Extensions = exts
		}
		marked.Items[i] = item
	}
	e.sel = MergeSelections(e.sel, marked)
}

// Remove clears the slot path names (see RemovePath). On an error the selection
// is left as it was.
func (e *SelectionEditor) Remove(path string) error {
	next, err := RemovePath(e.sel, path)
	if err != nil {
		return err
	}
	e.sel = next
	// An exclusion or a root ~name carries no params, so only a node does.
	if path = strings.TrimSpace(path); !strings.Contains(path, "~") {
		e.removed[path] = true
	}
	return nil
}

// Selection is the edited selection; nil when nothing is left.
func (e *SelectionEditor) Selection() *ParsedSelection {
	if e.sel == nil || len(e.sel.Items) == 0 {
		return nil
	}
	return e.sel
}
