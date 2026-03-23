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
	cursorStyle      = lipgloss.NewStyle().Background(lipgloss.Color("236"))
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

func (m model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}

	fullWidth := m.width
	leftWidth := fullWidth * 55 / 100
	if leftWidth < 30 {
		leftWidth = 30
	}
	rightWidth := fullWidth - leftWidth - 3
	if rightWidth < 20 {
		rightWidth = 20
	}
	contentH := m.contentHeight()

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
		rightLines = m.renderRightPanel(rightWidth, contentH)
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

func (m model) renderTabBar() string {
	var tabs []string
	for i, name := range m.tabNames {
		label := name + " "
		if m.searchQuery != "" && i > 0 && m.tabItems[i] != nil {
			mp := &m
			if len(mp.filterItems(m.tabItems[i])) > 0 {
				label = name + boldStyle.Render("*")
			}
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
	cursor := m.cursorPos()
	scrollOff := m.tabScrollOffs[0]

	// Build all config lines (with group headers interleaved)
	type configLine struct {
		isGroup bool
		group   string
		fieldIdx int
	}
	var allLines []configLine
	lastGroup := ""
	for i, f := range allConfigFields {
		if f.Group != lastGroup {
			allLines = append(allLines, configLine{isGroup: true, group: f.Group})
			lastGroup = f.Group
		}
		allLines = append(allLines, configLine{fieldIdx: i})
	}

	// Map field index to allLines index for scrolling
	fieldToLineIdx := make([]int, len(allConfigFields))
	for li, cl := range allLines {
		if !cl.isGroup {
			fieldToLineIdx[cl.fieldIdx] = li
		}
	}

	// Determine visible start line based on scroll offset (which is a field index)
	visStart := 0
	if scrollOff >= 0 && scrollOff < len(fieldToLineIdx) {
		visStart = fieldToLineIdx[scrollOff]
	}
	// Show the group header above if the first visible field starts a new group
	if visStart > 0 && allLines[visStart-1].isGroup {
		visStart--
	}

	var lines []string

	for li := visStart; li < len(allLines) && len(lines) < contentH; li++ {
		cl := allLines[li]
		if cl.isGroup {
			groupLine := groupHeaderStyle.Render("── " + cl.group + " ──")
			lines = append(lines, padStyledRight(groupLine, leftWidth))
			continue
		}

		f := allConfigFields[cl.fieldIdx]
		isCursor := cl.fieldIdx == cursor

		var line string
		switch f.Kind {
		case fieldKindBool:
			line = m.renderBoolField(f, leftWidth, isCursor)
		case fieldKindCycle:
			line = m.renderCycleField(f, leftWidth, isCursor)
		case fieldKindString:
			line = m.renderStringField(f, leftWidth, isCursor)
		}
		lines = append(lines, line)
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

	if isCursor {
		styled := "  " + focusLabelStyle.Render(f.Label+":") + "  " + focusValueStyle.Render(" ◄ "+display+" ► ")
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
		if f.Kind == fieldKindString {
			lines = append(lines, "")
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

func (m model) renderRightPanel(rightWidth, contentH int) []string {
	var lines []string

	items := m.activeItems()
	cursor := m.cursorPos()

	if cursor >= 0 && cursor < len(items) {
		item := items[cursor]
		switch item.kind {
		case kindTemplate:
			lines = m.renderTemplateDetail(item.template, rightWidth)
		case kindExtension:
			lines = m.renderExtensionDetail(item, rightWidth)
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

	return lines
}

func (m model) renderTemplateDetail(t *tmpl.Template, width int) []string {
	var lines []string

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
			lines = m.renderParamFields(lines, item, t, width)
		} else if isSelected {
			lines = append(lines, detailLabel.Render("Parameters:")+"  "+detailLabel.Render("(Enter to edit)"))
			lines = m.renderParamValues(lines, item, t)
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

	return lines
}

func (m model) renderExtensionDetail(item treeItem, width int) []string {
	ext := item.extension
	var lines []string

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
			lines = m.renderParamFields(lines, item, ext, width)
		} else if isSelected {
			lines = append(lines, detailLabel.Render("Parameters:")+"  "+detailLabel.Render("(Enter to edit)"))
			lines = m.renderParamValues(lines, item, ext)
		} else {
			lines = append(lines, detailLabel.Render("Parameters:"))
			for _, name := range orderedParamNames(ext) {
				p := ext.Params[name]
				lines = append(lines, fmt.Sprintf("  %s = %s", name, p.Default))
			}
		}
	}

	return lines
}

func (m model) renderFooter() string {
	// Line 1: message/notification
	messageLine := ""
	if m.notification != "" {
		messageLine = " " + notifyStyle.Render(m.notification)
	}

	// Line 2: keybinding hints
	var keys string
	if m.quitting {
		keys = "  Enter: quit  │  Esc: cancel"
	} else if m.searchFocused {
		keys = "  Type to search  │  Tab/Enter/↓: go to list  │  Esc: clear  │  Ctrl+S: save  │  Ctrl+E: exit"
	} else if m.isConfigTab() {
		if m.editing {
			keys = "  Type value  │  Enter/Esc: finish  │  Backspace: delete"
		} else {
			keys = "  ↑↓: navigate  │  Space/Enter: toggle/edit  │  ◄►: tab  │  Tab: search  │  Ctrl+S: save  │  Ctrl+E: exit"
		}
	} else if m.paramEditing {
		keys = "  Type value  │  Enter/Tab: accept  │  Esc: cancel  │  Backspace: delete"
	} else if m.paramFocused {
		keys = "  ◄►: cycle  │  Enter/Type: custom value  │  ↑↓: param  │  Esc: back to list  │  Ctrl+S: save  │  Ctrl+E: exit"
	} else {
		keys = "  Space: select  │  Enter: edit params  │  ↑↓: navigate  │  ◄►: tab  │  Tab: search  │  Ctrl+S: save  │  Ctrl+E: exit"
	}
	hintsLine := footerStyle.Render(keys)

	return messageLine + "\n" + hintsLine
}

// renderParamValues renders param values as read-only (selected but not focused).
func (m model) renderParamValues(lines []string, item treeItem, t *tmpl.Template) []string {
	for _, name := range orderedParamNames(t) {
		pk := paramKey(item, name)
		val := m.paramValues[pk]
		if val == "" {
			val = t.Params[name].Default
		}
		lines = append(lines, fmt.Sprintf("  %s = %s", name, val))
	}
	return lines
}

// renderParamFields renders editable param fields in the right detail panel.
func (m model) renderParamFields(lines []string, item treeItem, t *tmpl.Template, width int) []string {
	paramNames := orderedParamNames(t)
	for i, name := range paramNames {
		p := t.Params[name]
		pk := paramKey(item, name)
		val := m.paramValues[pk]
		isFocused := i == m.paramCursorIdx

		if len(p.Suggests) > 0 && !(m.paramEditing && m.paramEditKey == pk) {
			// Cycle field with suggests
			display := val
			if display == "" {
				display = p.Default
			}
			// Check if current value is a custom value (not in suggests)
			isCustom := true
			for _, s := range p.Suggests {
				if s == display {
					isCustom = false
					break
				}
			}
			if isCustom && display != "" {
				display = display + " (custom)"
			}
			if isFocused {
				styled := "  " + focusLabelStyle.Render(name+":") + "  " + focusValueStyle.Render(" ◄ "+display+" ► ")
				lines = append(lines, styled)
			} else {
				styled := "  " + normalLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
				lines = append(lines, styled)
			}
		} else {
			// String field (no suggests, variadic, or custom edit mode)
			display := val
			if display == "" {
				display = "(empty)"
			}

			if isFocused && m.paramEditing && m.paramEditKey == pk {
				editDisplay := val + "▌"
				styled := "  " + focusLabelStyle.Render(name+":") + "  " + focusValueStyle.Render(" "+editDisplay+" ")
				lines = append(lines, styled)
			} else if isFocused {
				styled := "  " + focusLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
				lines = append(lines, styled)
			} else {
				styled := "  " + normalLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
				lines = append(lines, styled)
			}
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
