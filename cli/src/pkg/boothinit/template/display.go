// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"fmt"
	"io"
	"strings"
)

// FormatRegistry writes a formatted listing of templates grouped by category.
// Templates are indented with 2 spaces; extensions with 4 spaces and a "+ " prefix.
// Columns are dynamically aligned based on content widths.
func FormatRegistry(w io.Writer, registry *TemplateRegistry) {
	if len(registry.Categories) == 0 {
		return
	}

	nameWidth, displayWidth := computeColumnWidths(registry)

	for i, cat := range registry.Categories {
		if i > 0 {
			fmt.Fprintln(w)
		}
		fmt.Fprintln(w, cat.DisplayName)
		for _, t := range cat.Templates {
			fmt.Fprintf(w, "  %-*s  %-*s  %s\n",
				nameWidth, t.Name,
				displayWidth, t.DisplayName,
				formatTags(t.Tags))
			for _, ext := range t.Extensions {
				fmt.Fprintf(w, "    + %-*s  %-*s  %s\n",
					nameWidth-4, ext.Name,
					displayWidth, ext.DisplayName,
					formatTags(ext.Tags))
			}
		}
	}
}

// formatTags formats a slice of tags as "[tag1, tag2]" or "[]" if empty.
func formatTags(tags []string) string {
	if len(tags) == 0 {
		return "[]"
	}
	return "[" + strings.Join(tags, ", ") + "]"
}

// computeColumnWidths computes the max name width and max display-name width
// across all templates and extensions in the registry. Extension names account
// for the 4-character indent difference ("    + " vs "  ").
func computeColumnWidths(registry *TemplateRegistry) (nameWidth, displayWidth int) {
	for _, cat := range registry.Categories {
		for _, t := range cat.Templates {
			if len(t.Name) > nameWidth {
				nameWidth = len(t.Name)
			}
			if len(t.DisplayName) > displayWidth {
				displayWidth = len(t.DisplayName)
			}
			for _, ext := range t.Extensions {
				// Extensions use "    + " (6 chars) vs templates "  " (2 chars),
				// so the name needs 4 extra chars to align the display-name column.
				if len(ext.Name)+4 > nameWidth {
					nameWidth = len(ext.Name) + 4
				}
				if len(ext.DisplayName) > displayWidth {
					displayWidth = len(ext.DisplayName)
				}
			}
		}
	}
	return nameWidth, displayWidth
}
