// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"fmt"
	"io"
	"strings"
)

// FormatRegistryList writes a formatted listing of templates grouped by category.
// Templates are indented with 2 spaces; extensions with 4 spaces and a "+ " prefix.
// Shows the short description (DisplayDesc) instead of tags.
// Extensions with auto-select=true show "(auto)" after the description.
// If includeAutoExtensions is false, auto-select extensions are hidden to keep output compact.
func FormatRegistryList(w io.Writer, registry *TemplateRegistry, includeAutoExtensions bool) {
	if len(registry.Categories) == 0 {
		return
	}

	nameWidth := computeNameWidth(registry, true)

	for i, cat := range registry.Categories {
		if i > 0 {
			fmt.Fprintln(w)
		}
		fmt.Fprintln(w, cat.DisplayName)
		for _, t := range cat.Templates {
			fmt.Fprintf(w, "  %-*s  %s\n",
				nameWidth, t.Name,
				t.DisplayDesc)
			for _, ext := range t.Extensions {
				isAuto := ext.AutoSelect != nil && *ext.AutoSelect
				if !includeAutoExtensions && isAuto {
					continue
				}
				desc := ext.DisplayDesc
				extName := ext.Name
				if isAuto {
					extName += "*"
				}
				fmt.Fprintf(w, "    + %-*s  %s\n",
					nameWidth-4, extName,
					desc)
			}
		}
	}
}

// FormatTemplateDetail writes a detailed view of a single template.
// If detail is true, file/segment contents are shown in full.
func FormatTemplateDetail(w io.Writer, t *Template, registry *TemplateRegistry, detail bool) {
	// Header: DisplayName (name)
	fmt.Fprintf(w, "%s (%s)\n", t.DisplayName, t.Name)

	// Category
	fmt.Fprintf(w, "Category:    %s\n", t.CategoryName)

	// Auto-select (for extensions)
	if t.AutoSelect != nil {
		if *t.AutoSelect {
			fmt.Fprintln(w, "Auto-select: yes")
		} else {
			fmt.Fprintln(w, "Auto-select: no")
		}
	}

	// Short description
	if t.DisplayDesc != "" {
		fmt.Fprintf(w, "Description: %s\n", t.DisplayDesc)
	}

	// No build for this machine's architecture — before the long description, so
	// it is not missed by anyone skimming to decide whether to use the template.
	if t.UnsupportedOn(HostArch()) {
		fmt.Fprintf(w, "\n⚠  Not available on %s\n", HostArch())
		note := t.UnsupportedArchNote
		if note == "" {
			note = fmt.Sprintf("%s has no %s build and will not be installed. "+
				"The booth still builds without it.", t.Name, HostArch())
		}
		for _, line := range strings.Split(note, "\n") {
			fmt.Fprintf(w, "   %s\n", line)
		}
	}

	// Long description
	if t.DisplayDetail != "" {
		fmt.Fprintf(w, "\n%s\n", t.DisplayDetail)
	}

	// Parameters
	if len(t.Params) > 0 {
		fmt.Fprintln(w)
		fmt.Fprintln(w, "Parameters:")
		paramOrder := t.ParamOrder
		if len(paramOrder) == 0 {
			for k := range t.Params {
				paramOrder = append(paramOrder, k)
			}
		}
		nameW := 0
		for _, k := range paramOrder {
			if len(k) > nameW {
				nameW = len(k)
			}
		}
		for _, k := range paramOrder {
			p := t.Params[k]
			line := fmt.Sprintf("  %-*s  default: %s", nameW, k, p.Default)
			if len(p.Suggests) > 0 {
				line += fmt.Sprintf("  suggests: %s", strings.Join(p.Suggests, ", "))
			}
			fmt.Fprintln(w, line)
		}
	}

	// Extensions
	if len(t.Extensions) > 0 {
		fmt.Fprintln(w)
		fmt.Fprintln(w, "Extensions:")
		nameW := 0
		for _, ext := range t.Extensions {
			nameLen := len(ext.Name)
			if ext.AutoSelect != nil && *ext.AutoSelect {
				nameLen += 1
			}
			if nameLen > nameW {
				nameW = nameLen
			}
		}
		for _, ext := range t.Extensions {
			desc := ext.DisplayDesc
			extName := ext.Name
			if ext.AutoSelect != nil && *ext.AutoSelect {
				extName += "*"
			}
			fmt.Fprintf(w, "  %-*s  %s\n", nameW, extName, desc)
		}
	}

	// Requires
	fmt.Fprintln(w)
	if len(t.Requires) > 0 {
		fmt.Fprintf(w, "Requires: %s\n", strings.Join(t.Requires, ", "))
	} else {
		fmt.Fprintln(w, "Requires: (none)")
	}

	// Tags
	if len(t.Tags) > 0 {
		fmt.Fprintf(w, "Tags: %s\n", strings.Join(t.Tags, ", "))
	}

	// File changes
	changes := collectFileChanges(t)
	if len(changes) > 0 {
		fmt.Fprintln(w)
		fmt.Fprintln(w, "Changes:")
		for _, c := range changes {
			fmt.Fprintf(w, "  %s\n", c.label)
			if detail && c.content != "" {
				for _, line := range strings.Split(strings.TrimRight(c.content, "\n"), "\n") {
					fmt.Fprintf(w, "    | %s\n", line)
				}
			}
		}
	}
}

// FormatTemplateCat writes the raw content of a template's segments and files.
// Each section is preceded by a header line (e.g., "--- Boothfile ---").
func FormatTemplateCat(w io.Writer, t *Template) {
	changes := collectFileChanges(t)
	if len(changes) == 0 {
		return
	}
	first := true
	for _, c := range changes {
		if c.content == "" {
			continue
		}
		if !first {
			fmt.Fprintln(w)
		}
		first = false
		fmt.Fprintf(w, "--- %s ---\n", c.label)
		content := strings.TrimRight(c.content, "\n")
		fmt.Fprintln(w, content)
	}
}

// fileChange represents a file or segment that a template modifies.
type fileChange struct {
	label   string
	content string
}

// collectFileChanges gathers all segments and files from a template.
func collectFileChanges(t *Template) []fileChange {
	var changes []fileChange

	for _, seg := range t.BoothfileSegments {
		label := fmt.Sprintf("Boothfile (order %d)", seg.Order)
		changes = append(changes, fileChange{label, seg.Content})
	}
	for _, seg := range t.StartupSegments {
		label := fmt.Sprintf("startup (order %d)", seg.Order)
		changes = append(changes, fileChange{label, seg.Content})
	}
	for _, f := range t.Setups {
		label := fmt.Sprintf("setups/%s", f.RelPath)
		changes = append(changes, fileChange{label, f.Content})
	}
	for _, f := range t.Home {
		label := fmt.Sprintf("home/%s", f.RelPath)
		changes = append(changes, fileChange{label, f.Content})
	}
	for _, f := range t.HomeSeed {
		label := fmt.Sprintf("home-seed/%s", f.RelPath)
		changes = append(changes, fileChange{label, f.Content})
	}

	return changes
}

// computeNameWidth computes the max name width across all templates and extensions.
// Extension names account for the 4-character indent difference ("    + " vs "  ").
// If includeExtensions is false, only template names are considered.
func computeNameWidth(registry *TemplateRegistry, includeExtensions bool) int {
	nameWidth := 0
	for _, cat := range registry.Categories {
		for _, t := range cat.Templates {
			if len(t.Name) > nameWidth {
				nameWidth = len(t.Name)
			}
			if includeExtensions {
				for _, ext := range t.Extensions {
					extW := len(ext.Name) + 4
					if ext.AutoSelect != nil && *ext.AutoSelect {
						extW += 1
					}
					if extW > nameWidth {
						nameWidth = extW
					}
				}
			}
		}
	}
	return nameWidth
}
