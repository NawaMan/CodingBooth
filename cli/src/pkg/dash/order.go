// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// Ordering (ctrl+↑/↓) moves the selected row's group up or down among the
// groups: a repository with its worktrees, or a booth in no repository. On a
// linked worktree's row it moves that worktree within its repository instead;
// the main checkout always leads. The order is kept by Deps.SaveOrder, so the
// next dashboard opens with it. Anything not in it yet goes to the bottom, by
// name, and is added: the first time, that sorts everything by name.

// groupKey names the group a row is in: its repository, else its booth (a
// booth in no repository is a group of its own).
func groupKey(r row) string {
	if r.repo != nil && r.repo != otherBooths {
		return "repo:" + r.repo.Root
	}
	return r.key()
}

// innerKey names a linked worktree's place in its repository; "" for a row
// that leads its group. All the booths on a worktree move together.
func innerKey(r row) string {
	if r.main || r.repo == nil || r.repo == otherBooths || r.worktree == nil {
		return ""
	}
	return worktreeKey(*r.worktree)
}

// unit is something that has a place in the order.
type unit struct{ key, name, path string }

func groupUnit(r row) unit {
	if r.repo != nil && r.repo != otherBooths {
		return unit{groupKey(r), r.repo.Name, r.repo.Root}
	}
	return unit{groupKey(r), rowName(r), r.path()}
}

// arrange puts all in the saved order, adding what is not in it yet at the
// bottom, by name (groups, then worktrees: they are only ever compared among
// their own kind). Without an order store it leaves all as built.
func (m *model) arrange(all []row) []row {
	if m.deps.SaveOrder == nil {
		return all
	}
	pos := make(map[string]int, len(m.order))
	for i, e := range m.order {
		pos[e.Key] = i
	}
	var groups, inners []unit
	added := map[string]bool{}
	for _, r := range all {
		if g := groupUnit(r); g.key != "" && !added[g.key] {
			if _, known := pos[g.key]; !known {
				added[g.key] = true
				groups = append(groups, g)
			}
		}
		if k := innerKey(r); k != "" && !added[k] {
			if _, known := pos[k]; !known {
				added[k] = true
				inners = append(inners, unit{k, r.worktree.Name(), r.worktree.Path})
			}
		}
	}
	if len(groups)+len(inners) > 0 {
		byName := func(units []unit) {
			sort.SliceStable(units, func(i, j int) bool {
				a, b := strings.ToLower(units[i].name), strings.ToLower(units[j].name)
				if a != b {
					return a < b
				}
				return units[i].key < units[j].key
			})
		}
		byName(groups)
		byName(inners)
		order := append([]lifecycle.OrderEntry{}, m.order...)
		for _, u := range append(groups, inners...) {
			pos[u.key] = len(order)
			order = append(order, lifecycle.OrderEntry{Key: u.key, Path: u.path})
		}
		m.order = order
		if err := m.deps.SaveOrder(order); err != nil {
			m.setStatus("Could not save the row order: "+err.Error(), true)
		}
	}

	rank := func(r row) (int, int) {
		inner := -1 // the rows that lead come first in their group
		if k := innerKey(r); k != "" {
			inner = pos[k]
		}
		return pos[groupKey(r)], inner
	}
	sorted := append([]row{}, all...)
	sort.SliceStable(sorted, func(i, j int) bool {
		gi, ii := rank(sorted[i])
		gj, ij := rank(sorted[j])
		if gi != gj {
			return gi < gj
		}
		return ii < ij
	})
	return sorted
}

// reorder moves the selected row's group (or, on a linked worktree, that
// worktree) delta places among the ones the table shows. It swaps places with
// its neighbour in the saved order, so the rows hidden between them stay put.
func (m model) reorder(delta int) (tea.Model, tea.Cmd) {
	if m.deps.SaveOrder == nil {
		return m, nil
	}
	r, ok := m.currentRow()
	if !ok {
		return m, nil
	}
	key, group := innerKey(r), groupKey(r)
	var units []string
	shown := map[string]bool{}
	for _, x := range m.rows {
		k := groupKey(x)
		if key != "" {
			if k != group {
				continue
			}
			k = innerKey(x)
		}
		if k != "" && !shown[k] {
			shown[k] = true
			units = append(units, k)
		}
	}
	if key == "" {
		key = group
	}
	at := -1
	for i, k := range units {
		if k == key {
			at = i
		}
	}
	to := at + delta
	if at < 0 || to < 0 || to >= len(units) {
		return m, nil
	}
	order := append([]lifecycle.OrderEntry{}, m.order...)
	i, j := -1, -1
	for n, e := range order {
		switch e.Key {
		case key:
			i = n
		case units[to]:
			j = n
		}
	}
	if i < 0 || j < 0 {
		return m, nil
	}
	order[i], order[j] = order[j], order[i]
	if err := m.deps.SaveOrder(order); err != nil {
		m.setStatus("Could not save the row order: "+err.Error(), true)
		return m, nil
	}
	m.order = order
	m.setStatus("", false)
	m.layout()
	return m, nil
}
