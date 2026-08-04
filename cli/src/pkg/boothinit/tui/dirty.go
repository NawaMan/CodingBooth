// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"maps"
	"slices"
)

// Cancelling only asks when there is something to lose, and "is there" is answered
// by comparing the editable state against a snapshot taken when the TUI opened.
//
// The alternative — a `dirty` flag flipped at every mutation — is the drift this
// package has already been bitten by once: every new handler has to remember it,
// and the one that forgets makes the TUI lie about unsaved work. A comparison
// cannot forget, and it gets an extra property for free: selecting a template and
// deselecting it again is genuinely no change, so it does not ask.

// configSnapshot is everything a save would write, flattened for comparison.
// Cursors, scroll offsets, the active tab and the search query are deliberately
// absent: looking around is not editing.
type configSnapshot struct {
	selected map[string]bool
	params   map[string]string
	strings  map[string]string
	bools    map[string]bool
	lists    map[string][]string
}

// snapshot copies the editable state. The copies matter — the maps it reads are
// the live ones, so a reference would compare equal to itself forever.
func (m model) snapshot() configSnapshot {
	lists := make(map[string][]string, len(m.listFields))
	for k, v := range m.listFields {
		lists[k] = slices.Clone(v)
	}
	return configSnapshot{
		selected: maps.Clone(m.selected),
		params:   maps.Clone(m.paramValues),
		strings:  maps.Clone(m.stringFields),
		bools:    maps.Clone(m.boolFields),
		lists:    lists,
	}
}

func (s configSnapshot) equal(other configSnapshot) bool {
	return maps.Equal(s.selected, other.selected) &&
		maps.Equal(s.params, other.params) &&
		maps.Equal(s.strings, other.strings) &&
		maps.Equal(s.bools, other.bools) &&
		maps.EqualFunc(s.lists, other.lists, slices.Equal)
}

// hasUnsavedChanges reports whether leaving now would lose anything.
//
// A half-typed value counts. It has not reached the maps yet, so the comparison
// cannot see it, and "I was in the middle of typing" is exactly when a
// confirmation earns its keep.
func (m model) hasUnsavedChanges() bool {
	if m.editing || m.cycleEditing || m.paramEditing || m.variadicEditing {
		return true
	}
	return !m.snapshot().equal(m.baseline)
}
