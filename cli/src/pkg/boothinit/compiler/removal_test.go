// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package compiler

import (
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCompile_RemovalComesAfterEverySetup(t *testing.T) {
	goT := &tmpl.Template{Name: "go", BoothfileSegments: []tmpl.Segment{
		{Order: 30, Content: "setup go"},
		{Order: 90, Content: "run go mod download"},
	}}
	glow := &tmpl.Template{Name: "glow", InVariants: []string{"base"},
		Remove: "run rm -f /usr/local/bin/glow\n"}
	out, err := Compile(&selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{{Template: goT}},
		Removed:   []*tmpl.Template{glow},
	})
	require.NoError(t, err)

	content := out.Boothfile.Content
	setupAt := strings.Index(content, "run go mod download")
	removeAt := strings.Index(content, "run rm -f /usr/local/bin/glow")
	require.GreaterOrEqual(t, setupAt, 0)
	require.GreaterOrEqual(t, removeAt, 0, content)
	assert.Less(t, setupAt, removeAt, "the removal runs after the post-setup band")
	assert.Contains(t, content, "# ~glow: glow is in the variant image; removed by this selection")
}

func TestCompile_RemovalAloneEmitsOnlyTheRemoval(t *testing.T) {
	glow := &tmpl.Template{Name: "glow", InVariants: []string{"base"}, Remove: "run rm -f /usr/local/bin/glow",
		BoothfileSegments: []tmpl.Segment{{Order: 45, Content: "setup glow"}}}
	out, err := Compile(&selection.ResolvedSelection{Removed: []*tmpl.Template{glow}})
	require.NoError(t, err)
	assert.NotContains(t, out.Boothfile.Content, "setup glow", "a removed template is not installed")
	assert.Contains(t, out.Boothfile.Content, "run rm -f /usr/local/bin/glow")
}
