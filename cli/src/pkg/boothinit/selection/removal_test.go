// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// A top-level "~name" takes a template's tool out of the variant image that
// ships it: parsed as a Remove item, kept through serialize and merge, and
// resolved into ResolvedSelection.Removed rather than selected.

func removalRegistry() *tmpl.TemplateRegistry {
	glow := &tmpl.Template{Name: "glow", InVariants: []string{"base"}, Remove: "run rm -f /usr/local/bin/glow"}
	gnupg := &tmpl.Template{Name: "gnupg", InVariants: []string{"base"}}
	goT := &tmpl.Template{Name: "go"}
	needsGlow := &tmpl.Template{Name: "docs", Requires: []string{"glow"}}
	return &tmpl.TemplateRegistry{ByName: map[string]*tmpl.Template{
		"glow": glow, "gnupg": gnupg, "go": goT, "docs": needsGlow,
	}}
}

func TestParse_TopLevelRemoval(t *testing.T) {
	parsed, err := ParseSelectDSL("go/~glow")
	require.NoError(t, err)
	require.Len(t, parsed.Items, 2)
	assert.Equal(t, ParsedItem{Name: "go"}, parsed.Items[0])
	assert.Equal(t, ParsedItem{Name: "glow", Remove: true}, parsed.Items[1])

	only, err := ParseSelectDSL("~glow")
	require.NoError(t, err)
	assert.Equal(t, []ParsedItem{{Name: "glow", Remove: true}}, only.Items)
}

func TestParse_ExtensionExcludeIsNotARemoval(t *testing.T) {
	parsed, err := ParseSelectDSL("go~linter")
	require.NoError(t, err)
	assert.False(t, parsed.Items[0].Remove)
	assert.Equal(t, []string{"linter"}, parsed.Items[0].Excludes)
}

func TestParse_RemovalRejectsParamsAndExtensions(t *testing.T) {
	for _, dsl := range []string{"~", "~glow:3.0.0", "~glow+x", "~glow~y"} {
		_, err := ParseSelectDSL(dsl)
		assert.Error(t, err, dsl)
	}
}

func TestSerialize_RemovalRoundTrips(t *testing.T) {
	parsed, err := ParseSelectDSL("go:1.25/~glow")
	require.NoError(t, err)
	assert.Equal(t, "go:1.25/~glow", SerializeSelection(parsed))
}

func TestMerge_LaterWordWinsBetweenSelectAndRemove(t *testing.T) {
	base, _ := ParseSelectDSL("go/glow")
	add, _ := ParseSelectDSL("~glow")
	assert.Equal(t, "go/~glow", SerializeSelection(MergeSelections(base, add)))

	back, _ := ParseSelectDSL("glow")
	assert.Equal(t, "go/glow", SerializeSelection(MergeSelections(MergeSelections(base, add), back)))
}

func TestResolve_RemovalIsNotSelected(t *testing.T) {
	parsed, _ := ParseSelectDSL("go/~glow")
	resolved, err := Resolve(parsed, removalRegistry())
	require.NoError(t, err)
	require.Len(t, resolved.Templates, 1)
	assert.Equal(t, "go", resolved.Templates[0].Template.Name)
	require.Len(t, resolved.Removed, 1)
	assert.Equal(t, "glow", resolved.Removed[0].Name)
}

func TestResolve_RemovalErrors(t *testing.T) {
	for dsl, want := range map[string]string{
		"~nope":      "unknown template",
		"~gnupg":     "cannot be removed",
		"~go":        "cannot be removed",
		"glow/~glow": "both selected and removed",
		"docs/~glow": "the selection needs",
	} {
		parsed, err := ParseSelectDSL(dsl)
		require.NoError(t, err, dsl)
		_, err = Resolve(parsed, removalRegistry())
		if assert.Error(t, err, dsl) {
			assert.Contains(t, err.Error(), want, dsl)
		}
	}
}

func TestLiftParams_SkipsRemovals(t *testing.T) {
	reg := removalRegistry()
	reg.ByName["glow"].Params = map[string]tmpl.Param{"GLOW_VERSION": {Default: "latest"}}
	reg.ByName["glow"].ParamOrder = []string{"GLOW_VERSION"}
	parsed, _ := ParseSelectDSL("~glow")
	LiftParams(parsed, reg, map[string]string{"GLOW_VERSION": "3.0.0"})
	assert.Equal(t, "~glow", SerializeSelection(parsed))
}
