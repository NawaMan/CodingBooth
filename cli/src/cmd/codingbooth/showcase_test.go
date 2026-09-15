// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSplitHandleSlug_Valid(t *testing.T) {
	handle, slug, err := splitHandleSlug("NawaMan-GMail/defaultj")
	require.NoError(t, err)
	assert.Equal(t, "NawaMan-GMail", handle)
	assert.Equal(t, "defaultj", slug)
}

func TestSplitHandleSlug_Invalid(t *testing.T) {
	cases := []string{
		"no-slash",
		"too/many/slashes",
		"/missing-handle",
		"missing-slug/",
		"",
	}
	for _, c := range cases {
		_, _, err := splitHandleSlug(c)
		assert.Errorf(t, err, "expected error for %q", c)
	}
}

func TestParseShowcaseFlags(t *testing.T) {
	limit, cursor, ver, asJSON := parseShowcaseFlags([]string{"--limit", "5", "--cursor", "abc", "--version", "3", "--json"})
	assert.Equal(t, "5", limit)
	assert.Equal(t, "abc", cursor)
	assert.Equal(t, "3", ver)
	assert.True(t, asJSON)
}

func TestParseShowcaseFlags_Empty(t *testing.T) {
	limit, cursor, ver, asJSON := parseShowcaseFlags(nil)
	assert.Equal(t, "", limit)
	assert.Equal(t, "", cursor)
	assert.Equal(t, "", ver)
	assert.False(t, asJSON)
}
