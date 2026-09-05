// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

func filterFixture() model {
	linter := &tmpl.Template{Name: "linter", DisplayName: "Linter"}
	goTmpl := &tmpl.Template{
		Name:        "go",
		DisplayName: "Go",
		Primary:     true,
		Extensions:  []*tmpl.Template{linter},
	}
	python := &tmpl.Template{Name: "python", DisplayName: "Python", Primary: true}
	gcc := &tmpl.Template{Name: "gcc", DisplayName: "GCC"}
	myapp := &tmpl.Template{Name: "myapp", DisplayName: "My App", Local: true}
	items := []treeItem{
		{kind: kindTemplate, template: goTmpl},
		{kind: kindExtension, template: goTmpl, extension: linter},
		{kind: kindTemplate, template: python},
		{kind: kindTemplate, template: gcc},
		{kind: kindTemplate, template: myapp},
	}
	m := mouseModel(items)
	m.hasLocal = true
	return m
}

func templateNames(items []treeItem) []string {
	var names []string
	for _, item := range items {
		if item.kind == kindTemplate {
			names = append(names, item.template.Name)
		}
	}
	return names
}

func extensionNames(items []treeItem) []string {
	var names []string
	for _, item := range items {
		if item.kind == kindExtension {
			names = append(names, item.extension.Name)
		}
	}
	return names
}

func namesEqual(got, want []string) bool {
	if len(got) != len(want) {
		return false
	}
	for index := range want {
		if got[index] != want[index] {
			return false
		}
	}
	return true
}

func TestApplyListFilter_PopularKeepsPrimaryAndItsExtensions(t *testing.T) {
	m := filterFixture()
	m.listFilter = listFilterPopular
	items := m.activeItems()
	if got, want := templateNames(items), []string{"go", "python"}; !namesEqual(got, want) {
		t.Fatalf("popular templates = %v, want %v", got, want)
	}
	if got, want := extensionNames(items), []string{"linter"}; !namesEqual(got, want) {
		t.Fatalf("popular extensions = %v, want %v", got, want)
	}
}

func TestApplyListFilter_PopularKeepsSelectedNonPrimary(t *testing.T) {
	m := filterFixture()
	m.listFilter = listFilterPopular
	m.selected["gcc"] = true
	if got, want := templateNames(m.activeItems()), []string{"go", "python", "gcc"}; !namesEqual(got, want) {
		t.Fatalf("popular + gcc selected = %v, want %v", got, want)
	}
}

func TestApplyListFilter_PopularKeepsParentWhenNonPrimaryExtensionIsPicked(t *testing.T) {
	plugin := &tmpl.Template{Name: "plugin", DisplayName: "Plugin"}
	gcc := &tmpl.Template{Name: "gcc", DisplayName: "GCC", Extensions: []*tmpl.Template{plugin}}
	goTmpl := &tmpl.Template{Name: "go", DisplayName: "Go", Primary: true}
	m := mouseModel([]treeItem{
		{kind: kindTemplate, template: goTmpl},
		{kind: kindTemplate, template: gcc},
		{kind: kindExtension, template: gcc, extension: plugin},
	})
	m.listFilter = listFilterPopular
	m.selected["gcc/plugin"] = true
	if got, want := templateNames(m.activeItems()), []string{"go", "gcc"}; !namesEqual(got, want) {
		t.Fatalf("popular templates = %v, want %v", got, want)
	}
	if got, want := extensionNames(m.activeItems()), []string{"plugin"}; !namesEqual(got, want) {
		t.Fatalf("popular extensions = %v, want %v", got, want)
	}
}

func TestApplyListFilter_LocalKeepsProjectTemplates(t *testing.T) {
	m := filterFixture()
	m.listFilter = listFilterLocal
	items := m.activeItems()
	if got, want := templateNames(items), []string{"myapp"}; !namesEqual(got, want) {
		t.Fatalf("local templates = %v, want %v", got, want)
	}
}

func TestApplyListFilter_SelectedKeepsPickedTemplateAndAllItsExtensions(t *testing.T) {
	m := filterFixture()
	m.selected["go"] = true
	m.listFilter = listFilterSelected
	items := m.activeItems()
	if got, want := templateNames(items), []string{"go"}; !namesEqual(got, want) {
		t.Fatalf("selected templates = %v, want %v", got, want)
	}
	if got, want := extensionNames(items), []string{"linter"}; !namesEqual(got, want) {
		t.Fatalf("selected extensions = %v, want %v", got, want)
	}
}

func TestApplyListFilter_SelectedKeepsParentWhenOnlyExtensionIsPicked(t *testing.T) {
	m := filterFixture()
	m.selected["go/linter"] = true
	m.listFilter = listFilterSelected
	items := m.activeItems()
	if got, want := templateNames(items), []string{"go"}; !namesEqual(got, want) {
		t.Fatalf("selected templates = %v, want %v", got, want)
	}
	if got, want := extensionNames(items), []string{"linter"}; !namesEqual(got, want) {
		t.Fatalf("selected extensions = %v, want %v", got, want)
	}
}

func TestApplyListFilter_AllIsIdentity(t *testing.T) {
	m := filterFixture()
	m.listFilter = listFilterAll
	if got, want := templateNames(m.activeItems()), []string{"go", "python", "gcc", "myapp"}; !namesEqual(got, want) {
		t.Fatalf("all templates = %v, want %v", got, want)
	}
}

func TestActiveItems_SearchIgnoresListFilter(t *testing.T) {
	m := filterFixture()
	m.listFilter = listFilterPopular
	m.searchQuery = "gcc"
	items := m.activeItems()
	if got, want := templateNames(items), []string{"gcc"}; !namesEqual(got, want) {
		t.Fatalf("search under popular = %v, want %v (search is the escape hatch)", got, want)
	}
}

func TestChipLabels_HiddenOnConfigTab(t *testing.T) {
	m := filterFixture()
	m.activeTab = 0
	if len(m.chipLabels()) != 0 {
		t.Fatalf("Config tab should have no chips, got %d", len(m.chipLabels()))
	}
}

func TestChipLabels_LocalOnlyWhenProjectTemplatesExist(t *testing.T) {
	without := mouseModel([]treeItem{templateItem("go")})
	for _, chip := range without.chipLabels() {
		if chip.filter == listFilterLocal {
			t.Fatal("Local chip should be hidden when the booth has no project templates")
		}
	}

	withLocal := filterFixture()
	found := false
	for _, chip := range withLocal.chipLabels() {
		if chip.filter == listFilterLocal {
			found = true
		}
	}
	if !found {
		t.Fatal("Local chip should appear when hasLocal is set")
	}
}

func TestSearchRowDrawsFilterChips(t *testing.T) {
	m := filterFixture()
	lines := strings.Split(m.View(), "\n")
	row := lines[rowSearch]
	for _, want := range []string{"Search:", "All", "Popular", "Local", "Selected"} {
		if !strings.Contains(row, want) {
			t.Fatalf("search row missing %q: %q", want, row)
		}
	}
}

func TestClickChipSwitchesFilter(t *testing.T) {
	m := filterFixture()
	var popular chipLabel
	for _, chip := range m.chipLabels() {
		if chip.filter == listFilterPopular {
			popular = chip
			break
		}
	}
	if popular.width == 0 {
		t.Fatal("Popular chip was not laid out")
	}

	m = click(m, popular.start, rowSearch)
	if m.listFilter != listFilterPopular {
		t.Fatalf("listFilter = %v, want Popular", m.listFilter)
	}
	if m.searchFocused {
		t.Fatal("clicking a chip should leave search unfocused")
	}
	if got, want := templateNames(m.activeItems()), []string{"go", "python"}; !namesEqual(got, want) {
		t.Fatalf("after Popular click, templates = %v, want %v", got, want)
	}
}

func press(m model, ch rune) model {
	res, _ := m.Update(keyMsg(ch))
	return res.(model)
}

func TestKeySwitchesListFilter(t *testing.T) {
	m := filterFixture()

	m = press(m, '2')
	if m.listFilter != listFilterPopular {
		t.Fatalf("2 should select Popular, got %v", m.listFilter)
	}
	if got, want := templateNames(m.activeItems()), []string{"go", "python"}; !namesEqual(got, want) {
		t.Fatalf("after 2, templates = %v, want %v", got, want)
	}

	m = press(m, '3')
	if m.listFilter != listFilterSelected {
		t.Fatalf("3 should select Selected, got %v", m.listFilter)
	}

	m = press(m, '1')
	if m.listFilter != listFilterAll {
		t.Fatalf("1 should select All, got %v", m.listFilter)
	}

	m = press(m, '4')
	if m.listFilter != listFilterLocal {
		t.Fatalf("4 should select Local when the booth has project templates, got %v", m.listFilter)
	}
}

func TestKeyFourIsNoopWithoutLocal(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	m = press(m, '4')
	if m.listFilter != listFilterAll {
		t.Fatalf("4 without Local should leave All, got %v", m.listFilter)
	}
}

func TestKeyDoesNotSwitchFilterWhileSearching(t *testing.T) {
	m := filterFixture()
	m.searchFocused = true
	m = press(m, '2')
	if m.listFilter != listFilterAll {
		t.Fatal("a digit typed into search must not switch the filter")
	}
	if m.searchQuery != "2" {
		t.Fatalf("search query = %q, want 2", m.searchQuery)
	}
}

func TestChipLabels_ShowKeyDigits(t *testing.T) {
	m := filterFixture()
	byFilter := map[listFilter]string{}
	for _, chip := range m.chipLabels() {
		byFilter[chip.filter] = chip.name
	}
	if byFilter[listFilterAll] != "1 All" || byFilter[listFilterPopular] != "2 Popular" ||
		byFilter[listFilterSelected] != "3 Selected" || byFilter[listFilterLocal] != "4 Local" {
		t.Fatalf("chip names = %v", byFilter)
	}
}

func TestClickSearchBoxStillFocusesSearch(t *testing.T) {
	m := filterFixture()
	chips := m.chipLabels()
	if len(chips) == 0 {
		t.Fatal("expected chips on the Languages tab")
	}
	// A column well to the left of the first chip is the query box.
	m = click(m, chips[0].start-5, rowSearch)
	if !m.searchFocused {
		t.Fatal("clicking the search box should still focus it")
	}
	if m.listFilter != listFilterAll {
		t.Fatalf("a search-box click must not change the filter, got %v", m.listFilter)
	}
}

func TestNewModel_HasLocalWhenProjectTemplateMerged(t *testing.T) {
	stock := &tmpl.Template{Name: "go", DisplayName: "Go", CategoryName: "languages"}
	local := &tmpl.Template{Name: "myapp", DisplayName: "My App", CategoryName: "project", Local: true}
	registry := &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{
			{Name: "languages", DisplayName: "Languages", Order: 1, Templates: []*tmpl.Template{stock}},
			{Name: "project", DisplayName: "This project", Order: 0, Templates: []*tmpl.Template{local}},
		},
		ByName: map[string]*tmpl.Template{"go": stock, "myapp": local},
	}
	m := newModel(registry, nil)
	if !m.hasLocal {
		t.Fatal("newModel should set hasLocal when a merged template is Local")
	}
}

func TestNewModel_DefaultsToPopular(t *testing.T) {
	goTmpl := &tmpl.Template{Name: "go", DisplayName: "Go", Primary: true, CategoryName: "languages"}
	gcc := &tmpl.Template{Name: "gcc", DisplayName: "GCC", CategoryName: "languages"}
	registry := &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{
			Name: "languages", DisplayName: "Languages", Order: 1,
			Templates: []*tmpl.Template{goTmpl, gcc},
		}},
		ByName: map[string]*tmpl.Template{"go": goTmpl, "gcc": gcc},
	}

	blank := newModel(registry, nil)
	if blank.listFilter != listFilterPopular {
		t.Fatalf("new booth listFilter = %v, want Popular", blank.listFilter)
	}
	if got, want := templateNames(blank.activeItems()), []string{"go"}; !namesEqual(got, want) {
		t.Fatalf("blank Popular templates = %v, want %v", got, want)
	}

	reopen := newModel(registry, &PreSelection{SelectedTemplates: map[string]bool{"gcc": true}})
	if got, want := templateNames(reopen.activeItems()), []string{"gcc", "go"}; !namesEqual(got, want) {
		t.Fatalf("reopened Popular with gcc selected = %v, want %v", got, want)
	}
}

func TestTabStar_PopularMarksTabsThatHavePrimaryTemplates(t *testing.T) {
	goTmpl := &tmpl.Template{Name: "go", DisplayName: "Go", Primary: true}
	gcc := &tmpl.Template{Name: "gcc", DisplayName: "GCC"}
	m := model{
		width:         100,
		height:        30,
		tabNames:      []string{"Config", "Languages", "Tools"},
		tabItems:      [][]treeItem{nil, {{kind: kindTemplate, template: goTmpl}}, {{kind: kindTemplate, template: gcc}}},
		activeTab:     1,
		tabCursors:    []int{0, 0, 0},
		tabScrollOffs: []int{0, 0, 0},
		selected:      map[string]bool{},
		paramValues:   map[string]string{},
		stringFields:  map[string]string{},
		boolFields:    map[string]bool{},
		cycleIndices:  map[string]int{},
		listFields:    map[string][]string{},
		listFilter:    listFilterPopular,
	}

	labels := m.tabLabels()
	if !labels[1].starred {
		t.Fatal("Languages should star under Popular — it has a primary template")
	}
	if labels[2].starred {
		t.Fatal("Tools should not star under Popular — gcc is not primary")
	}
}
