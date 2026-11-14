// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"errors"
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

// --- RemovePath ---

func dsl(t *testing.T, text string) *ParsedSelection {
	t.Helper()
	sel, err := ParseSelectDSL(text)
	require.NoError(t, err, text)
	return sel
}

func removed(t *testing.T, text, path string) string {
	t.Helper()
	result, err := RemovePath(dsl(t, text), path)
	require.NoError(t, err, "remove %q from %q", path, text)
	return SerializeSelection(result)
}

func TestRemovePath_WholeTemplateTakesItsSubtree(t *testing.T) {
	assert.Equal(t, "python/docker", removed(t, "go:1.24+linter~credential/python/docker", "go"))
}

func TestRemovePath_ExtensionUnderItsTemplate(t *testing.T) {
	assert.Equal(t, "go+linter/ttt+lsp", removed(t, "go+linter+lsp/ttt+lsp", "go+lsp"))
	assert.Equal(t, "go+linter+lsp/ttt", removed(t, "go+linter+lsp/ttt+lsp", "ttt+lsp"))
}

func TestRemovePath_Exclusion(t *testing.T) {
	assert.Equal(t, "go+linter", removed(t, "go+linter~credential", "go~credential"))
}

func TestRemovePath_RootRemoval(t *testing.T) {
	assert.Equal(t, "go", removed(t, "go/~glow", "~glow"), "~glow clears only a removal")
	assert.Equal(t, "go", removed(t, "go/~glow", "glow"), "a bare name clears the slot whatever it holds")
}

func TestRemovePath_TemplateNameWinsOverExtensionName(t *testing.T) {
	assert.Equal(t, "go+docker", removed(t, "go+docker/docker", "docker"))
}

func TestRemovePath_EmptiesSelection(t *testing.T) {
	result, err := RemovePath(dsl(t, "go"), "go")
	require.NoError(t, err)
	assert.Nil(t, result)
}

func TestRemovePath_BareExtensionNameIsRefusedWithPaths(t *testing.T) {
	sel := dsl(t, "go+lsp/ttt+lsp/python~lsp")
	_, err := RemovePath(sel, "lsp")
	require.Error(t, err)
	var noMatch *NoMatchError
	assert.False(t, errors.As(err, &noMatch), "an ambiguous name is a refusal, not a miss")
	assert.Contains(t, err.Error(), "go+lsp or ttt+lsp or python~lsp")
	assert.Equal(t, "go+lsp/ttt+lsp/python~lsp", SerializeSelection(sel), "the selection is not touched")
}

func TestRemovePath_EvenAUniqueBareExtensionNameIsRefused(t *testing.T) {
	_, err := RemovePath(dsl(t, "go+linter"), "linter")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "go+linter")
}

func TestRemovePath_NoMatch(t *testing.T) {
	for _, tc := range []struct{ sel, path, reason string }{
		{"go/python", "rust", ""},
		{"go", "go+lsp", ""},
		{"python", "go+lsp", "go is not selected"},
		{"go~lsp", "go+lsp", "go~lsp is what the selection holds"},
		{"go+lsp", "go~lsp", "go+lsp is what the selection holds"},
		{"glow", "~glow", "glow is selected, not removed"},
		{"go", "~glow", ""},
	} {
		_, err := RemovePath(dsl(t, tc.sel), tc.path)
		var noMatch *NoMatchError
		require.True(t, errors.As(err, &noMatch), "%q from %q: %v", tc.path, tc.sel, err)
		assert.Contains(t, err.Error(), tc.reason, "%q from %q", tc.path, tc.sel)
	}
	_, err := RemovePath(nil, "go")
	var noMatch *NoMatchError
	assert.True(t, errors.As(err, &noMatch), "nothing to remove from")
}

func TestRemovePath_RefusesWhatIsNotOnePath(t *testing.T) {
	sel := dsl(t, "go:1.24+linter+lsp")
	for path, want := range map[string]string{
		"@web":          "is a recipe, not a node",
		"go:1.24":       "not its params",
		"go+linter+lsp": "template+extension",
		"go/python":     "one node",
		"~go+linter":    "a template name only",
		"":              "empty",
		"+linter":       "template+extension",
	} {
		_, err := RemovePath(sel, path)
		require.Error(t, err, path)
		assert.Contains(t, err.Error(), want, path)
	}
}

// --- Merging: a node written without params is only the way to its children ---

func merged(t *testing.T, base, add string) string {
	t.Helper()
	return SerializeSelection(MergeSelections(dsl(t, base), dsl(t, add)))
}

func TestMergeSelections_PathThroughParentKeepsParent(t *testing.T) {
	assert.Equal(t, `go:1.22+linter+go-pkg:a+lsp`, merged(t, `go:1.22+linter+go-pkg:a`, "go+lsp"))
	assert.Equal(t, `go:1.22+linter`, merged(t, `go:1.22+linter`, "go"), "naming go again changes nothing")
	assert.Equal(t, `go:1.22+go-pkg:a`, merged(t, `go:1.22+go-pkg:a`, "go+go-pkg"), "nor naming its extension")
}

func TestMergeSelections_ParamsWrittenReplace(t *testing.T) {
	assert.Equal(t, `go:1.23+linter+lsp`, merged(t, `go:1.22+linter`, "go:1.23+lsp"))
	assert.Equal(t, `go+go-pkg:c`, merged(t, `go+go-pkg:a,b`, "go+go-pkg:c"), "a list param is replaced, not appended to")
}

func TestMergeSelections_EmptyParamListResets(t *testing.T) {
	sel := MergeSelections(dsl(t, "go:1.22+go-pkg:a"), dsl(t, "go:+go-pkg:"))
	assert.Equal(t, "go:+go-pkg:", SerializeSelection(sel), "the reset reaches the compiler")
	assert.Equal(t, "go+go-pkg", SerializeSelection(StripParamResets(sel)), "the header records the node")
	assert.Equal(t, "go:1.24", merged(t, "go:", "go:1.24"), "params written after a reset replace it")
}

func TestMergeSelections_PlusAndTildeShareASlot(t *testing.T) {
	assert.Equal(t, "go+linter+lsp", merged(t, "go+linter~lsp", "go+lsp"))
	assert.Equal(t, "go+linter~lsp", merged(t, "go+linter+lsp", "go~lsp"))
	assert.Equal(t, "go/~glow", merged(t, "go/glow+theme", "~glow"))
	assert.Equal(t, "go/glow", merged(t, "go/~glow", "glow"))
}

// --- SelectionEditor: command-line order, and nodes that come back new ---

func TestSelectionEditor_LaterWriteWins(t *testing.T) {
	e := NewSelectionEditor(dsl(t, "go+linter"))
	e.Add(dsl(t, "go+lsp"))
	require.NoError(t, e.Remove("go+lsp"))
	assert.Equal(t, "go+linter", SerializeSelection(e.Selection()))

	e = NewSelectionEditor(dsl(t, "go+linter"))
	require.NoError(t, e.Remove("go+linter"))
	e.Add(dsl(t, "go+linter"))
	assert.Equal(t, "go+linter:", SerializeSelection(e.Selection()))
}

func TestSelectionEditor_RemovedThenAddedComesBackAtDefaults(t *testing.T) {
	e := NewSelectionEditor(dsl(t, "go:1.22+linter+go-pkg:a/python"))
	require.NoError(t, e.Remove("go"))
	e.Add(dsl(t, "go+go-pkg"))
	sel := e.Selection()
	assert.Equal(t, "python/go:+go-pkg:", SerializeSelection(sel), "old pins in the Boothfile must not come back")
	assert.Equal(t, "python/go+go-pkg", SerializeSelection(StripParamResets(sel)))

	e = NewSelectionEditor(dsl(t, "go:1.22"))
	require.NoError(t, e.Remove("go"))
	e.Add(dsl(t, "go:1.25"))
	assert.Equal(t, "go:1.25", SerializeSelection(e.Selection()), "params written win as usual")
}

func TestSelectionEditor_FailedRemoveLeavesSelection(t *testing.T) {
	e := NewSelectionEditor(dsl(t, "go+lsp/ttt+lsp"))
	require.Error(t, e.Remove("lsp"))
	assert.Equal(t, "go+lsp/ttt+lsp", SerializeSelection(e.Selection()))
}

func TestSelectionEditor_EmptyIsNil(t *testing.T) {
	e := NewSelectionEditor(dsl(t, "go"))
	require.NoError(t, e.Remove("go"))
	assert.Nil(t, e.Selection())
}
