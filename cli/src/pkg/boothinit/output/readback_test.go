// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConfigTomlComments_WholeLineAndTrailing(t *testing.T) {
	content := "# Configured by: booth config --no-tui --overwrite --select go\n" +
		"\n" +
		"# team port\n" +
		"port = \"10080\"  # keep in sync with the proxy\n" +
		"timezone = \"Asia/Bangkok\"\n"

	assert.Equal(t, []Comment{
		{Line: 3, Text: "# team port"},
		{Line: 4, Text: "# keep in sync with the proxy"},
	}, ConfigTomlComments(content), "the header is booth config's own, not a comment to lose")
}

func TestConfigTomlComments_HashInsideStringIsNotAComment(t *testing.T) {
	content := "run-args = [\"--env\", \"COLOR=#fff\"]\n" +
		"name = 'a#b'  # real\n" +
		"quoted = \"say \\\"#hi\\\"\"\n"

	assert.Equal(t, []Comment{{Line: 2, Text: "# real"}}, ConfigTomlComments(content))
}

func TestBoothfileComments_OnlyWholeLinesAndNotOwned(t *testing.T) {
	content := "# syntax=codingbooth/boothfile:1\n" +
		"# Configured by: booth config --no-tui --overwrite --select go\n" +
		"\n" +
		"  # indented note\n" +
		"setup go 1.26   # template comment on a directive line\n"

	assert.Equal(t, []Comment{{Line: 4, Text: "# indented note"}}, BoothfileComments(content))
}

func TestBoothfileDirectives_IgnoresCommentsAndSpacing(t *testing.T) {
	a := "# syntax=codingbooth/boothfile:1\n\nenv A=1\n# note\n  setup go 1.26  \n"
	b := "env A=1\nsetup go 1.26\n"
	assert.Equal(t, BoothfileDirectives(b), BoothfileDirectives(a))
	assert.Equal(t, []string{"env A=1", "setup go 1.26"}, BoothfileDirectives(a))
}

func TestLostComments_MatchesOneForOne(t *testing.T) {
	before := []Comment{{1, "# a"}, {2, "# b"}, {3, "# a"}}
	after := []Comment{{9, "# a"}}
	assert.Equal(t, []Comment{{2, "# b"}, {3, "# a"}}, LostComments(before, after))
}

func TestManifest_RecordsTemplatesVersion(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	writeBooth(t, dir, "Boothfile", generatedBoothfile)

	require.NoError(t, writeManifest(boothDir, map[string]string{"Boothfile": hashContent(generatedBoothfile)}, "0.77.0"))
	assert.Equal(t, "0.77.0", ReadTemplatesVersion(dir))
	assert.Empty(t, Drifted(dir), "the version entry is not a file and must not read as drift")

	require.NoError(t, writeManifest(boothDir, map[string]string{"Boothfile": hashContent(generatedBoothfile)}, ""))
	assert.Empty(t, ReadTemplatesVersion(dir),
		"a local catalog replaces the record — the old version no longer wrote these files")
}
