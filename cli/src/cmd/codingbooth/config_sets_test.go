// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --set merges key by key

func TestMergeSets_KeepsKeysNotGivenNow(t *testing.T) {
	// One --set used to replace the whole baseline: timezone vanished here.
	got := mergeSets(
		[]string{"egress-allowlist=a.com", "timezone=Asia/Bangkok"},
		[]string{"egress-allowlist=b.com"})
	assert.Equal(t, []string{"egress-allowlist=b.com", "timezone=Asia/Bangkok"}, got)
}

func TestMergeSets_ListKeyReplacesEveryBaselineEntry(t *testing.T) {
	got := mergeSets(
		[]string{"cache-dirs=one", "silence-build", "cache-dirs=two"},
		[]string{"cache-dirs=three", "cache-dirs=four"})
	assert.Equal(t, []string{"cache-dirs=three", "cache-dirs=four", "silence-build"}, got)
}

func TestMergeSets_NewKeyIsAppended(t *testing.T) {
	got := mergeSets([]string{"dind"}, []string{"timezone=UTC"})
	assert.Equal(t, []string{"dind", "timezone=UTC"}, got)
}

func TestMergeSets_NoCLISetsKeepsBaseline(t *testing.T) {
	base := []string{"common-args=--platform", "common-args=linux/amd64"}
	assert.Equal(t, base, mergeSets(base, nil))
}

func TestDropReadBackForSets_ClearsOnlyTheKeysSetNow(t *testing.T) {
	merged := initFlags{cacheDirs: []string{"one"}, cacheFiles: []string{"f"}}
	dropReadBackForSets(&merged, []string{"cache-dirs=two"})
	assert.Nil(t, merged.cacheDirs)
	assert.Equal(t, []string{"f"}, merged.cacheFiles)
}

// commas split value lists, never argv lists

func TestExpandSet_SplitsValueListOnCommas(t *testing.T) {
	got, err := expandSet("egress-allowlist=c.com, d.com,,")
	require.NoError(t, err)
	assert.Equal(t, []string{"egress-allowlist=c.com", "egress-allowlist=d.com"}, got)
}

func TestExpandSet_ArgvListKeepsTheComma(t *testing.T) {
	for _, set := range []string{
		"run-args=type=bind,src=/a,dst=/b",
		"common-args=${X:-a,b}",
		"build-args=A=1,2",
		"cmds=echo a,b",
	} {
		got, err := expandSet(set)
		require.NoError(t, err)
		assert.Equal(t, []string{set}, got)
	}
}

func TestExpandSet_ScalarKeepsTheComma(t *testing.T) {
	got, err := expandSet("timezone=a,b")
	require.NoError(t, err)
	assert.Equal(t, []string{"timezone=a,b"}, got)
}

func TestExpandSet_OnlyCommasIsAnError(t *testing.T) {
	_, err := expandSet("egress-allowlist=,")
	assert.ErrorContains(t, err, "--unset egress-allowlist")
}

func TestParseInitFlags_SetCommaIsRecordedOnePerItem(t *testing.T) {
	flags := parseInitFlags([]string{"--set", "cache-dirs=a,b"})
	assert.Equal(t, []string{"cache-dirs=a", "cache-dirs=b"}, flags.sets)
}

func TestParseSetOverrides_CommaSplitsValueList(t *testing.T) {
	// A header written before commas split reads back as separate items.
	result, err := parseSetOverrides([]string{"egress-allowlist=a.com,b.com"})
	require.NoError(t, err)
	assert.Equal(t, []string{"a.com", "b.com"}, result["egress-allowlist"])
}

// --unset

func TestParseInitFlags_Unset(t *testing.T) {
	flags := parseInitFlags([]string{"--unset", "timezone", "--unset", "cache-dirs"})
	assert.Equal(t, []string{"timezone", "cache-dirs"}, flags.unsets)
}

func TestApplyUnsets_DropsSetsReadBackAndDedicatedFields(t *testing.T) {
	merged := initFlags{
		sets:      []string{"timezone=UTC", "cache-dirs=one", "dind"},
		cacheDirs: []string{"one", "two"},
		variant:   "xfce",
	}
	require.NoError(t, applyUnsets(&merged, []string{"timezone", "cache-dirs", "variant"}))
	assert.Equal(t, []string{"dind"}, merged.sets)
	assert.Nil(t, merged.cacheDirs)
	assert.Empty(t, merged.variant)
}

func TestApplyUnsets_KeyNotHeldIsAnError(t *testing.T) {
	merged := initFlags{sets: []string{"dind"}}
	err := applyUnsets(&merged, []string{"timezone"})
	assert.ErrorContains(t, err, "--unset timezone")
}

func TestValidateUnsets_UnknownKeySuggests(t *testing.T) {
	err := validateUnsets(initFlags{unsets: []string{"timezon"}})
	assert.ErrorContains(t, err, `Did you mean "timezone"`)
}

func TestValidateUnsets_RefusesSetAndUnsetOfOneKey(t *testing.T) {
	err := validateUnsets(initFlags{unsets: []string{"timezone"}, sets: []string{"timezone=UTC"}})
	assert.ErrorContains(t, err, "cannot be combined")
}

func TestValidateUnsets_RefusesDedicatedFlagAndUnset(t *testing.T) {
	err := validateUnsets(initFlags{unsets: []string{"cmds"}, cmds: []string{"bash"}})
	assert.ErrorContains(t, err, "--cmd and --unset cmds")
}

// --remove-* errors on no match

func TestRemoveByKey_ByKey(t *testing.T) {
	got, err := removeByKey([]string{"FOO=1", "BAR=2"}, []string{"FOO"}, envKey, "env")
	require.NoError(t, err)
	assert.Equal(t, []string{"BAR=2"}, got)
}

func TestRemoveByKey_ByWholeEntry(t *testing.T) {
	got, err := removeByKey([]string{"FOO=1", "BAR=2"}, []string{"FOO=1"}, envKey, "env")
	require.NoError(t, err)
	assert.Equal(t, []string{"BAR=2"}, got)
}

func TestRemoveByKey_DifferentValueIsAnErrorThatShowsTheEntry(t *testing.T) {
	_, err := removeByKey([]string{"FOO=2"}, []string{"FOO=1"}, envKey, "env")
	assert.ErrorContains(t, err, `--remove-env "FOO=1" did not match`)
	assert.ErrorContains(t, err, `(it has "FOO=2")`)
}

func TestRemoveByKey_NoMatchIsAnError(t *testing.T) {
	_, err := removeByKey([]string{"18080:8080"}, []string{"9000"}, exposeKey, "expose")
	assert.ErrorContains(t, err, `--remove-expose "9000" did not match`)
}
