package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	templates := GenerateSampleData()
	model := NewModel(templates)

	p := tea.NewProgram(model, tea.WithAltScreen())
	result, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	m := result.(Model)
	if m.confirmed {
		selected := m.SelectedItems()
		if len(selected) == 0 {
			fmt.Println("No items selected.")
		} else {
			fmt.Println("Selected items:")
			for _, item := range selected {
				fmt.Printf("  - %s\n", item)
			}
		}
	}
}
