// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// Styles
var (
	headerStyle      = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	sepStyle         = lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	footerStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	boldStyle        = lipgloss.NewStyle().Bold(true)
	cursorStyle      = lipgloss.NewStyle().Background(lipgloss.Color("24")).Foreground(lipgloss.Color("255"))
	selectedStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("82"))
	detailTitle      = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("214"))
	detailLabel      = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	notifyStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("220"))
	focusLabelStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	normalLabelStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	focusValueStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("255")).Background(lipgloss.Color("24"))
	normalValueStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("255"))
	activeTabStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("255")).Background(lipgloss.Color("62")).Padding(0, 1)
	inactiveTabStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Padding(0, 1)
	groupHeaderStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("213"))
)

// warningStyle is used for the warning dialog border and text.
var (
	warningBorderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("214")).
				Bold(true)
	warningTextStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("255"))
	warningHintStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("241"))
)

// dangerStyle is used for the overwrite confirmation dialog — red, not amber,
// because this one is about to destroy work rather than merely inform.
var (
	dangerBorderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("196")).
				Bold(true)
	dangerTitleStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("231")).
				Background(lipgloss.Color("196")).
				Bold(true)
	dangerFileStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("214")).
			Bold(true)
	dangerInputStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("231")).
				Background(lipgloss.Color("52")).
				Bold(true)
	// The non-destructive choice — green, so the safe way out reads as the way out.
	safeChoiceStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("231")).
			Background(lipgloss.Color("28")).
			Bold(true)
)

// Footer buttons — how a mouse saves or leaves. Green keeps the work, red throws it
// away, grey merely asks: the colour says which is which before the label is read.
var (
	saveButtonStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("231")).
			Background(lipgloss.Color("28")).
			Bold(true)
	cancelButtonStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("231")).
				Background(lipgloss.Color("240")).
				Bold(true)
	discardButtonStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("231")).
				Background(lipgloss.Color("124")).
				Bold(true)
)

func (m model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}

	// Warning dialog overlay
	if m.warningDialog {
		return m.renderWarningDialog()
	}

	// Overwrite confirmation overlay — shown when saving would destroy hand-written files
	if m.overwriteDialog {
		return m.renderOverwriteDialog()
	}

	l := m.layout()
	fullWidth, leftWidth, rightWidth, contentH := l.fullWidth, l.leftWidth, l.rightWidth, l.contentH

	// Count selections
	selCount := 0
	for _, v := range m.selected {
		if v {
			selCount++
		}
	}

	// === Header line 1: title ===
	title := "CodingBooth Configuration"
	selInfo := fmt.Sprintf("[%d selected]", selCount)
	padding := fullWidth - lipgloss.Width(title) - lipgloss.Width(selInfo) - 2
	if padding < 1 {
		padding = 1
	}
	headerLine1 := " " + headerStyle.Render(title) + strings.Repeat(" ", padding) + headerStyle.Render(selInfo)

	// === Header line 2: search bar ===
	headerLine2 := m.renderSearchBar(fullWidth)

	// === Scroll indicator appended to header ===
	if !m.isConfigTab() {
		items := m.activeItems()
		if len(items) > contentH {
			off := m.scrollOffset()
			scrollInfo := sepStyle.Render(fmt.Sprintf("  %d-%d of %d",
				off+1, min(off+contentH, len(items)), len(items)))
			headerLine1 += scrollInfo
		}
	}

	// === Tab bar ===
	tabBar := m.renderTabBar()

	// === Separator ===
	sep := sepStyle.Render(strings.Repeat("─", fullWidth))

	// === Content panels ===
	var leftLines, rightLines []string
	if m.isConfigTab() {
		leftLines = m.renderConfigPanel(leftWidth, contentH)
		rightLines = m.renderConfigDetail(rightWidth, contentH)
	} else {
		leftLines = m.renderLeftPanel(leftWidth, contentH)
		rightLines = m.renderRightPanel(rightWidth, contentH).lines
	}

	// === Combine panels ===
	divider := sepStyle.Render(" │ ")
	var contentLines []string
	for i := 0; i < contentH; i++ {
		contentLines = append(contentLines, leftLines[i]+divider+rightLines[i])
	}

	// === Footer ===
	footer := m.renderFooter()

	return headerLine1 + "\n" + headerLine2 + "\n" + tabBar + "\n" + sep + "\n" +
		strings.Join(contentLines, "\n") + "\n" +
		sep + "\n" + footer
}

// renderTabBar draws the tab bar from tabLabels, which is also what a click is
// hit-tested against — one description of where each tab sits.
func (m model) renderTabBar() string {
	labels := m.tabLabels()
	tabs := make([]string, 0, len(labels))
	for i, t := range labels {
		label := t.name + " "
		if t.starred {
			label = t.name + boldStyle.Render("*")
		}
		if i == m.activeTab {
			tabs = append(tabs, activeTabStyle.Render(label))
		} else {
			tabs = append(tabs, inactiveTabStyle.Render(label))
		}
	}
	return " " + strings.Join(tabs, " ")
}

func (m model) renderSearchBar(fullWidth int) string {
	label := normalLabelStyle.Render(" Search:")
	boxWidth := fullWidth - lipgloss.Width(label) - 3

	query := m.searchQuery
	if boxWidth < 5 {
		boxWidth = 5
	}

	// Truncate query if too long
	displayQuery := query
	if len(displayQuery) > boxWidth-2 {
		displayQuery = displayQuery[len(displayQuery)-boxWidth+2:]
	}

	if m.searchFocused {
		content := displayQuery + "▌"
		if len(content) > boxWidth {
			content = content[len(content)-boxWidth:]
		}
		box := focusValueStyle.Render(" " + content + strings.Repeat(" ", max(0, boxWidth-len(content)-1)))
		return label + " " + box
	}

	if query == "" {
		box := sepStyle.Render(" " + strings.Repeat("·", max(0, boxWidth-1)))
		return label + " " + box
	}

	box := normalValueStyle.Render(" " + displayQuery + strings.Repeat(" ", max(0, boxWidth-len(displayQuery)-1)))
	return label + " " + box
}

// renderConfigPanel renders the left panel for the Config tab.
func (m model) renderConfigPanel(leftWidth, contentH int) []string {
	mp := &m
	rows := mp.buildConfigRows()
	cursor := m.cursorPos()
	scrollOff := m.tabScrollOffs[0]
	if scrollOff < 0 {
		scrollOff = 0
	}

	var lines []string

	for ri := scrollOff; ri < len(rows) && len(lines) < contentH; ri++ {
		row := rows[ri]
		isCursor := ri == cursor

		switch row.kind {
		case configRowGroup:
			groupLine := groupHeaderStyle.Render("── " + row.group + " ──")
			lines = append(lines, padStyledRight(groupLine, leftWidth))

		case configRowField:
			f := allConfigFields[row.fieldIdx]
			var line string
			switch f.Kind {
			case fieldKindBool:
				line = m.renderBoolField(f, leftWidth, isCursor)
			case fieldKindCycle:
				line = m.renderCycleField(f, leftWidth, isCursor)
			case fieldKindString, fieldKindInt:
				line = m.renderStringField(f, leftWidth, isCursor)
			}
			lines = append(lines, line)

		case configRowListItem:
			f := allConfigFields[row.fieldIdx]
			line := m.renderListItemField(f, row.listIndex, leftWidth, isCursor)
			lines = append(lines, line)

		case configRowListAdd:
			f := allConfigFields[row.fieldIdx]
			line := m.renderListAddRow(f, leftWidth, isCursor)
			lines = append(lines, line)
		}
	}

	for len(lines) < contentH {
		lines = append(lines, strings.Repeat(" ", leftWidth))
	}

	return lines
}

func (m model) renderBoolField(f configFieldDef, width int, isCursor bool) string {
	val := m.boolFields[f.Key]
	check := "[ ]"
	if val {
		check = "[x]"
	}
	styledName := boldStyle.Render(f.Label)
	styled := "  " + check + " " + styledName

	if isCursor {
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	if val {
		return selectedStyle.Render(padRightPlain("  "+check+" "+f.Label, width))
	}
	return padStyledRight(styled, width)
}

func (m model) renderCycleField(f configFieldDef, width int, isCursor bool) string {
	val := m.stringFields[f.Key]
	display := val
	if display == "" {
		display = "(default)"
	}

	if isCursor && m.cycleEditing {
		styled := "  " + focusLabelStyle.Render(f.Label+":") + "  " + focusValueStyle.Render(" ◄ "+display+" ► ")
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	if isCursor {
		styled := "  " + focusLabelStyle.Render(f.Label+":") + "  " + normalValueStyle.Render(display)
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	styled := "  " + normalLabelStyle.Render(f.Label+":") + "  " + normalValueStyle.Render(display)
	return padStyledRight(styled, width)
}

func (m model) renderStringField(f configFieldDef, width int, isCursor bool) string {
	val := m.stringFields[f.Key]
	display := val
	if display == "" {
		display = "(empty)"
	}

	if isCursor && m.editing {
		editDisplay := val + "▌"
		styled := "  " + focusLabelStyle.Render(f.Label+":") + "  " + focusValueStyle.Render(" "+editDisplay+" ")
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	if isCursor {
		styled := "  " + focusLabelStyle.Render(f.Label+":") + "  " + normalValueStyle.Render(display)
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	styled := "  " + normalLabelStyle.Render(f.Label+":") + "  " + normalValueStyle.Render(display)
	return padStyledRight(styled, width)
}

func (m model) renderListItemField(f configFieldDef, listIdx int, width int, isCursor bool) string {
	items := m.listFields[f.Key]
	val := ""
	if listIdx >= 0 && listIdx < len(items) {
		val = items[listIdx]
	}
	display := val
	if display == "" {
		display = "(empty)"
	}

	if isCursor && m.editing && m.listEditing && m.listEditIdx == listIdx {
		editDisplay := val + "▌"
		styled := "  " + focusLabelStyle.Render(f.Label+":") + "  " + focusValueStyle.Render(" "+editDisplay+" ")
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	if isCursor {
		styled := "  " + focusLabelStyle.Render(f.Label+":") + "  " + normalValueStyle.Render(display)
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	styled := "  " + normalLabelStyle.Render(f.Label+":") + "  " + normalValueStyle.Render(display)
	return padStyledRight(styled, width)
}

func (m model) renderListAddRow(f configFieldDef, width int, isCursor bool) string {
	styled := "  " + normalLabelStyle.Render(f.Label+":") + "  " + detailLabel.Render("(+ add new)")
	if isCursor {
		return cursorStyle.Render(padStyledRight(styled, width))
	}
	return padStyledRight(styled, width)
}

// padStyledRight pads a styled string with spaces to reach the target visual width.
func padStyledRight(s string, width int) string {
	w := lipgloss.Width(s)
	if w >= width {
		return s
	}
	return s + strings.Repeat(" ", width-w)
}

// renderConfigDetail renders the right panel for the Config tab.
func (m model) renderConfigDetail(rightWidth, contentH int) []string {
	var lines []string

	f := m.currentConfigField()
	if f != nil {
		lines = append(lines, detailTitle.Render(f.Label))
		lines = append(lines, "")

		// Render detail text, splitting on newlines
		for _, paragraph := range strings.Split(f.Detail, "\n") {
			if paragraph == "" {
				lines = append(lines, "")
			} else {
				lines = append(lines, wrapText(paragraph, rightWidth)...)
			}
		}

		// For cycle fields, show available options
		if f.Kind == fieldKindCycle {
			lines = append(lines, "")
			lines = append(lines, detailLabel.Render("Options:"))
			currentVal := m.stringFields[f.Key]
			for _, opt := range f.Options {
				display := opt
				if display == "" {
					display = "(default)"
				}
				if opt == currentVal {
					lines = append(lines, selectedStyle.Render("> "+display))
				} else {
					lines = append(lines, "  "+display)
				}
			}
			lines = append(lines, "")
			if m.cycleEditing {
				lines = append(lines, detailLabel.Render("Editing... ◄► to change, Enter to commit, Esc to cancel"))
			} else {
				lines = append(lines, detailLabel.Render("Space/Enter to edit"))
			}
		}

		// For bool fields, show current state
		if f.Kind == fieldKindBool {
			lines = append(lines, "")
			if m.boolFields[f.Key] {
				lines = append(lines, selectedStyle.Render("Currently: ON"))
			} else {
				lines = append(lines, detailLabel.Render("Currently: OFF"))
			}
			lines = append(lines, "")
			lines = append(lines, detailLabel.Render("Space/Enter to toggle"))
		}

		// For string fields, show edit hint
		if f.Kind == fieldKindString || f.Kind == fieldKindInt {
			lines = append(lines, "")
			if f.Kind == fieldKindInt {
				lines = append(lines, detailLabel.Render("Digits only."))
			}
			val := m.stringFields[f.Key]
			if val != "" {
				lines = append(lines, detailLabel.Render("Current: ")+val)
			} else {
				lines = append(lines, detailLabel.Render("Current: (empty)"))
			}
			lines = append(lines, "")
			if m.editing {
				lines = append(lines, detailLabel.Render("Editing... Enter/Esc to finish"))
			} else {
				lines = append(lines, detailLabel.Render("Space/Enter to edit"))
			}
		}

		// For list fields, show entries and hints
		if f.Kind == fieldKindList {
			items := m.listFields[f.Key]
			lines = append(lines, "")
			if len(items) > 0 {
				lines = append(lines, detailLabel.Render(fmt.Sprintf("Entries (%d):", len(items))))
				for _, item := range items {
					lines = append(lines, "  "+item)
				}
			} else {
				lines = append(lines, detailLabel.Render("No entries yet."))
			}
			lines = append(lines, "")
			mp := &m
			rows := mp.buildConfigRows()
			row := mp.currentConfigRow(rows)
			if row != nil && row.kind == configRowListItem {
				if m.editing && m.listEditing {
					lines = append(lines, detailLabel.Render("Editing... Enter/Esc to finish"))
				} else {
					lines = append(lines, detailLabel.Render("Space/Enter to edit"))
					lines = append(lines, detailLabel.Render("Delete/Backspace to remove"))
				}
			} else {
				lines = append(lines, detailLabel.Render("Space/Enter to add new entry"))
			}
		}
	}

	// Pad and truncate
	for i, line := range lines {
		w := lipgloss.Width(line)
		if w > rightWidth {
			lines[i] = line[:rightWidth]
		} else if w < rightWidth {
			lines[i] = line + strings.Repeat(" ", rightWidth-w)
		}
	}
	for len(lines) < contentH {
		lines = append(lines, strings.Repeat(" ", rightWidth))
	}
	if len(lines) > contentH {
		lines = lines[:contentH]
	}

	return lines
}

func variantDisplay(v string) string {
	if v == "" {
		return "(default)"
	}
	return v
}

func (m model) renderLeftPanel(leftWidth, contentH int) []string {
	var lines []string

	items := m.activeItems()
	off := m.scrollOffset()
	cursor := m.cursorPos()

	end := off + contentH
	if end > len(items) {
		end = len(items)
	}

	for i := off; i < end; i++ {
		item := items[i]
		isCursor := i == cursor

		switch item.kind {
		case kindTemplate:
			lines = append(lines, m.renderTemplateLine(item, leftWidth, isCursor))
		case kindExtension:
			lines = append(lines, m.renderExtensionLine(item, leftWidth, isCursor))
		}
	}

	for len(lines) < contentH {
		lines = append(lines, strings.Repeat(" ", leftWidth))
	}

	return lines
}

func (m model) renderTemplateLine(item treeItem, width int, isCursor bool) string {
	isSelected := m.selected[item.template.Name]
	check := "[ ]"
	if isSelected {
		check = "[x]"
	}

	name := item.template.Name
	desc := item.template.DisplayDesc

	plainPrefix := check + " " + name
	remaining := width - len(plainPrefix) - 2
	descStr := ""
	if remaining > 3 && len(desc) > 0 {
		if len(desc) > remaining {
			desc = desc[:remaining-2] + ".."
		}
		descStr = desc
	}

	styledName := boldStyle.Render(name)
	line := check + " " + styledName
	if descStr != "" {
		line += "  " + detailLabel.Render(descStr)
	}
	plainLen := len(plainPrefix)
	if descStr != "" {
		plainLen += 2 + len(descStr)
	}
	if plainLen < width {
		line += strings.Repeat(" ", width-plainLen)
	}

	if isCursor {
		return cursorStyle.Render(line)
	}
	if isSelected {
		return selectedStyle.Render(line)
	}
	return line
}

func (m model) renderExtensionLine(item treeItem, width int, isCursor bool) string {
	extKey := item.template.Name + "/" + item.extension.Name
	isSelected := m.selected[extKey]
	check := "[ ]"
	if isSelected {
		check = "[x]"
	}

	name := item.extension.Name
	desc := item.extension.DisplayDesc

	autoMark := ""
	if item.extension.AutoSelect != nil && *item.extension.AutoSelect {
		autoMark = "*"
	}

	plainPrefix := "    " + check + " " + autoMark + name
	remaining := width - len(plainPrefix) - 2
	descStr := ""
	if remaining > 3 && len(desc) > 0 {
		if len(desc) > remaining {
			desc = desc[:remaining-2] + ".."
		}
		descStr = desc
	}

	styledName := boldStyle.Render(autoMark + name)
	line := "    " + check + " " + styledName
	if descStr != "" {
		line += "  " + detailLabel.Render(descStr)
	}
	plainLen := len(plainPrefix)
	if descStr != "" {
		plainLen += 2 + len(descStr)
	}
	if plainLen < width {
		line += strings.Repeat(" ", width-plainLen)
	}

	if isCursor {
		return cursorStyle.Render(line)
	}
	if isSelected {
		return selectedStyle.Render(line)
	}
	return line
}

// rightPanel is what the right panel drew: the lines now on screen, and which
// param row each of those lines belongs to.
//
// The map is filled by the same pass that renders the rows and is re-keyed by the
// same scroll offset that moved them, so a click can only ever resolve to a row
// the panel is actually showing. Recomputing the layout in the mouse handler
// instead would be a second copy of this arithmetic, and the copy is what drifts.
type rightPanel struct {
	lines      []string
	paramRowAt map[int]int // screen line within the panel → index into buildParamRows
}

func (m model) renderRightPanel(rightWidth, contentH int) rightPanel {
	var lines []string
	focusLine := -1
	var rowAt map[int]int

	items := m.activeItems()
	cursor := m.cursorPos()

	if cursor >= 0 && cursor < len(items) {
		item := items[cursor]
		switch item.kind {
		case kindTemplate:
			lines, focusLine, rowAt = m.renderTemplateDetail(item.template, rightWidth)
		case kindExtension:
			lines, focusLine, rowAt = m.renderExtensionDetail(item, rightWidth)
		}
	}

	// When editing params, scroll the panel so the focused row stays visible
	// (lists of packages can exceed the panel height).
	off := 0
	if m.paramFocused && focusLine >= 0 && contentH > 0 && len(lines) > contentH {
		if focusLine >= contentH {
			off = focusLine - contentH + 1
		}
		if maxOff := len(lines) - contentH; off > maxOff {
			off = maxOff
		}
		if off > 0 {
			lines = lines[off:]
		}
	}

	for i, line := range lines {
		w := lipgloss.Width(line)
		if w > rightWidth {
			lines[i] = line[:rightWidth]
		} else if w < rightWidth {
			lines[i] = line + strings.Repeat(" ", rightWidth-w)
		}
	}
	for len(lines) < contentH {
		lines = append(lines, strings.Repeat(" ", rightWidth))
	}
	if len(lines) > contentH {
		lines = lines[:contentH]
	}

	// Re-key the row map onto the lines that survived scrolling and truncation.
	visible := make(map[int]int, len(rowAt))
	for line, row := range rowAt {
		if screen := line - off; screen >= 0 && screen < len(lines) {
			visible[screen] = row
		}
	}
	return rightPanel{lines: lines, paramRowAt: visible}
}

// renderTemplateDetail draws a template's detail panel. It returns the lines, the
// index of the focused param row (or -1), and which line each param row occupies.
func (m model) renderTemplateDetail(t *tmpl.Template, width int) ([]string, int, map[int]int) {
	var lines []string
	focusLine := -1
	var rowAt map[int]int

	lines = append(lines, detailTitle.Render(t.DisplayName))
	lines = append(lines, detailLabel.Render(t.CategoryName))
	lines = append(lines, "")

	if t.DisplayDesc != "" {
		lines = append(lines, wrapText(t.DisplayDesc, width)...)
		lines = append(lines, "")
	}

	if t.DisplayDetail != "" {
		lines = append(lines, wrapText(t.DisplayDetail, width)...)
	}

	if len(t.Params) > 0 {
		item := treeItem{kind: kindTemplate, template: t}
		isSelected := m.selected[t.Name]
		lines = append(lines, "")
		if isSelected && m.paramFocused {
			lines = append(lines, detailLabel.Render("Parameters:")+"  "+detailLabel.Render("(editing)"))
			lines, focusLine, rowAt = m.renderParamFields(lines, item, t, width)
		} else if isSelected {
			lines = append(lines, detailLabel.Render("Parameters:")+"  "+detailLabel.Render("(Enter to edit)"))
			lines, rowAt = m.renderParamValues(lines, item, t)
		} else {
			lines = append(lines, detailLabel.Render("Parameters:"))
			for _, name := range orderedParamNames(t) {
				p := t.Params[name]
				lines = append(lines, fmt.Sprintf("  %s = %s", name, p.Default))
				if len(p.Suggests) > 0 {
					lines = append(lines, fmt.Sprintf("    options: %s", strings.Join(p.Suggests, ", ")))
				}
			}
		}
	}

	if len(t.Requires) > 0 {
		lines = append(lines, "")
		lines = append(lines, detailLabel.Render("Requires:"))
		lines = append(lines, fmt.Sprintf("  %s", strings.Join(t.Requires, ", ")))
	}

	if len(t.Extensions) > 0 {
		lines = append(lines, "")
		lines = append(lines, detailLabel.Render("Extensions:"))
		for _, ext := range t.Extensions {
			marker := "  "
			if ext.AutoSelect != nil && *ext.AutoSelect {
				marker = "* "
			}
			desc := ext.DisplayDesc
			if desc == "" {
				desc = ext.DisplayName
			}
			lines = append(lines, fmt.Sprintf("  %s%s - %s", marker, ext.Name, desc))
		}
	}

	return lines, focusLine, rowAt
}

// renderExtensionDetail draws an extension's detail panel, with the same param-row
// line map renderTemplateDetail returns.
func (m model) renderExtensionDetail(item treeItem, width int) ([]string, int, map[int]int) {
	ext := item.extension
	var lines []string
	focusLine := -1
	var rowAt map[int]int

	lines = append(lines, detailTitle.Render(ext.DisplayName))
	lines = append(lines, detailLabel.Render(fmt.Sprintf("Extension of %s", item.template.Name)))
	lines = append(lines, "")

	if ext.DisplayDesc != "" {
		lines = append(lines, wrapText(ext.DisplayDesc, width)...)
		lines = append(lines, "")
	}

	if ext.DisplayDetail != "" {
		lines = append(lines, wrapText(ext.DisplayDetail, width)...)
	}

	if ext.AutoSelect != nil && *ext.AutoSelect {
		lines = append(lines, "")
		lines = append(lines, detailLabel.Render("Auto-selected with parent"))
	}

	if len(ext.Requires) > 0 {
		lines = append(lines, "")
		lines = append(lines, detailLabel.Render("Requires:"))
		lines = append(lines, fmt.Sprintf("  %s", strings.Join(ext.Requires, ", ")))
	}

	if len(ext.Params) > 0 {
		extKey := item.template.Name + "/" + ext.Name
		isSelected := m.selected[extKey]
		lines = append(lines, "")
		if isSelected && m.paramFocused {
			lines = append(lines, detailLabel.Render("Parameters:")+"  "+detailLabel.Render("(editing)"))
			lines, focusLine, rowAt = m.renderParamFields(lines, item, ext, width)
		} else if isSelected {
			lines = append(lines, detailLabel.Render("Parameters:")+"  "+detailLabel.Render("(Enter to edit)"))
			lines, rowAt = m.renderParamValues(lines, item, ext)
		} else {
			lines = append(lines, detailLabel.Render("Parameters:"))
			for _, name := range orderedParamNames(ext) {
				p := ext.Params[name]
				lines = append(lines, fmt.Sprintf("  %s = %s", name, p.Default))
			}
		}
	}

	return lines, focusLine, rowAt
}

func (m model) renderFooter() string {
	// Line 1: message/notification
	messageLine := ""
	if m.notification != "" {
		messageLine = " " + notifyStyle.Render(m.notification)
	}

	// Line 2: keybinding hints, with the footer buttons flush right. Ctrl+S and
	// Ctrl+E are no longer spelled out here — the buttons carry both the action and
	// its key, and repeating them only crowded the row.
	var keys string
	if m.quitting {
		keys = "  Enter: quit  │  Esc: cancel"
	} else if m.searchFocused {
		keys = "  Type to search  │  Tab/Enter/↓: go to list  │  Esc: clear"
	} else if m.isConfigTab() {
		if m.editing {
			keys = "  Type value  │  Enter/Esc: finish  │  Backspace: delete"
		} else if m.cycleEditing {
			keys = "  ◄►: change  │  Enter: commit  │  Esc: cancel"
		} else {
			mp := &m
			rows := mp.buildConfigRows()
			row := mp.currentConfigRow(rows)
			if row != nil && row.kind == configRowListItem {
				keys = "  ↑↓: navigate  │  Space/Enter: edit  │  Del/BS: remove  │  ◄►: tab"
			} else if row != nil && row.kind == configRowListAdd {
				keys = "  ↑↓: navigate  │  Space/Enter: add new  │  ◄►: tab"
			} else {
				keys = "  ↑↓: navigate  │  Space/Enter: toggle/edit  │  ◄►: tab  │  Tab: search"
			}
		}
	} else if m.variadicEditing {
		keys = "  Type value  │  Enter: accept  │  Esc: cancel  │  Backspace: delete"
	} else if m.paramEditing {
		keys = "  Type value  │  Enter/Tab: accept  │  Esc: cancel  │  Backspace: delete"
	} else if m.paramFocused {
		mp := &m
		if row, ok := mp.currentParamRow(); ok && row.kind == paramRowVariadicValue {
			keys = "  ↑↓: navigate  │  Space/Enter: edit  │  Del/BS: remove  │  Esc: back"
		} else if ok && row.kind == paramRowVariadicAdd {
			keys = "  ↑↓: navigate  │  Space/Enter: add new  │  Esc: back"
		} else {
			keys = "  ◄►: cycle  │  Enter/Type: custom value  │  ↑↓: param  │  Esc: back to list"
		}
	} else {
		keys = "  Space: select  │  Enter: edit params  │  ↑↓: navigate  │  ◄►: tab  │  Tab: search"
	}

	return messageLine + "\n" + m.renderFooterHints(keys)
}

// renderFooterHints lays the key hints from the left and the buttons flush right.
//
// When the two would collide the hints give way: every hint has a key behind it
// that works whether or not it is on screen, while the buttons are the only way a
// mouse can save or leave.
func (m model) renderFooterHints(keys string) string {
	buttons := m.footerButtons()
	if len(buttons) == 0 {
		return footerStyle.Render(keys)
	}

	// Cutting the hints mid-list leaves the separator that was introducing the hint
	// that no longer fits; drop it rather than trail a "│" into empty space.
	keys = strings.TrimRight(truncateCols(keys, buttons[0].start-1), " │")
	line := footerStyle.Render(keys)
	col := lipgloss.Width(keys)
	for _, b := range buttons {
		if b.start > col {
			line += strings.Repeat(" ", b.start-col)
			col = b.start
		}
		line += b.style().Render(b.label)
		col += b.width
	}
	return line
}

// truncateCols cuts s to at most cols columns, on a rune boundary — the hints hold
// "│" and "◄►", so cutting bytes would leave a broken rune on screen.
func truncateCols(s string, cols int) string {
	if cols <= 0 {
		return ""
	}
	if lipgloss.Width(s) <= cols {
		return s
	}
	out := make([]rune, 0, cols)
	width := 0
	for _, r := range s {
		w := lipgloss.Width(string(r))
		if width+w > cols {
			break
		}
		out = append(out, r)
		width += w
	}
	return string(out)
}

// renderParamValues renders param values as read-only (selected but not focused),
// and reports which param row each line stands for.
//
// A click has to be able to *enter* the editor, not only move around inside one,
// so these lines are clickable too: one line per param, pointing at that param's
// first row — the value row of a single-value param, the first entry (or the add
// row) of a package list.
func (m model) renderParamValues(lines []string, item treeItem, t *tmpl.Template) ([]string, map[int]int) {
	rows := m.buildParamRows(item, t)
	firstRow := make(map[string]int, len(rows))
	for i, row := range rows {
		if _, seen := firstRow[row.param]; !seen {
			firstRow[row.param] = i
		}
	}

	rowAt := make(map[int]int, len(rows))
	for _, name := range orderedParamNames(t) {
		pk := paramKey(item, name)
		val := m.paramValues[pk]
		if val == "" {
			val = t.Params[name].Default
		}
		display, follows := m.paramDisplay(val)
		if row, ok := firstRow[name]; ok {
			rowAt[len(lines)] = row
		}
		lines = append(lines, fmt.Sprintf("  %s = %s%s", name, display, followsHint(follows)))
	}
	return lines, rowAt
}

// renderParamFields renders editable param fields in the right detail panel.
// Single-value params render as one row; a variadic param renders as a label
// header followed by one row per value plus a trailing "(+ add)" row.
//
// It returns the appended lines, the absolute line index of the focused row (or -1
// if nothing is focused) so the caller can scroll it into view, and which line
// each row landed on so a click can find it.
func (m model) renderParamFields(lines []string, item treeItem, t *tmpl.Template, width int) ([]string, int, map[int]int) {
	rows := m.buildParamRows(item, t)
	focusLine := -1
	rowAt := make(map[int]int, len(rows))
	for i, row := range rows {
		isFocused := i == m.paramCursorIdx
		pk := paramKey(item, row.param)

		switch row.kind {
		case paramRowField:
			if isFocused {
				focusLine = len(lines)
			}
			rowAt[len(lines)] = i
			lines = append(lines, m.renderParamFieldRow(t, row.param, pk, isFocused))

		case paramRowVariadicValue:
			// Label header before the first value of this param.
			if i == 0 || rows[i-1].param != row.param {
				lines = append(lines, "  "+normalLabelStyle.Render(row.param+":"))
			}
			vals := m.splitVariadic(pk)
			text := ""
			if row.valueIdx < len(vals) {
				text = vals[row.valueIdx]
			}
			if isFocused {
				focusLine = len(lines)
			}
			rowAt[len(lines)] = i
			if isFocused && m.variadicEditing && !m.variadicEditIsNew && m.variadicEditIdx == row.valueIdx {
				lines = append(lines, "      "+focusValueStyle.Render(" "+m.variadicEditBuf+"▌ "))
			} else if isFocused {
				lines = append(lines, "    "+cursorStyle.Render("• "+text))
			} else {
				lines = append(lines, "    "+normalValueStyle.Render("• "+text))
			}

		case paramRowVariadicAdd:
			// Label header when the list is empty (no value rows preceded this).
			if i == 0 || rows[i-1].param != row.param {
				lines = append(lines, "  "+normalLabelStyle.Render(row.param+":"))
			}
			if isFocused {
				focusLine = len(lines)
			}
			rowAt[len(lines)] = i
			if isFocused && m.variadicEditing && m.variadicEditIsNew {
				lines = append(lines, "      "+focusValueStyle.Render(" "+m.variadicEditBuf+"▌ "))
			} else if isFocused {
				lines = append(lines, "    "+cursorStyle.Render("(+ add)"))
			} else {
				lines = append(lines, "    "+detailLabel.Render("(+ add)"))
			}
		}
	}
	return lines, focusLine, rowAt
}

// renderParamFieldRow renders a single (non-variadic) param row.
func (m model) renderParamFieldRow(t *tmpl.Template, name, pk string, isFocused bool) string {
	p := t.Params[name]
	val := m.paramValues[pk]

	if len(p.Suggests) > 0 && !(m.paramEditing && m.paramEditKey == pk) {
		display := m.cycleParamDisplay(t, name, pk)
		if isFocused {
			return "  " + focusLabelStyle.Render(name+":") + "  " + focusValueStyle.Render(cycleArrowsAround(display))
		}
		return "  " + normalLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
	}

	// String field (no suggests, or custom edit mode)
	display, follows := m.paramDisplay(val)
	if display == "" {
		display = "(empty)"
	}
	display += followsHint(follows)
	// Editing shows the raw value, so a "${SVC_PORT}" reference stays visible and
	// editable — typing over it is an explicit, deliberate pin.
	if isFocused && m.paramEditing && m.paramEditKey == pk {
		return "  " + focusLabelStyle.Render(name+":") + "  " + focusValueStyle.Render(" "+val+"▌ ")
	}
	if isFocused {
		return "  " + focusLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
	}
	return "  " + normalLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
}

// renderOverwriteDialog renders the confirmation shown when saving would destroy
// hand-written files. It names every file at risk and will not proceed until the
// user has typed the confirmation word in full.
func (m model) renderOverwriteDialog() string {
	boxWidth := m.width * 70 / 100
	if boxWidth < 50 {
		boxWidth = 50
	}
	if boxWidth > m.width-4 {
		boxWidth = m.width - 4
	}
	inner := boxWidth - 2
	innerWidth := boxWidth - 4

	// left-aligned line inside the box
	line := func(s string) string {
		return dangerBorderStyle.Render("│") + padStyledRight(" "+s, inner) + dangerBorderStyle.Render("│")
	}
	blank := func() string {
		return dangerBorderStyle.Render("│") + strings.Repeat(" ", inner) + dangerBorderStyle.Render("│")
	}
	centered := func(s string) string {
		return dangerBorderStyle.Render("│") + centerPad(s, inner) + dangerBorderStyle.Render("│")
	}

	var dl []string
	dl = append(dl, dangerBorderStyle.Render("┌"+strings.Repeat("─", inner)+"┐"))
	dl = append(dl, centered(dangerTitleStyle.Render("  ⚠  THESE FILES ARE HAND-WRITTEN  ⚠  ")))
	dl = append(dl, blank())

	for _, l := range wrapText("Saving regenerates .booth/ from your selection. These files were not written by booth config — or were edited afterwards — so saving over them would destroy that work:", innerWidth) {
		dl = append(dl, line(warningTextStyle.Render(l)))
	}
	dl = append(dl, blank())
	for _, name := range m.drifted {
		dl = append(dl, line("  "+dangerFileStyle.Render(".booth/"+name)))
	}
	dl = append(dl, blank())

	// The safe way out, offered first and bound to the bare Enter key.
	dl = append(dl, line(safeChoiceStyle.Render(" ENTER ")+"  "+warningTextStyle.Render("Keep them. Write what I generated beside them:")))
	for _, name := range m.drifted {
		dl = append(dl, line("         "+dangerFileStyle.Render(".booth/"+name+".new")))
	}
	for _, l := range wrapText("Nothing is destroyed — you merge the two by hand.", innerWidth-9) {
		dl = append(dl, line("         "+warningHintStyle.Render(l)))
	}
	dl = append(dl, blank())

	// The destructive way out, gated behind typing the word in full.
	for _, l := range wrapText("To replace them instead (a .bak is kept), type \""+overwriteConfirmWord+"\" and press Enter:", innerWidth) {
		dl = append(dl, line(warningTextStyle.Render(l)))
	}

	// Input field with cursor
	field := m.overwriteInput + "█"
	pad := len(overwriteConfirmWord) + 4 - len([]rune(field))
	if pad > 0 {
		field += strings.Repeat(" ", pad)
	}
	dl = append(dl, line("  "+dangerInputStyle.Render(" "+field+" ")))
	dl = append(dl, blank())

	hint := "Enter: keep mine, write .new  │  Esc: back out  │  Ctrl+C: quit"
	dl = append(dl, centered(warningHintStyle.Render(hint)))
	dl = append(dl, dangerBorderStyle.Render("└"+strings.Repeat("─", inner)+"┘"))

	// Center the box
	topPad := (m.height - len(dl)) / 2
	if topPad < 0 {
		topPad = 0
	}
	leftPad := (m.width - boxWidth) / 2
	if leftPad < 0 {
		leftPad = 0
	}
	prefix := strings.Repeat(" ", leftPad)

	var lines []string
	for i := 0; i < topPad; i++ {
		lines = append(lines, "")
	}
	for _, l := range dl {
		lines = append(lines, prefix+l)
	}
	return strings.Join(lines, "\n")
}

// renderWarningDialog renders a centered warning dialog overlay.
func (m model) renderWarningDialog() string {
	// Dialog box dimensions
	boxWidth := m.width * 60 / 100
	if boxWidth < 40 {
		boxWidth = 40
	}
	if boxWidth > m.width-4 {
		boxWidth = m.width - 4
	}
	innerWidth := boxWidth - 4 // 2 border + 2 padding

	// Build dialog content
	title := "⚠ Warning"
	msgLines := wrapParagraphs(m.warningMessage, innerWidth)
	hint := "Enter/Space: continue  │  Esc: quit"

	// Dialog lines: border top, title, blank, message lines, blank, hint, border bottom
	var dialogLines []string
	dialogLines = append(dialogLines, warningBorderStyle.Render("┌"+strings.Repeat("─", boxWidth-2)+"┐"))
	dialogLines = append(dialogLines, warningBorderStyle.Render("│")+centerPad(warningBorderStyle.Render(title), boxWidth-2)+warningBorderStyle.Render("│"))
	dialogLines = append(dialogLines, warningBorderStyle.Render("│")+strings.Repeat(" ", boxWidth-2)+warningBorderStyle.Render("│"))
	for _, line := range msgLines {
		padded := " " + warningTextStyle.Render(line)
		padded = padStyledRight(padded, boxWidth-2)
		dialogLines = append(dialogLines, warningBorderStyle.Render("│")+padded+warningBorderStyle.Render("│"))
	}
	dialogLines = append(dialogLines, warningBorderStyle.Render("│")+strings.Repeat(" ", boxWidth-2)+warningBorderStyle.Render("│"))
	dialogLines = append(dialogLines, warningBorderStyle.Render("│")+centerPad(warningHintStyle.Render(hint), boxWidth-2)+warningBorderStyle.Render("│"))
	dialogLines = append(dialogLines, warningBorderStyle.Render("└"+strings.Repeat("─", boxWidth-2)+"┘"))

	dialogHeight := len(dialogLines)

	// Center vertically
	topPad := (m.height - dialogHeight) / 2
	if topPad < 0 {
		topPad = 0
	}
	bottomPad := m.height - topPad - dialogHeight
	if bottomPad < 0 {
		bottomPad = 0
	}

	// Center horizontally
	leftPad := (m.width - boxWidth) / 2
	if leftPad < 0 {
		leftPad = 0
	}
	prefix := strings.Repeat(" ", leftPad)

	var lines []string
	for i := 0; i < topPad; i++ {
		lines = append(lines, "")
	}
	for _, dl := range dialogLines {
		lines = append(lines, prefix+dl)
	}
	for i := 0; i < bottomPad; i++ {
		lines = append(lines, "")
	}

	return strings.Join(lines, "\n")
}

// centerPad centers styled text within a given width, padding with spaces.
func centerPad(s string, width int) string {
	w := lipgloss.Width(s)
	if w >= width {
		return s
	}
	left := (width - w) / 2
	right := width - w - left
	return strings.Repeat(" ", left) + s + strings.Repeat(" ", right)
}

// wrapParagraphs wraps text to width while honouring the newlines already in it,
// so a message can carry blank lines and its own short lines (e.g. a file list).
// wrapText alone collapses every run of whitespace, newlines included, which
// flattens a structured message into one blob.
func wrapParagraphs(text string, width int) []string {
	var lines []string
	for _, para := range strings.Split(text, "\n") {
		if strings.TrimSpace(para) == "" {
			lines = append(lines, "")
			continue
		}
		// Keep any leading indent — wrapText drops it, which would flatten an
		// indented file list back into flush-left prose.
		indent := para[:len(para)-len(strings.TrimLeft(para, " "))]
		for _, l := range wrapText(para, width-len(indent)) {
			lines = append(lines, indent+l)
		}
	}
	return lines
}

func wrapText(text string, width int) []string {
	if width <= 0 {
		return []string{text}
	}
	words := strings.Fields(text)
	if len(words) == 0 {
		return nil
	}
	var lines []string
	current := words[0]
	for _, word := range words[1:] {
		if len(current)+1+len(word) > width {
			lines = append(lines, current)
			current = word
		} else {
			current += " " + word
		}
	}
	lines = append(lines, current)
	return lines
}

func padRightPlain(s string, width int) string {
	if len(s) >= width {
		return s[:width]
	}
	return s + strings.Repeat(" ", width-len(s))
}
