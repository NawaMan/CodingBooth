// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func headerLines(s string) []string {
	return strings.Split(strings.TrimPrefix(s, "\n"), "\n")
}

func writeSetup(t *testing.T, projectRoot, name, content string) {
	t.Helper()
	dir := filepath.Join(projectRoot, ".booth", "setups")
	require.NoError(t, os.MkdirAll(dir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, name+"--setup.sh"), []byte(content), 0755))
}

func TestParseSetupHeader_NoMarkerIsNotATemplate(t *testing.T) {
	tmpl, err := ParseSetupHeader(headerLines(`
#!/bin/bash
# cb-version: 1.0.0
# A helper, not meant to be selected.
set -e
`), "helper")
	require.NoError(t, err)
	assert.Nil(t, tmpl)
}

func TestParseSetupHeader_MarkerOnly(t *testing.T) {
	tmpl, err := ParseSetupHeader(headerLines(`
#!/bin/bash
# cb-template: DB seed
set -e
`), "db-seed")
	require.NoError(t, err)
	require.NotNil(t, tmpl)

	assert.Equal(t, "db-seed", tmpl.Name)
	assert.Equal(t, "DB seed", tmpl.DisplayName)
	assert.Equal(t, ProjectCategoryName, tmpl.CategoryName)
	assert.True(t, tmpl.Primary)
	assert.Empty(t, tmpl.Params)
	assert.Equal(t, []Segment{{Order: 50, Content: "setup db-seed\n"}}, tmpl.BoothfileSegments)
}

func TestParseSetupHeader_EmptyMarkerUsesName(t *testing.T) {
	tmpl, err := ParseSetupHeader([]string{"# cb-template:"}, "db-seed")
	require.NoError(t, err)
	require.NotNil(t, tmpl)
	assert.Equal(t, "db-seed", tmpl.DisplayName)
}

func TestParseSetupHeader_AllKeys(t *testing.T) {
	tmpl, err := ParseSetupHeader(headerLines(`
#!/usr/bin/env bash
# Copyright notice.

# cb-version:  0.2.0
# cb-template: DB seed
# cb-disc:     Load fixture data into Postgres
# cb-detail:   Runs the SQL in db/fixtures.
# cb-band:     90
# cb-requires: postgresql
# cb-tags:     db, fixtures
# cb-param:    SEED_SET default=small suggests=small,full
# cb-param:    SEED_ROWS default=100
set -Eeuo pipefail
`), "db-seed")
	require.NoError(t, err)
	require.NotNil(t, tmpl)

	assert.Equal(t, "Load fixture data into Postgres", tmpl.DisplayDesc)
	assert.Equal(t, "Runs the SQL in db/fixtures.", tmpl.DisplayDetail)
	assert.Equal(t, "0.2.0", tmpl.CBVersion)
	assert.Equal(t, []string{"postgresql"}, tmpl.Requires)
	assert.Equal(t, []string{"db", "fixtures"}, tmpl.Tags)
	assert.Equal(t, []string{"SEED_SET", "SEED_ROWS"}, tmpl.ParamOrder)
	assert.Equal(t, Param{Default: "small", Suggests: []string{"small", "full"}}, tmpl.Params["SEED_SET"])
	assert.Equal(t, Param{Default: "100"}, tmpl.Params["SEED_ROWS"])
	assert.Equal(t, []Segment{{Order: 90, Content: "setup db-seed ${SEED_SET} ${SEED_ROWS}\n"}}, tmpl.BoothfileSegments)
}

func TestParseSetupHeader_OnlyLeadingCommentBlock(t *testing.T) {
	// A cb-template line after the first code line is not a header.
	tmpl, err := ParseSetupHeader(headerLines(`
#!/bin/bash
set -e
# cb-template: Not a header
`), "x")
	require.NoError(t, err)
	assert.Nil(t, tmpl)

	// Nor is a key after the marker once code starts.
	tmpl, err = ParseSetupHeader(headerLines(`
# cb-template: X
echo hi
# cb-band: 90
`), "x")
	require.NoError(t, err)
	require.NotNil(t, tmpl)
	assert.Equal(t, 50, tmpl.BoothfileSegments[0].Order)
}

func TestParseSetupHeader_Errors(t *testing.T) {
	cases := map[string]struct {
		header string
		want   string
	}{
		"unknown key":      {"# cb-template: X\n# cb-bnad: 90", "unknown key cb-bnad"},
		"bad band":         {"# cb-template: X\n# cb-band: late", "cb-band must be a non-negative number"},
		"duplicate scalar": {"# cb-template: X\n# cb-disc: a\n# cb-disc: b", "cb-disc already set on line 2"},
		"param no name":    {"# cb-template: X\n# cb-param:", "cb-param needs a name"},
		"param bad name":   {"# cb-template: X\n# cb-param: 1X", "must be letters, digits and underscores"},
		"param not attr":   {"# cb-template: X\n# cb-param: P small", `"small" is not attr=value`},
		"param bad attr":   {"# cb-template: X\n# cb-param: P variadic=true", `unknown attribute "variadic"`},
		"param twice":      {"# cb-template: X\n# cb-param: P\n# cb-param: P", "param P declared twice"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := ParseSetupHeader(strings.Split(tc.header, "\n"), "x")
			require.Error(t, err)
			assert.Contains(t, err.Error(), tc.want)
		})
	}
}

func TestParseSetupHeader_UnknownKeyWithoutMarkerIsIgnored(t *testing.T) {
	// Scripts that never opted in must not start failing on a stray cb- comment.
	tmpl, err := ParseSetupHeader([]string{"# cb-whatever: x"}, "x")
	require.NoError(t, err)
	assert.Nil(t, tmpl)
}

func TestLoadSetupHeaderTemplates_IgnoresOtherFiles(t *testing.T) {
	root := t.TempDir()
	writeSetup(t, root, "b-seed", "# cb-template: B\n")
	writeSetup(t, root, "a-seed", "# cb-template: A\n")
	writeSetup(t, root, "helper", "# just a helper\n")
	dir := filepath.Join(root, ".booth", "setups")
	require.NoError(t, os.WriteFile(filepath.Join(dir, "pkg--install.sh"), []byte("# cb-template: no\n"), 0755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("# cb-template: no\n"), 0644))

	templates, err := LoadSetupHeaderTemplates(dir)
	require.NoError(t, err)
	require.Len(t, templates, 2)
	assert.Equal(t, "a-seed", templates[0].Name)
	assert.Equal(t, 1, templates[0].DisplayOrder)
	assert.Equal(t, "b-seed", templates[1].Name)
	assert.Equal(t, 2, templates[1].DisplayOrder)
}

func TestLoadSetupHeaderTemplates_ErrorNamesTheScript(t *testing.T) {
	root := t.TempDir()
	writeSetup(t, root, "seed", "# cb-template: S\n# cb-band: x\n")

	_, err := LoadSetupHeaderTemplates(filepath.Join(root, ".booth", "setups"))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "seed--setup.sh: line 2")
}

func TestLoadSetupHeaderTemplates_MissingDir(t *testing.T) {
	templates, err := LoadSetupHeaderTemplates(filepath.Join(t.TempDir(), "nope"))
	require.NoError(t, err)
	assert.Empty(t, templates)
}

func TestLoadMergedRegistry_SetupHeaderBecomesTemplate(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeSetup(t, projectRoot, "db-seed", "#!/bin/bash\n# cb-template: DB seed\nset -e\n")

	var warn bytes.Buffer
	reg, err := LoadMergedRegistry(stockDir, projectRoot, &warn)
	require.NoError(t, err)
	assert.Empty(t, warn.String())

	require.Contains(t, reg.ByName, "db-seed")
	seed := reg.ByName["db-seed"]
	assert.True(t, seed.Local)
	assert.Equal(t, ProjectCategoryName, seed.CategoryName)

	require.NotEmpty(t, reg.Categories)
	assert.Equal(t, ProjectCategoryName, reg.Categories[0].Name, "project category sorts first (order 0)")
	assert.Equal(t, ProjectCategoryDisplayName, reg.Categories[0].DisplayName)
}

func TestLoadMergedRegistry_TemplateTomlBeatsSetupHeader(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeTemplateTree(t, filepath.Join(projectRoot, ".booth", "templates"), "mine", "db-seed", "Explicit", "setup db-seed --full")
	writeSetup(t, projectRoot, "db-seed", "# cb-template: From header\n")

	var warn bytes.Buffer
	reg, err := LoadMergedRegistry(stockDir, projectRoot, &warn)
	require.NoError(t, err)

	assert.Equal(t, "Explicit", reg.ByName["db-seed"].DisplayName)
	assert.Contains(t, warn.String(), `project template "db-seed" (category "mine") overrides the cb-template header in .booth/setups/db-seed--setup.sh`)
	for _, c := range reg.Categories {
		assert.NotEqual(t, ProjectCategoryName, c.Name, "no empty project category for a header that lost")
	}
}

func TestLoadMergedRegistry_SetupHeaderOverridesStock(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "tools", "lazygit", "Lazygit", "setup lazygit")
	writeSetup(t, projectRoot, "lazygit", "# cb-template: Our lazygit\n")

	var warn bytes.Buffer
	reg, err := LoadMergedRegistry(stockDir, projectRoot, &warn)
	require.NoError(t, err)

	assert.Equal(t, "Our lazygit", reg.ByName["lazygit"].DisplayName)
	assert.Contains(t, warn.String(), `project template "lazygit" overrides built-in`)
	for _, c := range reg.Categories {
		assert.NotEqual(t, "tools", c.Name, "stock category emptied by the override is dropped")
	}
}

func TestLoadMergedRegistry_SetupHeaderJoinsProjectCategory(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	local := filepath.Join(projectRoot, ".booth", "templates")
	writeTemplateTree(t, local, ProjectCategoryName, "lamp-init", "LAMP demo", "setup lamp-init")
	writeSetup(t, projectRoot, "db-seed", "# cb-template: DB seed\n")

	reg, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.NoError(t, err)

	var project *Category
	for _, c := range reg.Categories {
		if c.Name == ProjectCategoryName {
			project = c
		}
	}
	require.NotNil(t, project)
	require.Len(t, project.Templates, 2)
	assert.Equal(t, "lamp-init", project.Templates[0].Name)
	assert.Equal(t, "db-seed", project.Templates[1].Name, "header templates come after template.toml ones")
}

func TestLoadMergedRegistry_BadSetupHeaderFails(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeSetup(t, projectRoot, "seed", "# cb-template: S\n# cb-bnad: 90\n")

	_, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "seed--setup.sh: line 2: unknown key cb-bnad")
}
