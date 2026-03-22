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

	// === Header ===
	title := "CodingBooth Configuration"
	selInfo := fmt.Sprintf("[%d selected]", selCount)
	padding := fullWidth - lipgloss.Width(title) - lipgloss.Width(selInfo) - 2
	if padding < 1 {
		padding = 1
	}
	header := " " + headerStyle.Render(title) + strings.Repeat(" ", padding) + headerStyle.Render(selInfo)

	// === Config bar ===
	configBar := m.renderConfigBar(fullWidth)

	// === Tab bar ===
	tabBar := m.renderTabBar(fullWidth)

	// === Separator ===
	sep := sepStyle.Render(strings.Repeat("─", fullWidth))

	// === Left panel ===
	leftLines := m.renderLeftPanel(leftWidth, contentH)

	// === Right panel ===
	rightLines := m.renderRightPanel(rightWidth, contentH)

	// === Combine panels ===
	divider := sepStyle.Render(" │ ")
	var contentLines []string
	for i := 0; i < contentH; i++ {
		contentLines = append(contentLines, leftLines[i]+divider+rightLines[i])
	}

	// === Footer ===
	footer := m.renderFooter(fullWidth)

	// === Scroll indicator in header ===
	items := m.activeItems()
	if len(items) > contentH {
		off := m.scrollOffset()
		scrollInfo := sepStyle.Render(fmt.Sprintf("  %d-%d of %d",
			off+1, min(off+contentH, len(items)), len(items)))
		header += scrollInfo
	}

	return header + "\n" + configBar + "\n" + tabBar + "\n" + sep + "\n" +
		strings.Join(contentLines, "\n") + "\n" +
		sep + "\n" + footer
}

func (m model) renderTabBar(fullWidth int) string {
	var tabs []string
	for i, name := range m.tabNames {
		label := fmt.Sprintf("%s (%d)", name, i+1)
		if i == m.activeTab {
			tabs = append(tabs, activeTabStyle.Render(label))
		} else {
			tabs = append(tabs, inactiveTabStyle.Render(label))
		}
	}
	return " " + strings.Join(tabs, " ")
}

func (m model) renderConfigBar(fullWidth int) string {
	// Variant field
	varLabel := normalLabelStyle.Render("Variant:")
	varValue := normalValueStyle.Render(variantDisplay(m.variant))
	if m.focus == focusVariant {
		varLabel = focusLabelStyle.Render("Variant:")
		varValue = focusValueStyle.Render(" ◄ " + variantDisplay(m.variant) + " ► ")
	}

	// Port field
	portLabel := normalLabelStyle.Render("Port:")
	portValue := normalValueStyle.Render(m.port)
	if m.focus == focusPort {
		portLabel = focusLabelStyle.Render("Port:")
		if m.portEditing {
			portValue = focusValueStyle.Render(m.port + "▌")
		} else {
			portValue = focusValueStyle.Render(" " + m.port + " ")
		}
	}

	return " " + varLabel + " " + varValue + "    " + portLabel + " " + portValue
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
		isCursor := i == cursor && m.focus == focusTree

		switch item.kind {
		case kindTemplate:
			line := m.renderTemplateLine(item, leftWidth, isCursor)
			lines = append(lines, line)

		case kindExtension:
			line := m.renderExtensionLine(item, leftWidth, isCursor)
			lines = append(lines, line)
		}
	}

	// Pad remaining lines
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

	plain := check + " " + name
	remaining := width - len(plain) - 2
	if remaining > 3 && len(desc) > 0 {
		if len(desc) > remaining {
			desc = desc[:remaining-2] + ".."
		}
		plain += "  " + desc
	}
	plain = padRightPlain(plain, width)

	if isCursor {
		return cursorStyle.Render(plain)
	}
	if isSelected {
		return selectedStyle.Render(plain)
	}
	return plain
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

	// Mark auto-select
	autoMark := ""
	if item.extension.AutoSelect != nil && *item.extension.AutoSelect {
		autoMark = "*"
	}

	plain := "    " + check + " " + autoMark + name
	remaining := width - len(plain) - 2
	if remaining > 3 && len(desc) > 0 {
		if len(desc) > remaining {
			desc = desc[:remaining-2] + ".."
		}
		plain += "  " + desc
	}
	plain = padRightPlain(plain, width)

	if isCursor {
		return cursorStyle.Render(plain)
	}
	if isSelected {
		return selectedStyle.Render(plain)
	}
	return plain
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

func (m model) renderTemplateDetail(t *tmpl.Template, width int) []string {
	var lines []string

	lines = append(lines, detailTitle.Render(t.DisplayName))
	lines = append(lines, detailLabel.Render(t.CategoryName))
	lines = append(lines, "")

	if t.DisplayDesc != "" {
		for _, l := range wrapText(t.DisplayDesc, width) {
			lines = append(lines, l)
		}
		lines = append(lines, "")
	}

	if t.DisplayDetail != "" {
		for _, l := range wrapText(t.DisplayDetail, width) {
			lines = append(lines, l)
		}
	}

	if len(t.Params) > 0 {
		lines = append(lines, "")
		lines = append(lines, detailLabel.Render("Parameters:"))
		for _, name := range orderedParamNames(t) {
			p := t.Params[name]
			lines = append(lines, fmt.Sprintf("  %s = %s", name, p.Default))
			if len(p.Suggests) > 0 {
				lines = append(lines, fmt.Sprintf("    options: %s", strings.Join(p.Suggests, ", ")))
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
		for _, l := range wrapText(ext.DisplayDesc, width) {
			lines = append(lines, l)
		}
		lines = append(lines, "")
	}

	if ext.DisplayDetail != "" {
		for _, l := range wrapText(ext.DisplayDetail, width) {
			lines = append(lines, l)
		}
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
		lines = append(lines, "")
		lines = append(lines, detailLabel.Render("Parameters:"))
		for _, name := range orderedParamNames(ext) {
			p := ext.Params[name]
			lines = append(lines, fmt.Sprintf("  %s = %s", name, p.Default))
		}
	}

	return lines
}

func (m model) renderFooter(fullWidth int) string {
	// Line 1: message/notification
	messageLine := ""
	if m.notification != "" {
		messageLine = " " + notifyStyle.Render(m.notification)
	}

	// Line 2: keybinding hints
	var keys string
	if m.quitting {
		keys = "  Enter: quit  │  Esc: cancel"
	} else {
		keys = "  Space: select  │  ↑↓: navigate  │  ◄►: tab  │  Tab: config  │  Ctrl+S: save  │  Ctrl+Q: quit"
		switch m.focus {
		case focusVariant:
			keys = "  ◄►: change variant  │  Tab: next field  │  Ctrl+S: save  │  Ctrl+Q: quit"
		case focusPort:
			if m.portEditing {
				keys = "  Type port number  │  Enter: confirm  │  Esc: cancel"
			} else {
				keys = "  Enter: edit port  │  Tab: next field  │  Ctrl+S: save  │  Ctrl+Q: quit"
			}
		}
	}
	hintsLine := footerStyle.Render(keys)

	return messageLine + "\n" + hintsLine
}

// orderedParamNames returns param names in declaration order.
func orderedParamNames(t *tmpl.Template) []string {
	if len(t.ParamOrder) > 0 {
		return t.ParamOrder
	}
	names := make([]string, 0, len(t.Params))
	for name := range t.Params {
		names = append(names, name)
	}
	return names
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
