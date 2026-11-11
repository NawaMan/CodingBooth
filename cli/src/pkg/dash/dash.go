// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	tea "github.com/charmbracelet/bubbletea"
)

// Run shows the dashboard until the user quits.
func Run(deps Deps) error {
	m := newModel(deps)
	// Questions still waiting for an answer end with the dashboard.
	defer m.cancel()
	program := tea.NewProgram(m, tea.WithAltScreen())
	_, err := program.Run()
	return err
}
