// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import "strings"

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
func SerializeItem(item ParsedItem) string {
	var b strings.Builder
	b.WriteString(item.Name)
	writeParamList(&b, item.Params)
	for _, ext := range item.Extensions {
		b.WriteByte('+')
		b.WriteString(ext.Name)
		writeParamList(&b, ext.Params)
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
func writeParamList(b *strings.Builder, params []string) {
	if len(params) == 0 {
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

// MergeSelections merges add onto base: an add item whose name already exists in
// base has its extensions and excludes unioned into the existing item (an
// extension named the same as one already there has its params replace, rather
// than duplicate) and its params replace the base item's params only when the add
// item specifies any; an add item with a name not in base is appended. Base item
// order is preserved; new items from add are appended in add's order.
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
	merged := base
	if len(add.Params) > 0 {
		merged.Params = add.Params
	}
	merged.Extensions = mergeExtensions(base.Extensions, add.Extensions)
	merged.Excludes = mergeNames(base.Excludes, add.Excludes)
	return merged
}

func mergeExtensions(base, add []ParsedExtension) []ParsedExtension {
	result := make([]ParsedExtension, len(base))
	copy(result, base)
	for _, a := range add {
		found := false
		for i, b := range result {
			if b.Name == a.Name {
				if len(a.Params) > 0 {
					result[i].Params = a.Params
				}
				found = true
				break
			}
		}
		if !found {
			result = append(result, a)
		}
	}
	return result
}

func mergeNames(base, add []string) []string {
	result := make([]string, len(base))
	copy(result, base)
	for _, a := range add {
		if !containsName(result, a) {
			result = append(result, a)
		}
	}
	return result
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

// RemoveFromSelection drops each of names from sel: a name matching a top-level
// item removes that whole item (and everything selected under it); a name that
// does not match any top-level item is looked for as an extension name within
// each remaining item, in item order, and removed from the first one found.
// A name matching neither is reported back in unmatched, in the order given,
// rather than treated as an error — re-running the same removal is a no-op.
//
// sel may be nil (nothing to remove from); the result may likewise be nil if
// removing names empties the selection entirely.
func RemoveFromSelection(sel *ParsedSelection, names []string) (result *ParsedSelection, unmatched []string) {
	if sel == nil || len(names) == 0 {
		return sel, names
	}

	items := make([]ParsedItem, len(sel.Items))
	copy(items, sel.Items)

	for _, name := range names {
		if idx := indexOfItem(items, name); idx >= 0 {
			items = append(items[:idx], items[idx+1:]...)
			continue
		}
		if removeExtensionByName(items, name) {
			continue
		}
		unmatched = append(unmatched, name)
	}

	if len(items) == 0 {
		return nil, unmatched
	}
	return &ParsedSelection{Items: items}, unmatched
}

// removeExtensionByName drops the first extension named name from the first item
// that has one, mutating items in place. Reports whether it found one.
func removeExtensionByName(items []ParsedItem, name string) bool {
	for i := range items {
		for j, ext := range items[i].Extensions {
			if ext.Name == name {
				items[i].Extensions = append(items[i].Extensions[:j], items[i].Extensions[j+1:]...)
				return true
			}
		}
	}
	return false
}
