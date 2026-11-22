// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"errors"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// orderStore is an in-memory Deps.Order/SaveOrder.
type orderStore struct {
	order []lifecycle.OrderEntry
	saves int
	err   error
}

func (o *orderStore) wire(deps Deps) Deps {
	deps.Order = func() []lifecycle.OrderEntry { return append([]lifecycle.OrderEntry{}, o.order...) }
	deps.SaveOrder = func(order []lifecycle.OrderEntry) error {
		if o.err != nil {
			return o.err
		}
		o.saves++
		o.order = append([]lifecycle.OrderEntry{}, order...)
		return nil
	}
	return deps
}

func (o *orderStore) keys() []string {
	var keys []string
	for _, e := range o.order {
		keys = append(keys, e.Key)
	}
	return keys
}

// orderRepos: zeta (the dashboard's, with linked worktrees b-fix and a-idea,
// in git's order) and alpha; booths Mid (in no repository) and one on b-fix.
func orderRepos() ([]lifecycle.Booth, []lifecycle.Repo) {
	repos := []lifecycle.Repo{{
		Name: "zeta", Root: "/home/u/dev/zeta", Here: true,
		Worktrees: []lifecycle.Worktree{
			{Path: "/home/u/dev/zeta", Branch: "main", Main: true},
			{Path: "/home/u/dev/zeta.wt/b-fix", Branch: "b-fix"},
			{Path: "/home/u/dev/zeta.wt/a-idea", Branch: "a-idea"},
		},
	}, {
		Name: "alpha", Root: "/home/u/dev/alpha",
		Worktrees: []lifecycle.Worktree{{Path: "/home/u/dev/alpha", Branch: "main", Main: true}},
	}}
	booths := []lifecycle.Booth{running("Mid"), boothAt("fixer", "/home/u/dev/zeta.wt/b-fix")}
	return booths, repos
}

func orderModel(store *orderStore, booths []lifecycle.Booth, repos []lifecycle.Repo) model {
	deps := store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps())
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos})
	return next.(model)
}

func TestOrderStartsByNameAndIsSaved(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	want := []string{"(none) @main", "Mid", "(none) @main", "(none) @a-idea", "fixer @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v (alpha, Mid, zeta by name; its worktrees by name)", got, want)
	}
	if m.rows[2].repo.Name != "zeta" {
		t.Fatalf("third group is %s, want zeta", m.rows[2].repo.Name)
	}
	wantKeys := []string{"repo:/home/u/dev/alpha", "Mid@docker", "repo:/home/u/dev/zeta",
		"worktree:/home/u/dev/zeta.wt/a-idea", "worktree:/home/u/dev/zeta.wt/b-fix"}
	if got := store.keys(); !reflect.DeepEqual(got, wantKeys) {
		t.Errorf("saved = %v, want %v", got, wantKeys)
	}
	if r, _ := m.currentRow(); r.repo == nil || !r.repo.Here {
		t.Errorf("cursor on %s, want the dashboard's own repository (zeta)", rowName(r))
	}
}

func TestOrderPutsNewRowsAtTheBottom(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	saves := store.saves
	next, _ := m.Update(snapshotMsg{seq: 2, booths: append(booths, running("Aardvark")), repos: repos})
	m = next.(model)
	if got := rowName(m.rows[len(m.rows)-1]); got != "Aardvark" {
		t.Errorf("last row = %s, want the new booth Aardvark: %v", got, rowSummary(m.rows))
	}
	if store.saves != saves+1 {
		t.Errorf("saves = %d, want one more for the new booth", store.saves-saves)
	}
	// Nothing new: nothing written.
	m.Update(snapshotMsg{seq: 3, booths: append(booths, running("Aardvark")), repos: repos})
	if store.saves != saves+1 {
		t.Errorf("an unchanged snapshot saved the order again")
	}
}

func TestCtrlArrowsMoveTheGroup(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos) // cursor on zeta, the last group
	m, _ = press(t, m, "ctrl+up")
	want := []string{"(none) @main", "(none) @main", "(none) @a-idea", "fixer @b-fix", "Mid"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	if r, _ := m.currentRow(); r.repo == nil || r.repo.Name != "zeta" || !r.main {
		t.Errorf("cursor left zeta's lead row: %s", rowName(r))
	}
	if got := store.keys()[1]; got != "repo:/home/u/dev/zeta" {
		t.Errorf("saved second = %s, want zeta", got)
	}
	m, _ = press(t, m, "ctrl+up", "ctrl+up") // the second is already at the top
	if r, _ := m.currentRow(); m.cursor != 0 || r.repo.Name != "zeta" {
		t.Errorf("zeta should lead the table: %v", rowSummary(m.rows))
	}
	m, _ = press(t, m, "ctrl+down")
	if m.rows[0].repo.Name != "alpha" || m.rows[1].repo.Name != "zeta" {
		t.Errorf("ctrl+down did not move zeta back: %v", rowSummary(m.rows))
	}
	if !strings.Contains(helpText(m), "ctrl+↑/↓") {
		t.Errorf("the help page does not mention ctrl+↑/↓")
	}
}

func TestCtrlArrowsOnAWorktreeMoveItWithinItsRepository(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "down", "down", "ctrl+up") // fixer @b-fix
	want := []string{"(none) @main", "Mid", "(none) @main", "fixer @b-fix", "(none) @a-idea"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	m, _ = press(t, m, "ctrl+up") // the main checkout stays first
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Errorf("moved past the main checkout: %v", got)
	}
	if r, _ := m.currentRow(); rowName(r) != "fixer" {
		t.Errorf("cursor on %s, want fixer", rowName(r))
	}
}

func TestReorderSkipsHiddenRowsAndKeepsTheirPlace(t *testing.T) {
	store := &orderStore{}
	hidden := &hideStore{}
	booths, repos := orderRepos()
	deps := hidden.wire(store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps()))
	hidden.keys["Mid@docker"] = true
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos, hidden: deps.Hidden()})
	m, _ = press(t, next.(model), "ctrl+up") // zeta passes alpha, Mid is hidden between
	if m.rows[0].repo.Name != "zeta" {
		t.Fatalf("zeta did not move above alpha: %v", rowSummary(m.rows))
	}
	want := []string{"repo:/home/u/dev/zeta", "Mid@docker", "repo:/home/u/dev/alpha"}
	if got := store.keys()[:3]; !reflect.DeepEqual(got, want) {
		t.Errorf("saved = %v, want %v (Mid kept its place)", got, want)
	}
}

func TestReorderSaveFailureKeepsTheOrder(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	store.err = errors.New("disk full")
	before := rowSummary(m.rows)
	m, _ = press(t, m, "ctrl+up")
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, before) {
		t.Errorf("rows moved although the save failed: %v", got)
	}
	if !strings.Contains(m.status, "disk full") || !m.statusErr {
		t.Errorf("status = %q", m.status)
	}
}

func TestNoOrderStoreKeepsRowsAsBuilt(t *testing.T) {
	booths, repos := orderRepos()
	f := &fakeDeps{snapshot: booths, repos: repos}
	m := newModel(f.deps())
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos})
	m, _ = press(t, next.(model), "ctrl+down")
	want := []string{"(none) @main", "fixer @b-fix", "(none) @a-idea", "(none) @main", "Mid"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

// sepSummary is rowSummary with separators drawn as "---".
func sepSummary(rows []row) []string {
	out := rowSummary(rowsWithoutSeps(rows))
	var all []string
	i := 0
	for _, r := range rows {
		if r.sep != "" {
			all = append(all, "---")
			continue
		}
		all = append(all, out[i])
		i++
	}
	return all
}

func rowsWithoutSeps(rows []row) []row {
	var out []row
	for _, r := range rows {
		if r.sep == "" {
			out = append(out, r)
		}
	}
	return out
}

func TestSeparatorIsAddedBelowTheGroupAndSelected(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-") // on alpha
	// The first "---" is the top line, there once the table has a separator.
	want := []string{"---", "(none) @main", "---", "Mid", "(none) @main", "(none) @a-idea", "fixer @b-fix"}
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	if r, _ := m.currentRow(); r.sep == "" {
		t.Errorf("cursor not on the new separator")
	}
	if got := store.keys()[1]; got != "separator:1" {
		t.Errorf("saved second = %s, want separator:1", got)
	}
	// On a linked worktree it goes below the whole repository.
	m, _ = press(t, m, "G", "-")
	if got := sepSummary(m.rows); got[len(got)-1] != "---" {
		t.Errorf("separator not below zeta's worktrees: %v", got)
	}
	if got := store.keys()[4]; got != "separator:2" {
		t.Errorf("saved = %v, want separator:2 right after zeta", store.keys())
	}
	view := stripANSI(m.View())
	if !strings.Contains(view, "────") || !strings.Contains(view, "- separator") {
		t.Errorf("separator line or help missing:\n%s", view)
	}
}

func TestSeparatorMovesAndIsDeleted(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-", "ctrl+down")
	want := []string{"---", "(none) @main", "Mid", "---", "(none) @main", "(none) @a-idea", "fixer @b-fix"}
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	// Reopened: still there.
	m = orderModel(store, booths, repos)
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("after reopening rows = %v, want %v", got, want)
	}
	m, cmd := press(t, m, "g", "down", "down", "down", "delete")
	if cmd != nil || m.confirm != nil {
		t.Errorf("d on a separator should delete it at once")
	}
	if got := sepSummary(m.rows); len(got) != 5 || strings.Join(got, ",") != strings.Join(rowSummary(m.rows), ",") {
		t.Errorf("separator not deleted: %v", got)
	}
	for _, k := range store.keys() {
		if strings.HasPrefix(k, "separator:") {
			t.Errorf("separator still saved: %v", store.keys())
		}
	}
}

func TestSeparatorIgnoresBoothKeys(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	f := &fakeDeps{snapshot: booths, repos: repos}
	deps := store.wire(f.deps())
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos})
	m, _ = press(t, next.(model), "g", "-")
	for _, key := range []string{"s", "x", "r", "o", "p", "m", "l", "t", "e", "n", "i", "c"} {
		m, _ = press(t, m, key)
	}
	if len(f.ran)+len(f.execed) != 0 || m.confirm != nil {
		t.Errorf("a key on a separator acted: ran %v execed %v confirm %+v", f.ran, f.execed, m.confirm)
	}
}

func TestSeparatorsAreNotInTheHiddenView(t *testing.T) {
	store := &orderStore{}
	hidden := &hideStore{}
	booths, repos := orderRepos()
	deps := hidden.wire(store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps()))
	hidden.keys["Mid@docker"] = true
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos, hidden: deps.Hidden()})
	m, _ = press(t, next.(model), "g", "-", "h") // h on a separator does not hide it
	if !strings.Contains(m.status, "delete deletes it") || len(hidden.keys) != 1 {
		t.Errorf("h on a separator: status %q hidden %v", m.status, hidden.keys)
	}
	m, _ = press(t, m, "H")
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, []string{"Mid"}) {
		t.Errorf("hidden view = %v, want only Mid", got)
	}
	m, _ = press(t, m, "-")
	if n := len(store.keys()); n != 6 {
		t.Errorf("- in the hidden view added a separator: %v", store.keys())
	}
}

// Two dashboards share one order store; each must see the other's changes and
// never undo them.

// sharedDashboard is a dashboard on store whose snapshots return booths and
// repos, as the real one's do (order included).
func sharedDashboard(store *orderStore, booths []lifecycle.Booth, repos []lifecycle.Repo) model {
	deps := store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps())
	deps.Repos = func([]lifecycle.Booth) []lifecycle.Repo { return repos }
	return refreshed(newModel(deps))
}

// refreshed is m after a snapshot taken now.
func refreshed(m model) model {
	m, fetch := m.refresh(true)
	next, _ := m.Update(fetch())
	return next.(model)
}

func TestOrderAnotherDashboardsMoveShowsOnRefresh(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	a := sharedDashboard(store, booths, repos)
	b := sharedDashboard(store, booths, repos)
	a, _ = press(t, a, "ctrl+up") // zeta above Mid
	b = refreshed(b)
	if got, want := rowSummary(b.rows), rowSummary(a.rows); !reflect.DeepEqual(got, want) {
		t.Errorf("other dashboard after a refresh = %v, want %v", got, want)
	}
}

func TestOrderMoveKeepsAnotherDashboardsMove(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	a := sharedDashboard(store, booths, repos)
	b := sharedDashboard(store, booths, repos)
	a, _ = press(t, a, "ctrl+up") // alpha, zeta, Mid
	// b has not refreshed: its rows are still alpha, Mid, zeta. Its cursor is
	// on zeta; ctrl+up moves zeta among the rows as saved now: above alpha.
	b, _ = press(t, b, "ctrl+up")
	want := []string{"repo:/home/u/dev/zeta", "repo:/home/u/dev/alpha", "Mid@docker"}
	if got := groupKeys(store); !reflect.DeepEqual(got, want) {
		t.Errorf("saved groups = %v, want %v (a's move kept, b's on top of it)", got, want)
	}
	if got, want := rowSummary(b.rows), rowSummary(refreshed(a).rows); !reflect.DeepEqual(got, want) {
		t.Errorf("b shows %v, a %v", got, want)
	}
}

func TestOrderNewBoothKeepsAnotherDashboardsMove(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	a := sharedDashboard(store, booths, repos)
	b := sharedDashboard(store, booths, repos)
	// b's snapshot reads the order, then a moves zeta, then the snapshot
	// arrives with a new booth in it.
	b, fetch := b.refresh(true)
	msg := fetch().(snapshotMsg)
	a, _ = press(t, a, "ctrl+up") // alpha, zeta, Mid
	msg.booths = append(msg.booths, running("Aardvark"))
	next, _ := b.Update(msg)
	b = next.(model)
	want := []string{"repo:/home/u/dev/alpha", "repo:/home/u/dev/zeta", "Mid@docker", "Aardvark@docker"}
	if got := groupKeys(store); !reflect.DeepEqual(got, want) {
		t.Errorf("saved groups = %v, want %v (a's move kept, Aardvark added)", got, want)
	}
}

func TestOrderSeparatorKeepsAnotherDashboards(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	a := sharedDashboard(store, booths, repos)
	b := sharedDashboard(store, booths, repos)
	a, _ = press(t, a, "ctrl+up", "-") // zeta above Mid, a line below zeta
	b, _ = press(t, b, "-")
	var seps []string
	for _, k := range store.keys() {
		if strings.HasPrefix(k, separatorPrefix) {
			seps = append(seps, k)
		}
	}
	sort.Strings(seps)
	if !reflect.DeepEqual(seps, []string{"separator:1", "separator:2"}) {
		t.Errorf("separators = %v, want both a's and b's, numbered apart", seps)
	}
	if got := groupKeys(store); got[1] != "repo:/home/u/dev/zeta" {
		t.Errorf("saved groups = %v: b's separator undid a's move", got)
	}
	// d on b's separator leaves a's alone.
	b, _ = press(t, b, "delete")
	if got := store.keys(); !containsKey(got, "separator:1") || containsKey(got, "separator:2") {
		t.Errorf("after b deleted its separator: %v", got)
	}
}

func TestOrderSnapshotFromBeforeAMoveIsDropped(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := sharedDashboard(store, booths, repos)
	m, fetch := m.refresh(true)
	late := fetch() // read the order before the move below
	m, _ = press(t, m, "ctrl+up")
	moved := rowSummary(m.rows)
	next, _ := m.Update(late)
	if got := rowSummary(next.(model).rows); !reflect.DeepEqual(got, moved) {
		t.Errorf("a snapshot older than the move put the rows back: %v, want %v", got, moved)
	}
}

// groupKeys are the saved keys that are groups (no worktrees, no separators).
func groupKeys(store *orderStore) []string {
	var keys []string
	for _, k := range store.keys() {
		if !strings.HasPrefix(k, "worktree:") && !strings.HasPrefix(k, separatorPrefix) {
			keys = append(keys, k)
		}
	}
	return keys
}

func containsKey(keys []string, key string) bool {
	for _, k := range keys {
		if k == key {
			return true
		}
	}
	return false
}

// siblingModel is orderRepos with three booths on zeta's main checkout (one,
// two, three, as listed) and two on its worktree b-fix (fixer, helper).
func siblingModel(t *testing.T, store *orderStore, hidden *hideStore) model {
	t.Helper()
	_, repos := orderRepos()
	booths := []lifecycle.Booth{
		running("Mid"),
		boothAt("one", "/home/u/dev/zeta"), boothAt("two", "/home/u/dev/zeta"), boothAt("three", "/home/u/dev/zeta"),
		boothAt("fixer", "/home/u/dev/zeta.wt/b-fix"), boothAt("helper", "/home/u/dev/zeta.wt/b-fix"),
	}
	deps := store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps())
	msg := snapshotMsg{seq: 1, booths: booths, repos: repos}
	if hidden != nil {
		deps = hidden.wire(deps)
		msg.hidden = deps.Hidden()
	}
	next, _ := newModel(deps).Update(msg)
	return next.(model)
}

// selectRow moves the cursor to the booth name.
func selectRow(t *testing.T, m model, name string) model {
	t.Helper()
	for i, r := range m.rows {
		if rowName(r) == name && r.booth != nil {
			m.cursor = i
			m.selected = r.key()
			return m
		}
	}
	t.Fatalf("no row %s in %v", name, rowSummary(m.rows))
	return m
}

func TestCtrlArrowsSwapBoothsOnTheSameCheckout(t *testing.T) {
	store := &orderStore{}
	m := siblingModel(t, store, nil)
	before := []string{"(none) @main", "Mid", "one @main", "two @main", "three @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, before) {
		t.Fatalf("rows = %v, want %v", got, before)
	}
	for _, k := range store.keys() {
		if strings.HasPrefix(k, boothOrderPrefix) {
			t.Fatalf("a booth's place was saved before any was moved: %v", store.keys())
		}
	}
	groups := func() []string {
		var out []string
		for _, k := range store.keys() {
			if !strings.HasPrefix(k, boothOrderPrefix) {
				out = append(out, k)
			}
		}
		return out
	}
	groupsBefore := groups()

	m, _ = press(t, selectRow(t, m, "two"), "ctrl+up")
	want := []string{"(none) @main", "Mid", "two @main", "one @main", "three @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	if r, _ := m.currentRow(); rowName(r) != "two" {
		t.Errorf("cursor on %s, want two", rowName(r))
	}
	if got := groups(); !reflect.DeepEqual(got, groupsBefore) {
		t.Errorf("the groups moved: %v, want %v", got, groupsBefore)
	}

	m, _ = press(t, m, "ctrl+down", "ctrl+down") // back below one, then below three
	want = []string{"(none) @main", "Mid", "one @main", "three @main", "two @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}

	// On a linked worktree too, and only among its own booths.
	m, _ = press(t, selectRow(t, m, "helper"), "ctrl+up")
	want = []string{"(none) @main", "Mid", "one @main", "three @main", "two @main",
		"(none) @a-idea", "helper @b-fix", "fixer @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}

	// The next dashboard opens with it.
	_, repos := orderRepos()
	again := orderModel(store, m.booths, repos)
	if got := rowSummary(again.rows); !reflect.DeepEqual(got, want) {
		t.Errorf("reopened rows = %v, want %v", got, want)
	}
}

func TestCtrlArrowsAtTheEdgeOfACheckoutMoveTheGroup(t *testing.T) {
	store := &orderStore{}
	m := siblingModel(t, store, nil)
	m, _ = press(t, selectRow(t, m, "one"), "ctrl+up") // the first booth: zeta passes Mid
	want := []string{"(none) @main", "one @main", "two @main", "three @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix", "Mid"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	m, _ = press(t, selectRow(t, m, "three"), "ctrl+down") // the last booth: zeta goes back
	want = []string{"(none) @main", "Mid", "one @main", "two @main", "three @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	// The first booth on a worktree moves the worktree within its repository.
	m, _ = press(t, selectRow(t, m, "fixer"), "ctrl+up")
	want = []string{"(none) @main", "Mid", "one @main", "two @main", "three @main",
		"fixer @b-fix", "helper @b-fix", "(none) @a-idea"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
}

func TestBoothSwapSkipsAHiddenSiblingAndKeepsItsPlace(t *testing.T) {
	store := &orderStore{}
	hidden := &hideStore{keys: map[string]bool{"two@docker": true}, paths: map[string]string{}}
	m := siblingModel(t, store, hidden)
	m, _ = press(t, selectRow(t, m, "three"), "ctrl+up") // passes one; two is hidden between
	want := []string{"(none) @main", "Mid", "three @main", "one @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	var saved []string
	for _, k := range store.keys() {
		if strings.HasPrefix(k, boothOrderPrefix) {
			saved = append(saved, k)
		}
	}
	if want := []string{"booth:three@docker", "booth:two@docker", "booth:one@docker"}; !reflect.DeepEqual(saved, want) {
		t.Errorf("saved = %v, want %v (two kept its place)", saved, want)
	}
}

func TestBoothSwapSaveFailureKeepsTheOrder(t *testing.T) {
	store := &orderStore{}
	m := siblingModel(t, store, nil)
	before := rowSummary(m.rows)
	store.err = errors.New("disk full")
	m, _ = press(t, selectRow(t, m, "two"), "ctrl+up")
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, before) {
		t.Errorf("rows = %v, want %v", got, before)
	}
	if !strings.Contains(m.status, "Could not save the row order") {
		t.Errorf("status = %q", m.status)
	}
}

// Naming a separator (enter), and the top line.

// typed presses each rune of text.
func typed(t *testing.T, m model, text string) model {
	t.Helper()
	for _, r := range text {
		m, _ = press(t, m, string(r))
	}
	return m
}

// savedName is the name saved for key, and whether key is saved at all.
func savedName(store *orderStore, key string) (string, bool) {
	for _, e := range store.order {
		if e.Key == key {
			return e.Name, true
		}
	}
	return "", false
}

func TestEnterNamesASeparator(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-", "enter")
	if m.prompt == nil || m.prompt.sep != "separator:1" {
		t.Fatalf("enter on a separator should ask for its name: %+v", m.prompt)
	}
	if view := stripANSI(m.View()); !strings.Contains(view, "Name of the rows below this line:") {
		t.Errorf("prompt missing:\n%s", view)
	}
	m = typed(t, m, "Client work")
	m, _ = press(t, m, "enter")
	if name, _ := savedName(store, "separator:1"); name != "Client work" || m.prompt != nil {
		t.Fatalf("saved name %q, prompt %+v", name, m.prompt)
	}
	if r, _ := m.currentRow(); r.sep != "separator:1" || r.label != "Client work" {
		t.Errorf("cursor row = %+v, want the named separator", r)
	}
	m.width = 100
	if view := stripANSI(m.View()); !strings.Contains(view, "── Client work ──") {
		t.Errorf("name not in the line:\n%s", view)
	}
	// It moves with its name, and is there when the dashboard opens again.
	m, _ = press(t, m, "ctrl+down")
	if name, _ := savedName(store, "separator:1"); name != "Client work" {
		t.Errorf("after a move the name is %q", name)
	}
	m = orderModel(store, booths, repos)
	want := []string{"---", "(none) @main", "Mid", "---", "(none) @main", "(none) @a-idea", "fixer @b-fix"}
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, want) || m.rows[3].label != "Client work" {
		t.Fatalf("reopened rows = %v label %q", got, m.rows[3].label)
	}
	// Enter again starts from the name it has; an empty one takes it away.
	m, _ = press(t, m, "g", "down", "down", "down", "enter")
	if got := m.prompt.field.String(); got != "Client work" {
		t.Fatalf("prompt starts with %q, want the name it has", got)
	}
	m, _ = press(t, m, "ctrl+u", "enter")
	if name, saved := savedName(store, "separator:1"); name != "" || !saved {
		t.Errorf("cleared: name %q saved %v, want an unnamed separator", name, saved)
	}
}

func TestEscLeavesASeparatorsNameAlone(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-", "enter")
	m = typed(t, m, "Work")
	saves := store.saves
	m, _ = press(t, m, "esc")
	if name, _ := savedName(store, "separator:1"); name != "" || store.saves != saves || m.prompt != nil {
		t.Errorf("esc saved: name %q saves %d→%d", name, saves, store.saves)
	}
}

func TestTopLineIsThereWithASeparatorAndIsNamed(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	for _, r := range m.rows {
		if r.sep != "" {
			t.Fatalf("no separator yet, so no top line: %v", sepSummary(m.rows))
		}
	}
	m, _ = press(t, m, "G", "-", "g")
	if r, _ := m.currentRow(); r.sep != separatorTop {
		t.Fatalf("first row = %+v, want the top line", r)
	}
	if _, saved := savedName(store, separatorTop); saved {
		t.Errorf("an unnamed top line is not saved: %v", store.keys())
	}
	if help := stripANSI(m.View()); !strings.Contains(help, "top line: enter name the rows below it") {
		t.Errorf("top line help missing:\n%s", help)
	}
	m, _ = press(t, m, "enter")
	m = typed(t, m, "Mine")
	m, _ = press(t, m, "enter")
	if name, _ := savedName(store, separatorTop); name != "Mine" || m.rows[0].label != "Mine" {
		t.Fatalf("top line name saved %q shown %q", name, m.rows[0].label)
	}

	// It is not moved, deleted or added below, and nothing moves above it.
	before := sepSummary(m.rows)
	saves := store.saves
	m, _ = press(t, m, "ctrl+down", "ctrl+up", "delete", "-")
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, before) || store.saves != saves || m.confirm != nil {
		t.Errorf("the top line changed: rows %v → %v, saves %d → %d", before, got, saves, store.saves)
	}
	m, _ = press(t, m, "down", "ctrl+up")
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, before) {
		t.Errorf("a group moved above the top line: %v", got)
	}

	// It goes with the last separator, and comes back, named, with the next.
	m, _ = press(t, m, "G", "delete")
	for _, r := range m.rows {
		if r.sep != "" {
			t.Fatalf("the last separator is deleted, so no top line: %v", sepSummary(m.rows))
		}
	}
	m, _ = press(t, m, "-")
	if m.rows[0].sep != separatorTop || m.rows[0].label != "Mine" {
		t.Errorf("top line did not come back with its name: %+v", m.rows[0])
	}
	// An empty name takes it out of the saved order.
	m, _ = press(t, m, "g", "enter", "ctrl+u", "enter")
	if _, saved := savedName(store, separatorTop); saved || m.rows[0].sep != separatorTop || m.rows[0].label != "" {
		t.Errorf("cleared top line: saved %v row %+v", saved, m.rows[0])
	}
}

func TestDeleteOnSeveralRowsLeavesTheTopLine(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-", "g", "shift+down", "shift+down", "delete") // top line, alpha, the separator
	if m.confirm != nil || !strings.Contains(m.status, "Deleted 1 row.") || !strings.Contains(m.status, "the top line: it stays") {
		t.Fatalf("confirm %+v status %q", m.confirm, m.status)
	}
	if containsKey(store.keys(), "separator:1") {
		t.Errorf("the separator is left: %v", store.keys())
	}
}

func TestSeparatorNameIsSharedBetweenDashboards(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	a := sharedDashboard(store, booths, repos)
	b := sharedDashboard(store, booths, repos)
	a, _ = press(t, a, "-", "enter")
	a = typed(t, a, "Work")
	a, _ = press(t, a, "enter")
	b = refreshed(b)
	found := false
	for _, r := range b.rows {
		found = found || (r.sep == "separator:1" && r.label == "Work")
	}
	if !found {
		t.Fatalf("b does not show a's name: %v", sepSummary(b.rows))
	}
	// b moves a group; a's name is kept.
	b, _ = press(t, b, "ctrl+up")
	if name, _ := savedName(store, "separator:1"); name != "Work" {
		t.Errorf("b's move lost a's name: %q", name)
	}
	// a names a separator b has deleted meanwhile: nothing is saved.
	a, _ = press(t, a, "enter")
	store.order = nil
	a = typed(t, a, "!")
	a, _ = press(t, a, "enter")
	if _, saved := savedName(store, "separator:1"); saved || !strings.Contains(a.status, "is gone") {
		t.Errorf("named a deleted separator: saved %v status %q", saved, a.status)
	}
}

// A test's booth that is removed and comes back is new again: it goes to the
// bottom, below what was added meanwhile, not to the place it had.
func TestABoothThatComesBackGoesToTheBottom(t *testing.T) {
	store := &orderStore{}
	test := boothAt("basic", "/home/u/dev/zeta/tests/basic")
	booths, repos := orderRepos()
	m := orderModel(store, append(booths, test), repos)
	// By name the first time: alpha, basic, Mid, zeta.
	if got := rowSummary(m.rows)[:3]; !reflect.DeepEqual(got, []string{"(none) @main", "basic", "Mid"}) {
		t.Fatalf("setup: rows = %v, order = %v", rowSummary(m.rows), store.keys())
	}

	// The test ends: its booth is gone, and so is its place.
	next, _ := m.Update(snapshotMsg{seq: 2, booths: booths, repos: repos})
	m = next.(model)
	for _, k := range store.keys() {
		if k == "basic@docker" {
			t.Fatalf("order = %v: the gone booth kept its place", store.keys())
		}
	}

	// Run again, with another: both at the bottom, by name.
	other := boothAt("aaa-test", "/home/u/dev/zeta/tests/aaa")
	next, _ = m.Update(snapshotMsg{seq: 3, booths: append(append([]lifecycle.Booth{}, booths...), test, other), repos: repos})
	m = next.(model)
	rows := rowSummary(m.rows)
	if got := rows[len(rows)-2:]; !reflect.DeepEqual(got, []string{"aaa-test", "basic"}) {
		t.Errorf("rows = %v, want aaa-test and basic last", rows)
	}
}

func TestPlacesWithNoRowAreDroppedButNotSeparators(t *testing.T) {
	booths, repos := orderRepos()
	store := &orderStore{order: []lifecycle.OrderEntry{
		{Key: "old-test@docker"}, // a container with no folder: never dropped by the store
		{Key: "repo:/home/u/dev/zeta", Path: "/home/u/dev/zeta"},
		{Key: "booth:old-sibling@docker", Path: "/home/u/dev/zeta"},
		{Key: "separator:1", Name: "Tests"},
		{Key: "repo:/home/u/dev/elsewhere", Path: "/home/u/dev/elsewhere"}, // its booth was deleted: no row now
		{Key: "worktree:/home/u/dev/zeta.wt/old", Path: "/home/u/dev/zeta.wt/old"},
	}}
	deps := store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps())
	m := newModel(deps)

	// An engine that did not answer lists none of its booths: nothing is dropped.
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos, order: store.order, orderRead: true,
		warnings: []string{"Warning: could not list podman booths: down"}})
	m = next.(model)
	keys := strings.Join(store.keys(), " ")
	if !strings.Contains(keys, "old-test@docker") || !strings.Contains(keys, "booth:old-sibling@docker") ||
		!strings.Contains(keys, "repo:/home/u/dev/elsewhere") {
		t.Fatalf("order = %v: dropped while an engine did not answer", keys)
	}

	next, _ = m.Update(snapshotMsg{seq: 2, booths: booths, repos: repos, order: store.order, orderRead: true})
	m = next.(model)
	keys = strings.Join(store.keys(), " ")
	for _, gone := range []string{"old-test@docker", "booth:old-sibling@docker", "repo:/home/u/dev/elsewhere",
		"worktree:/home/u/dev/zeta.wt/old"} {
		if strings.Contains(keys, gone) {
			t.Errorf("order = %v: %s kept its place", keys, gone)
		}
	}
	for _, kept := range []string{"repo:/home/u/dev/zeta", "separator:1", "worktree:/home/u/dev/zeta.wt/b-fix",
		"Mid@docker"} {
		if !strings.Contains(keys, kept) {
			t.Errorf("order = %v: %s lost its place", keys, kept)
		}
	}
}

// A repository whose last booth is deleted has no row; when it has a booth
// again it is new, and goes to the bottom, not to the place it had.
func TestADeletedRepositoryComesBackAtTheBottom(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos) // alpha, Mid, zeta
	if got := store.keys()[0]; got != "repo:/home/u/dev/alpha" {
		t.Fatalf("setup: order = %v", store.keys())
	}
	next, _ := m.Update(snapshotMsg{seq: 2, booths: booths, repos: repos[:1]}) // alpha is no longer found
	m = next.(model)
	if keys := strings.Join(store.keys(), " "); strings.Contains(keys, "alpha") {
		t.Fatalf("order = %v: alpha kept its place", keys)
	}
	next, _ = m.Update(snapshotMsg{seq: 3, booths: booths, repos: repos})
	m = next.(model)
	if keys := store.keys(); keys[len(keys)-1] != "repo:/home/u/dev/alpha" {
		t.Errorf("order = %v, want alpha last", keys)
	}
}
