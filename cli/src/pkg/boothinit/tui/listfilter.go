// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"github.com/charmbracelet/lipgloss"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// listFilter is the exclusive view chip on the search row. Category tabs still
// partition the catalog; these chips answer how much of the active tab to show.
type listFilter int

const (
	listFilterAll listFilter = iota
	listFilterPopular
	listFilterLocal
	listFilterSelected
)

func (filter listFilter) label() string {
	switch filter {
	case listFilterPopular:
		return "Popular"
	case listFilterLocal:
		return "Local"
	case listFilterSelected:
		return "Selected"
	default:
		return "All"
	}
}

// keyDigit is the keyboard shortcut for this chip. Stable across whether
// Local is shown, so Selected is always 3.
func (filter listFilter) keyDigit() string {
	switch filter {
	case listFilterPopular:
		return "2"
	case listFilterSelected:
		return "3"
	case listFilterLocal:
		return "4"
	default:
		return "1"
	}
}

func (filter listFilter) chipName() string {
	return filter.keyDigit() + " " + filter.label()
}

func (m model) visibleFilters() []listFilter {
	filters := []listFilter{listFilterAll, listFilterPopular, listFilterSelected}
	if m.hasLocal {
		filters = append(filters, listFilterLocal)
	}
	return filters
}

// applyListFilter keeps the tree items that belong to the active chip.
// Search is applied separately and, when the query is non-empty, replaces this
// filter so typing can still find a hidden template.
func (m *model) applyListFilter(items []treeItem) []treeItem {
	if m.listFilter == listFilterAll || len(items) == 0 {
		return items
	}

	parentKept := make(map[string]bool)
	for _, item := range items {
		if item.kind != kindTemplate {
			continue
		}
		if m.templatePassesFilter(item.template) {
			parentKept[item.template.Name] = true
		}
	}
	// Popular and Selected both keep a parent that has a picked extension,
	// so a current pick never vanishes from the list.
	if m.listFilter == listFilterSelected || m.listFilter == listFilterPopular {
		for _, item := range items {
			if item.kind == kindExtension && m.selected[item.key()] {
				parentKept[item.template.Name] = true
			}
		}
	}

	var result []treeItem
	for _, item := range items {
		switch item.kind {
		case kindTemplate:
			if parentKept[item.template.Name] {
				result = append(result, item)
			}
		case kindExtension:
			if !parentKept[item.template.Name] {
				continue
			}
			// A selected parent keeps every extension so they can still be
			// toggled. An unselected parent that is only here because an
			// extension is selected keeps that extension alone.
			if m.listFilter == listFilterSelected && !m.selected[item.template.Name] && !m.selected[item.key()] {
				continue
			}
			result = append(result, item)
		}
	}
	return result
}

func (m *model) templatePassesFilter(t *tmpl.Template) bool {
	if t == nil {
		return false
	}
	switch m.listFilter {
	case listFilterPopular:
		// Primaries plus anything already picked — reopening a booth that
		// selected kotlin still shows kotlin on Languages.
		return t.Primary || m.selected[t.Name]
	case listFilterLocal:
		return t.Local
	case listFilterSelected:
		return m.selected[t.Name]
	default:
		return true
	}
}

// chipLabel is one filter chip on the search row and the columns it occupies.
type chipLabel struct {
	filter listFilter
	name   string
	start  int
	width  int
}

// chipLabels returns the chips flush against the right of the search row.
// renderSearchBar draws from this and a click is hit-tested against it.
// Config has no list to filter, so the chips stay off that tab — the search
// box then keeps the full width it had before this row grew a second widget.
func (m model) chipLabels() []chipLabel {
	if m.activeTab == 0 || m.width == 0 {
		return nil
	}
	filters := m.visibleFilters()
	if len(filters) == 0 {
		return nil
	}

	const gap = 1
	labels := make([]chipLabel, len(filters))
	total := gap * (len(filters) - 1)
	for index, filter := range filters {
		labels[index].filter = filter
		labels[index].name = filter.chipName()
		labels[index].width = lipgloss.Width(inactiveTabStyle.Render(labels[index].name))
		total += labels[index].width
	}

	// Search: + space + a usable box + a right margin. Too narrow to place the
	// chips is not a reason to draw them on top of the query.
	const minSearchBox = 8
	col := m.width - total - 1
	minCol := lipgloss.Width(" Search:") + 1 + minSearchBox + 1
	if col < minCol {
		return nil
	}
	for index := range labels {
		labels[index].start = col
		col += labels[index].width + gap
	}
	return labels
}

func (m model) chipAt(x int) (listFilter, bool) {
	for _, chip := range m.chipLabels() {
		if x >= chip.start && x < chip.start+chip.width {
			return chip.filter, true
		}
	}
	return 0, false
}

func (m model) renderChip(chip chipLabel) string {
	active := chip.filter == m.listFilter
	searching := m.searchQuery != ""
	var style lipgloss.Style
	switch {
	case active:
		style = activeTabStyle
	case searching:
		style = footerStyle.Padding(0, 1)
	default:
		style = inactiveTabStyle
	}
	return style.Render(chip.name)
}
