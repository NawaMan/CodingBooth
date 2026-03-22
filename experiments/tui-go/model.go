package main

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// TreeItem is a flattened representation of a tree node (template or extension).
type TreeItem struct {
	TemplateName  string
	ExtensionName string // empty for template-level items
	Depth         int    // 0=template, 1=extension
}

func (ti TreeItem) Key() string {
	if ti.ExtensionName != "" {
		return ti.TemplateName + "/" + ti.ExtensionName
	}
	return ti.TemplateName
}

type clearNotificationMsg struct{}

type Model struct {
	templates    []Template
	templateMap  map[string]*Template
	selected     map[string]bool
	flatItems    []TreeItem
	cursor       int
	scrollOffset int
	width        int
	height       int
	notification string
	confirmed    bool // true if user pressed Ctrl+S
}

func NewModel(templates []Template) Model {
	m := Model{
		templates:   templates,
		templateMap: make(map[string]*Template),
		selected:    make(map[string]bool),
	}

	for i := range m.templates {
		t := &m.templates[i]
		m.templateMap[t.Name] = t
		m.flatItems = append(m.flatItems, TreeItem{TemplateName: t.Name, Depth: 0})
		for _, ext := range t.Extensions {
			m.flatItems = append(m.flatItems, TreeItem{TemplateName: t.Name, ExtensionName: ext.Name, Depth: 1})
		}
	}

	return m
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit

		case "ctrl+s":
			m.confirmed = true
			return m, tea.Quit

		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}

		case "down", "j":
			if m.cursor < len(m.flatItems)-1 {
				m.cursor++
			}

		case " ":
			m.toggleSelection()
		}

	case clearNotificationMsg:
		m.notification = ""
	}

	// Adjust scroll
	visibleHeight := m.contentHeight()
	if visibleHeight > 0 {
		if m.cursor < m.scrollOffset {
			m.scrollOffset = m.cursor
		}
		if m.cursor >= m.scrollOffset+visibleHeight {
			m.scrollOffset = m.cursor - visibleHeight + 1
		}
	}

	return m, nil
}

func (m *Model) toggleSelection() {
	if len(m.flatItems) == 0 {
		return
	}
	item := m.flatItems[m.cursor]
	key := item.Key()
	var notifications []string

	if m.selected[key] {
		// Deselecting
		delete(m.selected, key)
		if item.Depth == 0 {
			// Deselect all extensions of this template
			tmpl := m.templateMap[item.TemplateName]
			if tmpl != nil {
				for _, ext := range tmpl.Extensions {
					delete(m.selected, item.TemplateName+"/"+ext.Name)
				}
			}
		}
	} else {
		// Selecting
		m.selected[key] = true

		if item.Depth == 1 {
			// Auto-select parent template if not selected
			if !m.selected[item.TemplateName] {
				m.selected[item.TemplateName] = true
				notifications = append(notifications, fmt.Sprintf("Auto-selected: %s", item.TemplateName))
				// Also handle parent template's auto-select extensions and deps
				m.selectDependencies(item.TemplateName, &notifications)
				m.autoSelectExtensions(item.TemplateName, &notifications)
			}
			// Handle this extension's dependencies
			ext := m.findExtension(item.TemplateName, item.ExtensionName)
			if ext != nil {
				for _, dep := range ext.Requires {
					if !m.selected[dep] {
						m.selected[dep] = true
						notifications = append(notifications, fmt.Sprintf("Dependency: %s", dep))
						m.selectDependencies(dep, &notifications)
						m.autoSelectExtensions(dep, &notifications)
					}
				}
			}
		} else {
			// Template selected - handle dependencies and auto-select extensions
			m.selectDependencies(item.TemplateName, &notifications)
			m.autoSelectExtensions(item.TemplateName, &notifications)
		}
	}

	if len(notifications) > 0 {
		m.notification = strings.Join(notifications, " | ")
	} else {
		m.notification = ""
	}
}

func (m *Model) selectDependencies(tmplName string, notifications *[]string) {
	tmpl := m.templateMap[tmplName]
	if tmpl == nil {
		return
	}
	for _, dep := range tmpl.Requires {
		if !m.selected[dep] {
			m.selected[dep] = true
			*notifications = append(*notifications, fmt.Sprintf("Dependency: %s", dep))
			m.selectDependencies(dep, notifications)
			m.autoSelectExtensions(dep, notifications)
		}
	}
}

func (m *Model) autoSelectExtensions(tmplName string, notifications *[]string) {
	tmpl := m.templateMap[tmplName]
	if tmpl == nil {
		return
	}
	var autoSelected []string
	for _, ext := range tmpl.Extensions {
		if ext.AutoSelect {
			extKey := tmplName + "/" + ext.Name
			if !m.selected[extKey] {
				m.selected[extKey] = true
				autoSelected = append(autoSelected, ext.Name)
			}
		}
	}
	if len(autoSelected) > 0 {
		*notifications = append(*notifications, fmt.Sprintf("Auto: %s/%s", tmplName, strings.Join(autoSelected, ",")))
	}
}

func (m *Model) findExtension(tmplName, extName string) *Extension {
	tmpl := m.templateMap[tmplName]
	if tmpl == nil {
		return nil
	}
	for i := range tmpl.Extensions {
		if tmpl.Extensions[i].Name == extName {
			return &tmpl.Extensions[i]
		}
	}
	return nil
}

func (m Model) contentHeight() int {
	h := m.height - 4 // header(1) + separator(1) + separator(1) + footer(1)
	if h < 1 {
		return 1
	}
	return h
}

func (m Model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}

	// Styles
	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	sepStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	footerStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	selectedStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("82"))
	cursorStyle := lipgloss.NewStyle().Background(lipgloss.Color("236")).Bold(true)
	detailTitleStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("214"))
	detailLabelStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	notifyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("220"))
	checkOnStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("82"))
	checkOffStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))

	fullWidth := m.width
	leftWidth := fullWidth * 55 / 100
	if leftWidth < 30 {
		leftWidth = 30
	}
	rightWidth := fullWidth - leftWidth - 3 // 3 for " | "
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
	title := "CodingBooth Template Selector"
	selInfo := fmt.Sprintf("[%d selected]", selCount)
	padding := fullWidth - len(title) - len(selInfo)
	if padding < 1 {
		padding = 1
	}
	header := headerStyle.Render(title) + strings.Repeat(" ", padding) + headerStyle.Render(selInfo)

	// === Separator ===
	sep := sepStyle.Render(strings.Repeat("─", fullWidth))

	// === Left panel (tree) ===
	var leftLines []string
	end := m.scrollOffset + contentH
	if end > len(m.flatItems) {
		end = len(m.flatItems)
	}
	for i := m.scrollOffset; i < end; i++ {
		item := m.flatItems[i]
		key := item.Key()
		isSelected := m.selected[key]
		isCursor := i == m.cursor

		var check string
		if isSelected {
			check = checkOnStyle.Render("[x]")
		} else {
			check = checkOffStyle.Render("[ ]")
		}

		indent := ""
		name := ""
		if item.Depth == 1 {
			indent = "    "
			name = item.ExtensionName
		} else {
			name = item.TemplateName
		}

		// Get description
		desc := ""
		if item.Depth == 0 {
			if t := m.templateMap[item.TemplateName]; t != nil {
				desc = t.Description
			}
		} else {
			if ext := m.findExtension(item.TemplateName, item.ExtensionName); ext != nil {
				desc = ext.Description
			}
		}

		line := fmt.Sprintf("%s%s %s", indent, check, name)
		if desc != "" {
			remaining := leftWidth - lipgloss.Width(indent) - 4 - len(name) - 2
			if remaining > 3 && len(desc) > 0 {
				if len(desc) > remaining {
					desc = desc[:remaining-2] + ".."
				}
				line += "  " + detailLabelStyle.Render(desc)
			}
		}

		// Pad to leftWidth
		lineWidth := lipgloss.Width(line)
		if lineWidth < leftWidth {
			line += strings.Repeat(" ", leftWidth-lineWidth)
		}

		if isCursor {
			// Apply cursor style to the whole line - re-render
			plainLine := fmt.Sprintf("%s%s %s", indent, func() string {
				if isSelected {
					return "[x]"
				}
				return "[ ]"
			}(), name)
			if desc != "" {
				remaining := leftWidth - len(indent) - 4 - len(name) - 2
				if remaining > 3 && len(desc) > 0 {
					if len(desc) > remaining {
						desc = desc[:remaining-2] + ".."
					}
					plainLine += "  " + desc
				}
			}
			if len(plainLine) < leftWidth {
				plainLine += strings.Repeat(" ", leftWidth-len(plainLine))
			}
			if isSelected {
				line = cursorStyle.Render(selectedStyle.Render(plainLine))
			} else {
				line = cursorStyle.Render(plainLine)
			}
		} else if isSelected {
			plainLine := fmt.Sprintf("%s[x] %s", indent, name)
			if desc != "" {
				remaining := leftWidth - len(indent) - 4 - len(name) - 2
				if remaining > 3 && len(desc) > 0 {
					if len(desc) > remaining {
						desc = desc[:remaining-2] + ".."
					}
					plainLine += "  " + desc
				}
			}
			if len(plainLine) < leftWidth {
				plainLine += strings.Repeat(" ", leftWidth-len(plainLine))
			}
			line = selectedStyle.Render(plainLine)
		}

		leftLines = append(leftLines, line)
	}

	// Pad left panel if fewer items than contentH
	for len(leftLines) < contentH {
		leftLines = append(leftLines, strings.Repeat(" ", leftWidth))
	}

	// === Right panel (detail) ===
	var rightLines []string
	if m.cursor >= 0 && m.cursor < len(m.flatItems) {
		curItem := m.flatItems[m.cursor]

		if curItem.Depth == 0 {
			tmpl := m.templateMap[curItem.TemplateName]
			if tmpl != nil {
				rightLines = append(rightLines, detailTitleStyle.Render(tmpl.Name))
				rightLines = append(rightLines, detailLabelStyle.Render(tmpl.Category))
				rightLines = append(rightLines, "")
				rightLines = append(rightLines, wrapText(tmpl.Description, rightWidth))
				rightLines = append(rightLines, "")
				for _, line := range strings.Split(wrapText(tmpl.Detail, rightWidth), "\n") {
					rightLines = append(rightLines, line)
				}

				if len(tmpl.Params) > 0 {
					rightLines = append(rightLines, "")
					rightLines = append(rightLines, detailLabelStyle.Render("Parameters:"))
					for _, p := range tmpl.Params {
						rightLines = append(rightLines, fmt.Sprintf("  %s = %s", p.Name, p.Default))
						if len(p.Suggests) > 0 {
							rightLines = append(rightLines, fmt.Sprintf("    options: %s", strings.Join(p.Suggests, ", ")))
						}
					}
				}

				if len(tmpl.Requires) > 0 {
					rightLines = append(rightLines, "")
					rightLines = append(rightLines, detailLabelStyle.Render("Requires:"))
					rightLines = append(rightLines, fmt.Sprintf("  %s", strings.Join(tmpl.Requires, ", ")))
				}

				if len(tmpl.Extensions) > 0 {
					rightLines = append(rightLines, "")
					rightLines = append(rightLines, detailLabelStyle.Render("Extensions:"))
					for _, ext := range tmpl.Extensions {
						marker := "  "
						if ext.AutoSelect {
							marker = "* "
						}
						rightLines = append(rightLines, fmt.Sprintf("  %s%s - %s", marker, ext.Name, ext.Description))
					}
				}
			}
		} else {
			ext := m.findExtension(curItem.TemplateName, curItem.ExtensionName)
			if ext != nil {
				rightLines = append(rightLines, detailTitleStyle.Render(ext.Name))
				rightLines = append(rightLines, detailLabelStyle.Render(fmt.Sprintf("Extension of %s", curItem.TemplateName)))
				rightLines = append(rightLines, "")
				rightLines = append(rightLines, wrapText(ext.Description, rightWidth))
				rightLines = append(rightLines, "")
				for _, line := range strings.Split(wrapText(ext.Detail, rightWidth), "\n") {
					rightLines = append(rightLines, line)
				}

				if ext.AutoSelect {
					rightLines = append(rightLines, "")
					rightLines = append(rightLines, detailLabelStyle.Render("Auto-selected with parent"))
				}

				if len(ext.Requires) > 0 {
					rightLines = append(rightLines, "")
					rightLines = append(rightLines, detailLabelStyle.Render("Requires:"))
					rightLines = append(rightLines, fmt.Sprintf("  %s", strings.Join(ext.Requires, ", ")))
				}

				if len(ext.Params) > 0 {
					rightLines = append(rightLines, "")
					rightLines = append(rightLines, detailLabelStyle.Render("Parameters:"))
					for _, p := range ext.Params {
						rightLines = append(rightLines, fmt.Sprintf("  %s = %s", p.Name, p.Default))
					}
				}
			}
		}
	}

	// Pad right panel
	for len(rightLines) < contentH {
		rightLines = append(rightLines, "")
	}

	// Truncate right lines to rightWidth
	for i, line := range rightLines {
		if lipgloss.Width(line) > rightWidth {
			rightLines[i] = line[:rightWidth]
		}
		// Pad to rightWidth
		w := lipgloss.Width(rightLines[i])
		if w < rightWidth {
			rightLines[i] += strings.Repeat(" ", rightWidth-w)
		}
	}

	// === Combine panels ===
	var contentLines []string
	divider := sepStyle.Render(" │ ")
	for i := 0; i < contentH; i++ {
		contentLines = append(contentLines, leftLines[i]+divider+rightLines[i])
	}

	// === Footer ===
	footerText := "  Space: select  │  ↑↓/jk: navigate  │  Ctrl+S: save & quit  │  q: quit"
	if m.notification != "" {
		footerText = "  " + notifyStyle.Render(m.notification)
	}
	footer := footerStyle.Render(footerText)

	// === Scroll indicator ===
	scrollInfo := ""
	if len(m.flatItems) > contentH {
		scrollInfo = fmt.Sprintf("  %d-%d of %d", m.scrollOffset+1,
			min(m.scrollOffset+contentH, len(m.flatItems)), len(m.flatItems))
		header += sepStyle.Render(scrollInfo)
	}

	// Assemble
	return header + "\n" + sep + "\n" + strings.Join(contentLines, "\n") + "\n" + sep + "\n" + footer
}

func (m Model) SelectedItems() []string {
	var items []string
	for _, item := range m.flatItems {
		key := item.Key()
		if m.selected[key] {
			items = append(items, key)
		}
	}
	return items
}

func wrapText(text string, width int) string {
	if width <= 0 {
		return text
	}
	words := strings.Fields(text)
	if len(words) == 0 {
		return ""
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
	return strings.Join(lines, "\n")
}

func tickClearNotification() tea.Cmd {
	return tea.Tick(3*time.Second, func(t time.Time) tea.Msg {
		return clearNotificationMsg{}
	})
}
