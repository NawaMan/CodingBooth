// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/nawaman/codingbooth/src/pkg/booth"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// inVariantMark fills a row's checkbox, [=], when the variant image already
// holds what the item installs: kept without being selected. "=" reads as "same
// as what you have".
const inVariantMark = "="

var inVariantStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("73"))

// currentVariant is the canonical variant the booth will run, from the Config
// tab's Variant field — so the marks follow a variant change straight away. An
// empty field is the default, base. A name booth would refuse gives "", which
// marks nothing rather than guessing.
func (m model) currentVariant() string {
	canonical, ok := booth.CanonicalVariant(m.stringFields["variant"])
	if !ok {
		return ""
	}
	return canonical
}

// inVariant reports whether the current variant's image already holds item.
func (m model) inVariant(item treeItem) bool {
	return itemTemplate(item).InVariant(m.currentVariant())
}

// renderInVariantNote returns the "already in the image" block for a detail
// panel, or nil when the current variant does not hold the item. It says what
// Space does next, since [=] cycles through three states.
func (m model) renderInVariantNote(item treeItem, width int) []string {
	if !m.inVariant(item) {
		return nil
	}
	entry := itemTemplate(item)
	variant := m.currentVariant()
	var title, body string
	switch {
	case m.selected[item.key()]:
		title = fmt.Sprintf("%s In the %s image, and selected", inVariantMark, variant)
		body = "Selecting it adds no new tool: it installs the template's own release over the image's, and whatever else the template sets up."
	case item.kind == kindTemplate && m.isRemoved(entry):
		title = fmt.Sprintf("~ Removed from the %s image", variant)
		body = fmt.Sprintf("Saving writes ~%s: the booth takes %s out of the image. Space selects the template's own release instead.", entry.Name, entry.Name)
	case item.kind == kindTemplate && entry.Removable():
		title = fmt.Sprintf("%s Already in the %s image", inVariantMark, variant)
		body = fmt.Sprintf("Kept as the image ships it. Space removes it (~%s); Space again selects the template's own release.", entry.Name)
	default:
		title = fmt.Sprintf("%s Already in the %s image", inVariantMark, variant)
		body = "Kept as the image ships it, and it cannot be removed. Selecting it installs the template's own release over the image's, and whatever else the template sets up."
	}
	lines := []string{inVariantStyle.Render(title)}
	for _, l := range wrapText(body, width) {
		lines = append(lines, detailLabel.Render(l))
	}
	return append(lines, "")
}

// isRemoved reports whether the save takes t's tool out of the image: the user
// unticked it from [=], it is not selected, it can be removed, and the current
// variant's image ships it.
func (m model) isRemoved(t *tmpl.Template) bool {
	return m.removed[t.Name] && !m.selected[t.Name] && t.Removable() && t.InVariant(m.currentVariant())
}

// checkState is a row's checkbox: [x] selected, [=] already in the image,
// [ ] neither — or removed from the image with ~name.
func (m model) checkState(item treeItem) string {
	if m.selected[item.key()] {
		return "[x]"
	}
	if !m.inVariant(item) {
		return "[ ]"
	}
	if item.kind == kindTemplate && m.isRemoved(item.template) {
		return "[ ]"
	}
	if item.kind == kindExtension && m.isRemoved(item.template) {
		return "[ ]" // its parent's tool is going, so this goes with it
	}
	return "[=]"
}

// styledCheck colours an [=] checkbox so it reads apart from [ ] and [x]. Other
// states are drawn plain, as before; the row's own style colours [x].
func (m model) styledCheck(check string) string {
	if check == "["+inVariantMark+"]" {
		return inVariantStyle.Render(check)
	}
	return check
}
