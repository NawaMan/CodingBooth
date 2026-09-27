// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- SerializeSelection / SerializeItem ---

func TestSerializeSelection_RoundTrips(t *testing.T) {
	for _, dsl := range []string{
		"go",
		"go/python",
		"go:1.24",
		"go+linter",
		"go+linter+docker",
		"go:1.24+linter",
		"go+linter~credential",
		`go+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest"`,
	} {
		parsed, err := ParseSelectDSL(dsl)
		require.NoError(t, err, dsl)
		assert.Equal(t, dsl, SerializeSelection(parsed), "round-trip of %q", dsl)
	}
}

func TestSerializeSelection_Nil(t *testing.T) {
	assert.Equal(t, "", SerializeSelection(nil))
	assert.Equal(t, "", SerializeSelection(&ParsedSelection{}))
}

func TestSerializeItem_QuotesParamsIndependently(t *testing.T) {
	item := ParsedItem{Name: "nodejs", Extensions: []ParsedExtension{
		{Name: "npm-pkg", Params: []string{"@types/node", "@types/react"}},
	}}
	assert.Equal(t, `nodejs+npm-pkg:"@types/node","@types/react"`, SerializeItem(item))
}

// --- MergeSelections ---

func TestMergeSelections_NewTemplateAppended(t *testing.T) {
	base, _ := ParseSelectDSL("go/python")
	add, _ := ParseSelectDSL("docker")

	merged := MergeSelections(base, add)

	assert.Equal(t, "go/python/docker", SerializeSelection(merged))
}

func TestMergeSelections_ExtensionAddedToExistingTemplate(t *testing.T) {
	base, _ := ParseSelectDSL("go")
	add, _ := ParseSelectDSL("go+docker")

	merged := MergeSelections(base, add)

	require.Len(t, merged.Items, 1)
	assert.Equal(t, "go+docker", SerializeSelection(merged))
}

func TestMergeSelections_ExistingExtensionParamsReplaced(t *testing.T) {
	base, _ := ParseSelectDSL("nodejs+npm-pkg:lodash")
	add, _ := ParseSelectDSL("nodejs+npm-pkg:express")

	merged := MergeSelections(base, add)

	assert.Equal(t, "nodejs+npm-pkg:express", SerializeSelection(merged))
}

func TestMergeSelections_ExcludesUnioned(t *testing.T) {
	base, _ := ParseSelectDSL("firebase~credential")
	add, _ := ParseSelectDSL("firebase~emulator")

	merged := MergeSelections(base, add)

	assert.Equal(t, "firebase~credential~emulator", SerializeSelection(merged))
}

func TestMergeSelections_ItemParamsReplacedWhenAddSpecifiesThem(t *testing.T) {
	base, _ := ParseSelectDSL("go:1.23")
	add, _ := ParseSelectDSL("go:1.24")

	merged := MergeSelections(base, add)

	assert.Equal(t, "go:1.24", SerializeSelection(merged))
}

func TestMergeSelections_NilBase(t *testing.T) {
	add, _ := ParseSelectDSL("go")
	assert.Equal(t, add, MergeSelections(nil, add))
}

func TestMergeSelections_NilAdd(t *testing.T) {
	base, _ := ParseSelectDSL("go")
	assert.Equal(t, base, MergeSelections(base, nil))
}

// --- RemoveFromSelection ---

func TestRemoveFromSelection_WholeTemplate(t *testing.T) {
	sel, _ := ParseSelectDSL("go/python/docker")

	result, unmatched := RemoveFromSelection(sel, []string{"python"})

	assert.Empty(t, unmatched)
	assert.Equal(t, "go/docker", SerializeSelection(result))
}

func TestRemoveFromSelection_ExtensionWithinTemplate(t *testing.T) {
	sel, _ := ParseSelectDSL("go+linter+docker")

	result, unmatched := RemoveFromSelection(sel, []string{"docker"})

	assert.Empty(t, unmatched)
	assert.Equal(t, "go+linter", SerializeSelection(result))
}

func TestRemoveFromSelection_Unmatched(t *testing.T) {
	sel, _ := ParseSelectDSL("go/python")

	result, unmatched := RemoveFromSelection(sel, []string{"rust"})

	assert.Equal(t, []string{"rust"}, unmatched)
	assert.Equal(t, "go/python", SerializeSelection(result))
}

func TestRemoveFromSelection_EmptiesSelection(t *testing.T) {
	sel, _ := ParseSelectDSL("go")

	result, unmatched := RemoveFromSelection(sel, []string{"go"})

	assert.Empty(t, unmatched)
	assert.Nil(t, result)
}

func TestRemoveFromSelection_NilBase(t *testing.T) {
	result, unmatched := RemoveFromSelection(nil, []string{"go"})
	assert.Nil(t, result)
	assert.Equal(t, []string{"go"}, unmatched)
}

func TestRemoveFromSelection_TemplateNameWinsOverExtensionName(t *testing.T) {
	// "docker" exists both as a top-level template and, hypothetically, as an
	// extension elsewhere; a bare top-level match is removed whole rather than
	// falling through to the extension search.
	sel, _ := ParseSelectDSL("go+docker/docker")

	result, unmatched := RemoveFromSelection(sel, []string{"docker"})

	assert.Empty(t, unmatched)
	assert.Equal(t, "go+docker", SerializeSelection(result))
}
