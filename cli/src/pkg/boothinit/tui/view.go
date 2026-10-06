// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/aptsnapshot"
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
	fieldErrStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("203"))
	focusLabelStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	normalLabelStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	focusValueStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("255")).Background(lipgloss.Color("24"))
	normalValueStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("255"))
	activeTabStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("255")).Background(lipgloss.Color("62")).Padding(0, 1)
	inactiveTabStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Padding(0, 1)
	groupHeaderStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("213"))
	// Templates with no build on this architecture — amber, the same tone the
	// warning dialog uses, because this informs rather than destroys.
	archWarnStyle      = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("214"))
	archWarnTitleStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("232")).Background(lipgloss.Color("214"))
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

// cautionStyle is used for the hand-written dialog — orange, like the other
// notices: the user's work is at risk only if they pick the wrong choice, and the
// dialog exists so they don't. Nothing is lost yet, so it should not read as an
// alarm.
var (
	cautionBorderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("208")).
				Bold(true)
	cautionTitleStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("16")).
				Background(lipgloss.Color("208")).
				Bold(true)
	cautionLeadStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("214")).
				Bold(true)
	cautionFileStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("214")).
				Bold(true)
	cautionInputStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("231")).
				Background(lipgloss.Color("94")).
				Bold(true)
	// The focused choice of a dialog.
	choiceFocusStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("16")).
				Background(lipgloss.Color("214")).
				Bold(true)
	choiceLabelStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("255")).
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

	// Edits-made-outside question — asked on open, before the startup warning
	if m.adoptedDialog {
		return m.renderAdoptedDialog()
	}

	// Warning dialog overlay
	if m.warningDialog {
		return m.renderWarningDialog()
	}

	// Overwrite confirmation overlay — shown when saving would destroy hand-written files
	if m.overwriteDialog {
		return m.renderOverwriteDialog()
	}

	// Comments confirmation overlay — shown when saving would remove comments
	if m.commentsDialog {
		return m.renderMessageDialog("⚠ Comments will be removed", commentsDialogMessage(m.lostComments),
			"Enter: save anyway  │  Esc: back")
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
	// Identity of the running binary, e.g. "v0.78.0 · built 2026-09-17T21:03:00Z" —
	// dim, next to the title, so a rebuilt-but-unbumped dev binary is visibly
	// distinguishable from whatever a project's wrapper/cache already resolved.
	identity := ""
	if m.binaryVersion != "" {
		identity = "  v" + m.binaryVersion
		if m.buildDate != "" && m.buildDate != "unknown" {
			identity += " · built " + m.buildDate
		}
	}
	selInfo := fmt.Sprintf("[%d selected]", selCount)
	padding := fullWidth - lipgloss.Width(title) - lipgloss.Width(identity) - lipgloss.Width(selInfo) - 2
	if padding < 1 {
		padding = 1
	}
	headerLine1 := " " + headerStyle.Render(title) + sepStyle.Render(identity) + strings.Repeat(" ", padding) + headerStyle.Render(selInfo)

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
		rightLines = m.renderConfigDetail(rightWidth, contentH).lines
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
		tabs = append(tabs, t.rendered(i == m.activeTab))
	}
	return " " + strings.Join(tabs, " ")
}

func (m model) renderSearchBar(fullWidth int) string {
	label := normalLabelStyle.Render(" Search:")
	chips := m.chipLabels()
	chipStart := fullWidth
	if len(chips) > 0 {
		chipStart = chips[0].start
	}

	boxWidth := chipStart - lipgloss.Width(label) - 3
	if boxWidth < 5 {
		boxWidth = 5
	}

	query := m.searchQuery
	var box string
	if m.searchFocused {
		// The box holds a leading space, the visible text and the caret, so the text
		// window is two columns narrower — and it follows the cursor rather than the
		// end of the query, or Home in a long query would scroll the caret off-screen.
		visible, cursor := windowAround(query, m.searchCursor, boxWidth-2)
		content := caretText(visible, cursor)
		// lipgloss.Width, not len: the block cursor carries escape codes that cost
		// bytes and no columns, and counting them would eat the box's padding.
		box = focusValueStyle.Render(" " + content + strings.Repeat(" ", max(0, boxWidth-lipgloss.Width(content)-1)))
	} else if query == "" {
		box = sepStyle.Render(" " + strings.Repeat("·", max(0, boxWidth-1)))
	} else {
		displayQuery := query
		if len(displayQuery) > boxWidth-2 {
			displayQuery = displayQuery[len(displayQuery)-boxWidth+2:]
		}
		box = normalValueStyle.Render(" " + displayQuery + strings.Repeat(" ", max(0, boxWidth-len(displayQuery)-1)))
	}

	line := label + " " + box
	col := lipgloss.Width(line)
	for _, chip := range chips {
		if chip.start > col {
			line += strings.Repeat(" ", chip.start-col)
			col = chip.start
		}
		rendered := m.renderChip(chip)
		line += rendered
		col += lipgloss.Width(rendered)
	}
	if col < fullWidth {
		line += strings.Repeat(" ", fullWidth-col)
	}
	return line
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
	if f.Key == "dind" && m.templateImpliesDind() {
		val = true
	}
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
		editDisplay := caretText(val, m.editCursor)
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
		editDisplay := caretText(val, m.editCursor)
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

// configDetail is what the Config tab's right panel drew: the lines on screen,
// and which cycle option each of those lines belongs to.
//
// Same contract as rightPanel.paramRowAt: the map is filled by the same pass
// that renders the options and re-keyed by the same scroll that moved them, so a
// click can only ever resolve to an option the panel is actually showing.
type configDetail struct {
	lines    []string
	optionAt map[int]int // screen line within the panel → index into field.Options
}

// renderImageSnapshot shows the snapshot this booth's image was built at, and
// warns when the field holds an older one: apt cannot install a package needing
// an exact version of one the image already has newer. Only a warning — the
// image on this machine may not be the one the booth is built on. Nothing at all
// when the image's snapshot is not known.
func (m model) renderImageSnapshot(width int) []string {
	if m.imageAptSnapshot == nil {
		return nil
	}
	settings := make(map[string]string, len(m.stringFields)+2)
	for key, value := range m.stringFields {
		settings[key] = value
	}
	for _, key := range []string{"dind", "egress"} {
		if m.boolFields[key] {
			settings[key] = "true"
		}
	}
	ref, imageSnap := m.imageAptSnapshot(settings)
	if imageSnap == "" {
		return nil
	}
	// The image name has no spaces to wrap at, so it gets a line of its own.
	lines := []string{detailLabel.Render("This booth's image:"), "  " + ref}
	lines = append(lines, detailLabel.Render("was built at ")+imageSnap+".")
	chosen, err := aptsnapshot.Parse(m.stringFields["apt-snapshot"])
	if err == nil && chosen != "" && chosen < imageSnap {
		lines = append(lines, "")
		for _, paragraph := range []string{
			"⚠ " + chosen + " is older than the image.",
			"`install apt` can fail on a package that needs an exact version of one the image already has newer.",
			"Use " + imageSnap + ", or TODAY.",
		} {
			for _, line := range wrapText(paragraph, width) {
				lines = append(lines, notifyStyle.Render(line))
			}
		}
	}
	return lines
}

// renderFieldError explains a refused value: what is wrong with it, what the field
// takes, and the two ways out — fix it, or Esc back to what was there.
func (m model) renderFieldError(f configFieldDef, width int) []string {
	var lines []string
	for i, line := range wrapText("✗ "+m.editErr, width) {
		if i > 0 {
			line = "  " + line
		}
		lines = append(lines, fieldErrStyle.Render(line))
	}
	if f.ValidHint != "" {
		for _, paragraph := range strings.Split(f.ValidHint, "\n") {
			lines = append(lines, wrapText(paragraph, width)...)
		}
	}
	prev := m.editPrev
	if prev == "" {
		prev = "(empty)"
	}
	lines = append(lines, "")
	lines = append(lines, detailLabel.Render("Enter to try again · Esc puts back "+prev))
	return lines
}

// renderConfigDetail renders the right panel for the Config tab.
func (m model) renderConfigDetail(rightWidth, contentH int) configDetail {
	var lines []string
	optionAt := map[int]int{}

	f := m.currentConfigField()
	if f != nil {
		lines = append(lines, detailTitle.Render(f.Label))
		lines = append(lines, "")

		// A refused value leads the panel: it is why the edit is still open.
		if m.editing && m.editErr != "" {
			lines = append(lines, m.renderFieldError(*f, rightWidth)...)
			lines = append(lines, "")
		}
		// So does the image's snapshot, and a warning against it, above the help.
		if f.Key == "apt-snapshot" {
			if image := m.renderImageSnapshot(rightWidth); len(image) > 0 {
				lines = append(lines, image...)
				lines = append(lines, "")
			}
		}

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
			for optIdx, opt := range f.Options {
				display := variantDisplay(opt)
				if opt == currentVal {
					lines = append(lines, selectedStyle.Render("> "+display))
				} else {
					lines = append(lines, "  "+display)
				}
				optionAt[len(lines)-1] = optIdx
			}
			lines = append(lines, "")
			if m.cycleEditing {
				lines = append(lines, detailLabel.Render("Editing... click an option or ◄►, Enter commits"))
			} else {
				lines = append(lines, detailLabel.Render("Click an option, or Space/Enter to edit"))
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
			if m.editing && m.editErr != "" {
				lines = append(lines, detailLabel.Render("Editing... fix the value and press Enter"))
			} else if m.editing {
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

	off := m.configDetailScroll(len(lines), optionAt, contentH)
	if off > 0 {
		lines = lines[off:]
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

	visible := make(map[int]int, len(optionAt))
	for line, optIdx := range optionAt {
		if screen := line - off; screen >= 0 && screen < len(lines) {
			visible[screen] = optIdx
		}
	}
	return configDetail{lines: lines, optionAt: visible}
}

// configDetailScroll is how far to shift the Config help pane so a cycle field's
// option list stays on screen while it is being edited.
//
// Variant's help restates every value, then lists them again under Options:. On a
// short terminal that list was the thing that fell off the bottom — exactly the
// rows a mouse needs. Help yields while editing; browsing still prefers the
// description.
func (m model) configDetailScroll(lineCount int, optionAt map[int]int, contentH int) int {
	if !m.cycleEditing || contentH <= 0 || len(optionAt) == 0 || lineCount <= contentH {
		return 0
	}

	first, last := -1, -1
	for line := range optionAt {
		if first < 0 || line < first {
			first = line
		}
		if line > last {
			last = line
		}
	}

	// "Options:" sits immediately above the first value; keep the hint below
	// when it fits.
	blockStart := first - 1
	if blockStart < 0 {
		blockStart = 0
	}
	blockEnd := last
	if last+2 < lineCount {
		blockEnd = last + 2
	}

	off := 0
	if blockEnd >= contentH {
		switch {
		case blockEnd-blockStart+1 <= contentH:
			off = blockStart
		case last-first+1 <= contentH:
			off = first
		default:
			off = last - contentH + 1
		}
	}
	if off < 0 {
		off = 0
	}
	if maxOff := lineCount - contentH; maxOff < 0 {
		return 0
	} else if off > maxOff {
		return maxOff
	}
	return off
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

	name := item.template.ListLabel()
	desc := item.template.DisplayDesc

	// Marker for templates with no build on this architecture. Empty in the
	// normal case so the gap after "[ ]" is exactly one space, same as an
	// extension row's "[ ] name" or "[ ] *name" — the warning glyph takes that
	// single slot instead of widening it, same convention as the "*" auto-select
	// marker below.
	mark := ""
	if item.template.UnsupportedOn(m.hostArch) {
		mark = "!"
	}

	plainPrefix := check + " " + mark + name
	// Width, not byte length: a display-disc with a multi-byte rune (an em dash,
	// say) has fewer columns than bytes, and len() here shifted the divider left
	// by the byte/column difference on every row that had one — flutter's own
	// disc ("...codebase — brings...") was the one that surfaced it.
	remaining := width - lipgloss.Width(plainPrefix) - 2
	descStr := ""
	if remaining > 3 && len(desc) > 0 {
		if lipgloss.Width(desc) > remaining {
			desc = truncateCols(desc, remaining-2) + ".."
		}
		descStr = desc
	}

	styledName := boldStyle.Render(name)
	styledMark := mark
	if mark != "" {
		styledMark = archWarnStyle.Render(mark)
	}
	line := check + " " + styledMark + styledName
	if descStr != "" {
		line += "  " + detailLabel.Render(descStr)
	}
	plainLen := lipgloss.Width(plainPrefix)
	if descStr != "" {
		plainLen += 2 + lipgloss.Width(descStr)
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
	// See renderTemplateLine: width, not byte length, for the same reason.
	remaining := width - lipgloss.Width(plainPrefix) - 2
	descStr := ""
	if remaining > 3 && len(desc) > 0 {
		if lipgloss.Width(desc) > remaining {
			desc = truncateCols(desc, remaining-2) + ".."
		}
		descStr = desc
	}

	styledName := boldStyle.Render(autoMark + name)
	line := "    " + check + " " + styledName
	if descStr != "" {
		line += "  " + detailLabel.Render(descStr)
	}
	plainLen := lipgloss.Width(plainPrefix)
	if descStr != "" {
		plainLen += 2 + lipgloss.Width(descStr)
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

	// Above the description, not below it: someone scanning this panel to decide
	// whether to tick the box needs to see "this will not install" first.
	lines = append(lines, m.renderArchWarning(t, width)...)

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

// renderArchWarning returns the "no build for this architecture" block for a
// template, or nil when the template installs fine here. Selecting such a
// template is allowed — the booth still builds, the setup warns and skips — so
// this explains the trade rather than forbidding it.
func (m model) renderArchWarning(t *tmpl.Template, width int) []string {
	if !t.UnsupportedOn(m.hostArch) {
		return nil
	}

	var lines []string
	lines = append(lines, archWarnTitleStyle.Render(fmt.Sprintf(" ⚠  Not available on %s ", m.hostArch)))
	lines = append(lines, "")

	note := t.UnsupportedArchNote
	if note == "" {
		note = fmt.Sprintf("%s has no %s build and will not be installed. "+
			"The booth still builds without it.", t.Name, m.hostArch)
	}
	for _, l := range wrapParagraphs(note, width) {
		lines = append(lines, archWarnStyle.Render(l))
	}
	lines = append(lines, "")
	return lines
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
	if m.confirmRequires != nil {
		keys = "  Enter/Y: yes  │  Esc/N: no"
	} else if m.quitting {
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
		keys = "  Space: select  │  ↑↓: navigate  │  ◄►: tab  │  1-3: filter  │  Tab: search"
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
				lines = append(lines, "      "+focusValueStyle.Render(" "+caretText(m.variadicEditBuf, m.variadicEditCur)+" "))
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
				lines = append(lines, "      "+focusValueStyle.Render(" "+caretText(m.variadicEditBuf, m.variadicEditCur)+" "))
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
		return "  " + focusLabelStyle.Render(name+":") + "  " + focusValueStyle.Render(" "+caretText(val, m.paramEditCursor)+" ")
	}
	if isFocused {
		return "  " + focusLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
	}
	return "  " + normalLabelStyle.Render(name+":") + "  " + normalValueStyle.Render(display)
}

// adoptReasonsShown caps how many read-back failures the hand-written dialog
// lists; the startup notice has the full list.
const adoptReasonsShown = 3

// renderOverwriteDialog renders the dialog shown when saving would replace
// hand-written files. It says what is at risk, why booth config could not take the
// edits in, and offers three numbered choices — the last of which, losing the
// files with no backup, needs the confirmation word typed in full.
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
	const indent = "       " // aligns detail lines under a choice's label

	border := cautionBorderStyle.Render("│")
	line := func(s string) string {
		return border + padStyledRight(" "+s, inner) + border
	}
	blank := func() string {
		return border + strings.Repeat(" ", inner) + border
	}
	centered := func(s string) string {
		return border + centerPad(s, inner) + border
	}
	para := func(dl []string, text string, width int, prefix string, style lipgloss.Style) []string {
		for _, l := range wrapText(text, width) {
			dl = append(dl, line(prefix+style.Render(l)))
		}
		return dl
	}

	var dl []string
	dl = append(dl, cautionBorderStyle.Render("┌"+strings.Repeat("─", inner)+"┐"))
	dl = append(dl, centered(cautionTitleStyle.Render("  Your booth files have changes booth config did not make  ")))
	dl = append(dl, blank())

	dl = para(dl, "You are at risk of losing your hand-written booth configuration. Please read carefully before you choose.", innerWidth, "", cautionLeadStyle)
	dl = append(dl, blank())

	if len(m.adoptReasons) > 0 {
		dl = para(dl, "booth config tried to read your changes back into the selection, but some of them are not something it can write:", innerWidth, "", warningTextStyle)
		for i, reason := range m.adoptReasons {
			if i == adoptReasonsShown {
				dl = append(dl, line("  "+warningHintStyle.Render(fmt.Sprintf("… and %d more", len(m.adoptReasons)-adoptReasonsShown))))
				break
			}
			for j, l := range wrapText(reason, innerWidth-4) {
				bullet := "  - "
				if j > 0 {
					bullet = "    "
				}
				dl = append(dl, line(bullet+warningHintStyle.Render(l)))
			}
		}
	} else {
		dl = para(dl, "These files were not written by booth config, or were changed by hand afterwards, so it cannot tell what they hold.", innerWidth, "", warningTextStyle)
	}
	dl = append(dl, blank())
	dl = para(dl, "Saving regenerates them from your selection:", innerWidth, "", warningTextStyle)
	for _, name := range m.drifted {
		dl = append(dl, line("  "+cautionFileStyle.Render(".booth/"+name)))
	}
	dl = append(dl, blank())

	choice := func(n int, label string) string {
		tag := fmt.Sprintf(" %d ", n)
		if m.overwriteChoice == n {
			return line("▸ " + choiceFocusStyle.Render(tag) + "  " + choiceLabelStyle.Render(label))
		}
		return line("  " + warningHintStyle.Render(tag) + "  " + warningTextStyle.Render(label))
	}
	files := func(suffix string) {
		for _, name := range m.drifted {
			dl = append(dl, line(indent+cautionFileStyle.Render(".booth/"+name+suffix)))
		}
	}

	dl = append(dl, choice(overwriteApply, "Apply, and back up your files"))
	dl = para(dl, "Replace them with the generated files. Your version is kept as:", innerWidth-len(indent), indent, warningHintStyle)
	files(".bak")
	dl = append(dl, blank())

	dl = append(dl, choice(overwriteBeside, "Save as new, to compare"))
	dl = para(dl, "Keep your files as they are, and write the generated ones beside them:", innerWidth-len(indent), indent, warningHintStyle)
	files(".new")
	dl = append(dl, blank())

	dl = append(dl, choice(overwriteOutright, "Overwrite, with no backup"))
	dl = para(dl, "Replace them, and keep nothing. Type \""+overwriteConfirmWord+"\" to confirm:", innerWidth-len(indent), indent, warningHintStyle)
	field := ""
	if m.overwriteChoice == overwriteOutright {
		field = caretText(m.overwriteInput, m.overwriteCursor)
	} else {
		field = m.overwriteInput
	}
	if pad := len(overwriteConfirmWord) + 4 - lipgloss.Width(field); pad > 0 {
		field += strings.Repeat(" ", pad)
	}
	dl = append(dl, line(indent+cautionInputStyle.Render(" "+field+" ")))
	dl = append(dl, blank())

	hint := "↑↓ or 1-3: choose  │  Enter: confirm  │  Esc: back  │  Ctrl+C: quit"
	dl = append(dl, centered(warningHintStyle.Render(hint)))
	dl = append(dl, cautionBorderStyle.Render("└"+strings.Repeat("─", inner)+"┘"))

	return m.centerDialog(dl, boxWidth)
}

// adoptedChangesShown caps how many read-back changes the question lists.
const adoptedChangesShown = 8

// renderAdoptedDialog renders the question asked on open when the booth's files
// were changed outside booth config and the changes were read back. They are
// valid, but the user did not make them here — so it says what changed and lets
// them accept it or leave to look first.
func (m model) renderAdoptedDialog() string {
	boxWidth := m.width * 60 / 100
	if boxWidth < 50 {
		boxWidth = 50
	}
	if boxWidth > m.width-4 {
		boxWidth = m.width - 4
	}
	inner := boxWidth - 2
	innerWidth := boxWidth - 4

	border := warningBorderStyle.Render("│")
	line := func(s string) string {
		return border + padStyledRight(" "+s, inner) + border
	}
	blank := func() string {
		return border + strings.Repeat(" ", inner) + border
	}
	centered := func(s string) string {
		return border + centerPad(s, inner) + border
	}
	para := func(dl []string, text string) []string {
		for _, l := range wrapText(text, innerWidth) {
			dl = append(dl, line(warningTextStyle.Render(l)))
		}
		return dl
	}

	var dl []string
	dl = append(dl, warningBorderStyle.Render("┌"+strings.Repeat("─", inner)+"┐"))
	dl = append(dl, centered(warningBorderStyle.Render("Your booth files were changed outside booth config")))
	dl = append(dl, blank())
	dl = para(dl, "These files were edited since booth config last wrote them:")
	nameWidth := 0
	for _, name := range m.adoptedFiles {
		nameWidth = max(nameWidth, len(".booth/"+name))
	}
	for _, name := range m.adoptedFiles {
		entry := cautionFileStyle.Render(".booth/" + name)
		if when := m.adoptedModified[name]; when != "" {
			entry += strings.Repeat(" ", nameWidth-len(".booth/"+name)) + "  " + warningHintStyle.Render("modified "+when)
		}
		dl = append(dl, line("  "+entry))
	}
	dl = append(dl, blank())
	if len(m.adoptedChanges) > 0 {
		dl = para(dl, "booth config read the changes back. They are valid, and it will keep them:")
		for i, change := range m.adoptedChanges {
			if i == adoptedChangesShown {
				dl = append(dl, line("  "+warningHintStyle.Render(fmt.Sprintf("… and %d more", len(m.adoptedChanges)-adoptedChangesShown))))
				break
			}
			for j, l := range wrapText(change, innerWidth-2) {
				if j > 0 {
					l = "  " + l
				}
				dl = append(dl, line("  "+cautionFileStyle.Render(l)))
			}
		}
	} else {
		dl = para(dl, "booth config read them back and found no setting it would write differently — only their fingerprint in .booth/.generated disagrees.")
	}
	dl = append(dl, blank())
	dl = para(dl, "If you did not expect this, choose Cancel and review the files yourself first.")
	dl = append(dl, blank())

	button := func(label string, focused bool) string {
		if focused {
			return choiceFocusStyle.Render(" " + label + " ")
		}
		return warningTextStyle.Render("[" + label + "]")
	}
	dl = append(dl, centered(button("OK", !m.adoptedCancel)+"    "+button("Cancel", m.adoptedCancel)))
	dl = append(dl, centered(warningHintStyle.Render("OK: accept the changes  │  Cancel: quit and review first")))
	dl = append(dl, blank())
	dl = append(dl, centered(warningHintStyle.Render("←→: choose  │  Enter: confirm")))
	dl = append(dl, warningBorderStyle.Render("└"+strings.Repeat("─", inner)+"┘"))

	return m.centerDialog(dl, boxWidth)
}

// centerDialog places a dialog's lines in the middle of the screen.
func (m model) centerDialog(dl []string, boxWidth int) string {
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

// commentsDialogMessage explains why a save removes comments, and lists them.
func commentsDialogMessage(lost []string) string {
	var b strings.Builder
	b.WriteString("This booth was edited outside booth config. The edits were read back and ")
	b.WriteString("will be kept, but comments cannot be: saving regenerates the files, and ")
	b.WriteString("these comments will be removed:\n\n")
	for _, c := range lost {
		b.WriteString("  " + c + "\n")
	}
	b.WriteString("\nNothing has been written yet. Esc goes back without saving.")
	return b.String()
}

// renderWarningDialog renders a centered warning dialog overlay.
func (m model) renderWarningDialog() string {
	return m.renderMessageDialog("⚠ Warning", m.warningMessage, "Enter/Space: continue  │  Esc: quit")
}

// renderMessageDialog renders a centered dialog: a title, a message (its own
// newlines kept), and a key hint.
func (m model) renderMessageDialog(title, message, hint string) string {
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
	msgLines := wrapParagraphs(message, innerWidth)

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
