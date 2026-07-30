// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- QuoteParam ---

func TestQuoteParam_LeavesPlainValuesAlone(t *testing.T) {
	for _, v := range []string{"", "1.25.7", "gopls@latest", "openjdk", "bat"} {
		assert.Equal(t, v, QuoteParam(v))
	}
}

func TestQuoteParam_QuotesModulePath(t *testing.T) {
	assert.Equal(t, `"github.com/user/tool@latest"`, QuoteParam("github.com/user/tool@latest"))
}

func TestQuoteParam_QuotesCommaAndTilde(t *testing.T) {
	assert.Equal(t, `"a,b"`, QuoteParam("a,b"))
	assert.Equal(t, `"a~b"`, QuoteParam("a~b"))
}

func TestQuoteParam_QuotesWhitespace(t *testing.T) {
	assert.Equal(t, `"two words"`, QuoteParam("two words"))
}

// A "+" is left alone: splitExtensions already keeps it with the value unless a
// letter follows, and quoting it would rewrite existing headers for nothing.
func TestQuoteParam_LeavesPlusAlone(t *testing.T) {
	assert.Equal(t, "+19000", QuoteParam("+19000"))
	assert.Equal(t, "libstdc++6", QuoteParam("libstdc++6"))
}

// Only the first ":" of an item separates, so a second one needs no quoting.
func TestQuoteParam_LeavesColonAlone(t *testing.T) {
	assert.Equal(t, "jsr:@luca", QuoteParam("jsr:@luca"))
}

func TestQuoteParam_PicksTheQuoteTheValueLacks(t *testing.T) {
	assert.Equal(t, `'say "hi"/now'`, QuoteParam(`say "hi"/now`))
}

func TestQuoteParam_BothQuotesIsLeftUnquoted(t *testing.T) {
	// Unrepresentable — the DSL has no escape. Better an unquoted value that
	// fails loudly than a quoted one that truncates at the inner quote.
	v := `a"b'c/d`
	assert.Equal(t, v, QuoteParam(v))
}

// --- QuoteVariadic ---

func TestQuoteVariadic_QuotesEachElement(t *testing.T) {
	assert.Equal(t,
		`"github.com/a/b@v1","github.com/c/d@v2"`,
		QuoteVariadic("github.com/a/b@v1,github.com/c/d@v2"))
}

func TestQuoteVariadic_LeavesPlainListAlone(t *testing.T) {
	assert.Equal(t, "htop,jq", QuoteVariadic("htop,jq"))
}

func TestQuoteVariadic_DropsBlanksAndTrims(t *testing.T) {
	assert.Equal(t, "htop,jq", QuoteVariadic("htop, , jq ,"))
}

func TestQuoteVariadic_MixedListQuotesOnlyWhatNeedsIt(t *testing.T) {
	assert.Equal(t, `bat,"github.com/a/b@v1"`, QuoteVariadic("bat,github.com/a/b@v1"))
}

// --- Unquote ---

func TestUnquote(t *testing.T) {
	assert.Equal(t, "a/b", Unquote(`"a/b"`))
	assert.Equal(t, "a/b", Unquote(`'a/b'`))
	assert.Equal(t, "a/b", Unquote("a/b"))
	assert.Equal(t, `"`, Unquote(`"`))     // single char, nothing to strip
	assert.Equal(t, `"a'`, Unquote(`"a'`)) // mismatched pair, left alone
}

// --- splitUnquoted / fieldsUnquoted ---

func TestSplitUnquoted_IgnoresSeparatorsInsideQuotes(t *testing.T) {
	assert.Equal(t,
		[]string{`go+go-pkg:"github.com/a/b@v1"`, "claude-code"},
		splitUnquoted(`go+go-pkg:"github.com/a/b@v1"/claude-code`, '/'))
}

func TestSplitUnquoted_UnquotedBehavesLikeSplit(t *testing.T) {
	assert.Equal(t, []string{"go", "python", "java"}, splitUnquoted("go/python/java", '/'))
}

func TestFieldsUnquoted_KeepsQuotedWhitespaceTogether(t *testing.T) {
	assert.Equal(t, []string{`a:"one two"`, "b"}, fieldsUnquoted(`a:"one two"  b`))
}

// --- ParseSelectDSL with quoted values ---

func TestParseSelectDSL_QuotedModulePathIsOneValue(t *testing.T) {
	parsed, err := ParseSelectDSL(`go+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest"`)
	require.NoError(t, err)
	require.Len(t, parsed.Items, 1)
	assert.Equal(t, "go", parsed.Items[0].Name)
	require.Len(t, parsed.Items[0].Extensions, 1)
	assert.Equal(t, "go-pkg", parsed.Items[0].Extensions[0].Name)
	assert.Equal(t,
		[]string{"github.com/pocketbase/pocketbase/examples/base@latest"},
		parsed.Items[0].Extensions[0].Params)
}

func TestParseSelectDSL_SingleQuotesWorkToo(t *testing.T) {
	parsed, err := ParseSelectDSL(`go+go-pkg:'github.com/a/b@v1'`)
	require.NoError(t, err)
	assert.Equal(t, []string{"github.com/a/b@v1"}, parsed.Items[0].Extensions[0].Params)
}

func TestParseSelectDSL_QuotedValueThenAnotherTemplate(t *testing.T) {
	parsed, err := ParseSelectDSL(`go+go-pkg:"github.com/a/b@v1"/claude-code+auto-accept`)
	require.NoError(t, err)
	require.Len(t, parsed.Items, 2)
	assert.Equal(t, []string{"github.com/a/b@v1"}, parsed.Items[0].Extensions[0].Params)
	assert.Equal(t, "claude-code", parsed.Items[1].Name)
	require.Len(t, parsed.Items[1].Extensions, 1)
	assert.Equal(t, "auto-accept", parsed.Items[1].Extensions[0].Name)
}

func TestParseSelectDSL_QuotedValueThenExtension(t *testing.T) {
	parsed, err := ParseSelectDSL(`go+go-pkg:"github.com/a/b@v1"+vscode-ext`)
	require.NoError(t, err)
	require.Len(t, parsed.Items, 1)
	require.Len(t, parsed.Items[0].Extensions, 2)
	assert.Equal(t, "go-pkg", parsed.Items[0].Extensions[0].Name)
	assert.Equal(t, "vscode-ext", parsed.Items[0].Extensions[1].Name)
}

func TestParseSelectDSL_QuotedValueThenExclusion(t *testing.T) {
	parsed, err := ParseSelectDSL(`go+go-pkg:"github.com/a/b@v1"~vscode-ext`)
	require.NoError(t, err)
	require.Len(t, parsed.Items, 1)
	assert.Equal(t, []string{"github.com/a/b@v1"}, parsed.Items[0].Extensions[0].Params)
	assert.Equal(t, []string{"vscode-ext"}, parsed.Items[0].Excludes)
}

func TestParseSelectDSL_MultipleQuotedPackages(t *testing.T) {
	parsed, err := ParseSelectDSL(`nodejs+npm-pkg:"@types/node","@types/react"`)
	require.NoError(t, err)
	assert.Equal(t,
		[]string{"@types/node", "@types/react"},
		parsed.Items[0].Extensions[0].Params)
}

func TestParseSelectDSL_QuotedTemplateParam(t *testing.T) {
	parsed, err := ParseSelectDSL(`mytool:"a/b"/go`)
	require.NoError(t, err)
	require.Len(t, parsed.Items, 2)
	assert.Equal(t, []string{"a/b"}, parsed.Items[0].Params)
	assert.Equal(t, "go", parsed.Items[1].Name)
}

// A quoted value keeps a "+" whatever follows it, unlike the bare-value heuristic.
func TestParseSelectDSL_QuotedPlusIsNotAnExtension(t *testing.T) {
	parsed, err := ParseSelectDSL(`apt+apt-pkg:"libstdc++6"`)
	require.NoError(t, err)
	require.Len(t, parsed.Items, 1)
	require.Len(t, parsed.Items[0].Extensions, 1)
	assert.Equal(t, []string{"libstdc++6"}, parsed.Items[0].Extensions[0].Params)
}

// An unquoted "/" still splits. Ambiguous by construction — "go:1.25.7/claude-code"
// has the same shape — so this stays the documented behaviour, with a hint in the
// resolver's error. See TestResolve_UnquotedSlashHint.
func TestParseSelectDSL_UnquotedSlashStillSplits(t *testing.T) {
	parsed, err := ParseSelectDSL("go+go-pkg:github.com/user/tool@latest")
	require.NoError(t, err)
	require.Len(t, parsed.Items, 3)
	assert.Equal(t, "go", parsed.Items[0].Name)
	assert.Equal(t, "user", parsed.Items[1].Name)
	assert.Equal(t, "tool@latest", parsed.Items[2].Name)
}

// --- NormalizeInput with quoted values ---

func TestNormalizeInput_KeepsQuotedSpaces(t *testing.T) {
	assert.Equal(t, `a:"one two"/b`, NormalizeInput(`a:"one two"  b`))
}

func TestNormalizeInput_DoesNotEatOperatorsInsideQuotes(t *testing.T) {
	assert.Equal(t, `a:"x + y"`, NormalizeInput(`a:"x + y"`))
}

func TestNormalizeInput_SpacesAroundOperatorsOutsideQuotes(t *testing.T) {
	assert.Equal(t, `go+go-pkg:"a/b"+vscode-ext`, NormalizeInput(`go + go-pkg:"a/b" + vscode-ext`))
}
