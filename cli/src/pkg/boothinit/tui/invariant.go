// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/nawaman/codingbooth/src/pkg/booth"
)

// inVariantMark is drawn in a row's marker slot when the variant image already
// holds what the template installs. "=" reads as "same as what you have": the
// tool is there, and selecting it only swaps in the template's own release.
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
// panel, or nil when the current variant does not hold the item.
func (m model) renderInVariantNote(item treeItem, width int) []string {
	if !m.inVariant(item) {
		return nil
	}
	var lines []string
	lines = append(lines, inVariantStyle.Render(fmt.Sprintf("%s Already in the %s image", inVariantMark, m.currentVariant())))
	for _, l := range wrapText("Selecting it adds no new tool: it installs the template's own release over the image's, and whatever else the template sets up.", width) {
		lines = append(lines, detailLabel.Render(l))
	}
	lines = append(lines, "")
	return lines
}
