// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestInVariant_BaseMeansEveryVariant(t *testing.T) {
	tmpl := &Template{Name: "glow", InVariants: []string{"base"}}
	for _, variant := range []string{"base", "notebook", "codeserver", "desktop-xfce"} {
		assert.True(t, tmpl.InVariant(variant), variant)
	}
}

func TestInVariant_NamedVariantsOnly(t *testing.T) {
	tmpl := &Template{Name: "firefox", InVariants: []string{"desktop-xfce", " desktop-kde "}}
	assert.True(t, tmpl.InVariant("desktop-xfce"))
	assert.True(t, tmpl.InVariant("desktop-kde"))
	assert.False(t, tmpl.InVariant("base"))
	assert.False(t, tmpl.InVariant("notebook"))
}

func TestInVariant_EmptyVariantOrListMatchesNothing(t *testing.T) {
	assert.False(t, (&Template{InVariants: []string{"base"}}).InVariant(""))
	assert.False(t, (&Template{}).InVariant("base"))
	var none *Template
	assert.False(t, none.InVariant("base"))
}

func TestInVariantsText(t *testing.T) {
	assert.Equal(t, "every variant (base image)", (&Template{InVariants: []string{"base"}}).InVariantsText())
	assert.Equal(t, "desktop-kde, notebook", (&Template{InVariants: []string{"notebook", "desktop-kde"}}).InVariantsText())
	assert.Empty(t, (&Template{}).InVariantsText())
}

func TestLoadTemplate_ReadsInVariants(t *testing.T) {
	dir := t.TempDir()
	tmplDir := filepath.Join(dir, "glow")
	require.NoError(t, os.MkdirAll(tmplDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "template.toml"), []byte(
		"display-name = \"glow\"\nin-variants = [\"base\"]\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "extra--extension.toml"), []byte(
		"display-name = \"extra\"\nin-variants = [\"notebook\"]\n"), 0644))

	tmpl, err := loadTemplateDir(tmplDir, "glow", "tools", true)
	require.NoError(t, err)
	assert.Equal(t, []string{"base"}, tmpl.InVariants)
	require.Len(t, tmpl.Extensions, 1)
	assert.Equal(t, []string{"notebook"}, tmpl.Extensions[0].InVariants)
}

func TestFormatTemplateDetail_ShowsInImage(t *testing.T) {
	var buf bytes.Buffer
	FormatTemplateDetail(&buf, &Template{Name: "glow", InVariants: []string{"base"}}, &TemplateRegistry{}, false)
	assert.Contains(t, buf.String(), "In image:    every variant (base image)")

	buf.Reset()
	FormatTemplateDetail(&buf, &Template{Name: "go"}, &TemplateRegistry{}, false)
	assert.NotContains(t, buf.String(), "In image:")
}

// --- The catalog against the variant Dockerfiles ---

var (
	setupScriptRef = regexp.MustCompile(`([a-z0-9][a-z0-9-]*)--setup\.sh`)
	segmentSetup   = regexp.MustCompile(`(?m)^\s*setup\s+([A-Za-z0-9_-]+)`)
)

// scriptRefs returns the <name>--setup.sh scripts a file runs, skipping comment
// lines (the setups document what they expect of each other in comments).
func scriptRefs(t *testing.T, path string) []string {
	t.Helper()
	content, err := os.ReadFile(path)
	require.NoError(t, err)
	var names []string
	for _, line := range strings.Split(string(content), "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		for _, match := range setupScriptRef.FindAllStringSubmatch(line, -1) {
			names = append(names, match[1])
		}
	}
	return names
}

// variantSetups maps each variant to every setup its image runs: its own
// Dockerfile's, base's (every variant is built FROM base), and the setups those
// call in turn.
func variantSetups(t *testing.T, variantsDir string) map[string]map[string]bool {
	t.Helper()
	setupsDir := filepath.Join(variantsDir, "base", "setups")
	closure := func(start []string) map[string]bool {
		seen := map[string]bool{}
		queue := append([]string{}, start...)
		for len(queue) > 0 {
			name := queue[0]
			queue = queue[1:]
			if seen[name] {
				continue
			}
			seen[name] = true
			script := filepath.Join(setupsDir, name+"--setup.sh")
			if _, err := os.Stat(script); err == nil {
				queue = append(queue, scriptRefs(t, script)...)
			}
		}
		return seen
	}

	entries, err := os.ReadDir(variantsDir)
	require.NoError(t, err)
	base := scriptRefs(t, filepath.Join(variantsDir, "base", "Dockerfile"))
	result := map[string]map[string]bool{}
	for _, entry := range entries {
		dockerfile := filepath.Join(variantsDir, entry.Name(), "Dockerfile")
		if _, err := os.Stat(dockerfile); err != nil {
			continue
		}
		start := base
		if entry.Name() != BaseVariant {
			start = append(append([]string{}, base...), scriptRefs(t, dockerfile)...)
		}
		result[entry.Name()] = closure(start)
	}
	require.Contains(t, result, BaseVariant)
	return result
}

// TestCatalogInVariantsMatchVariantImages keeps `in-variants` honest. For every
// catalog item that runs setup scripts, the variants it declares must be exactly
// the variants whose image already runs all of them — so a variant that gains a
// tool, or loses one, fails here until the template says so. Items with no setup
// line (an `install apt` one, say) cannot be checked this way; their values only
// have to name real variants.
func TestCatalogInVariantsMatchVariantImages(t *testing.T) {
	templatesDir := repoTemplatesDir(t)
	variantsDir := filepath.Join(filepath.Dir(templatesDir), "variants")
	if _, err := os.Stat(variantsDir); err != nil {
		t.Skipf("variants directory not found: %s", variantsDir)
	}
	images := variantSetups(t, variantsDir)
	var variants []string
	for name := range images {
		variants = append(variants, name)
	}
	sort.Strings(variants)

	registry, err := LoadRegistry(templatesDir)
	require.NoError(t, err)

	check := func(label string, item *Template) {
		declared := map[string]bool{}
		for _, v := range item.InVariants {
			v = strings.TrimSpace(v)
			if _, ok := images[v]; !ok {
				t.Errorf("%s: in-variants names %q, which is not a variant (have %v)", label, v, variants)
				continue
			}
			if v == BaseVariant {
				for _, all := range variants {
					declared[all] = true
				}
			} else {
				declared[v] = true
			}
		}

		var setups []string
		for _, seg := range item.BoothfileSegments {
			for _, match := range segmentSetup.FindAllStringSubmatch(seg.Content, -1) {
				setups = append(setups, match[1])
			}
		}
		if len(setups) == 0 {
			return
		}
		for _, variant := range variants {
			inImage := true
			for _, name := range setups {
				if !images[variant][name] {
					inImage = false
					break
				}
			}
			switch {
			case inImage && !declared[variant]:
				t.Errorf("%s: the %s image already runs %v — add %q to in-variants", label, variant, setups, variant)
			case !inImage && declared[variant]:
				t.Errorf("%s: in-variants lists %q, but the %s image does not run %v", label, variant, variant, setups)
			}
		}
	}

	for _, category := range registry.Categories {
		for _, tmpl := range category.Templates {
			check(tmpl.Name, tmpl)
			for _, ext := range tmpl.Extensions {
				check(tmpl.Name+"+"+ext.Name, ext)
			}
		}
	}
}

// TestCatalogRemoveNeedsInVariants: a remove step takes a tool out of an image,
// so it only means something on an item that says which images ship it. An item
// with `remove` and no `in-variants` would offer nothing (Removable is false),
// which is a declaration mistake worth catching here rather than in the TUI.
func TestCatalogRemoveNeedsInVariants(t *testing.T) {
	registry, err := LoadRegistry(repoTemplatesDir(t))
	require.NoError(t, err)
	check := func(label string, item *Template) {
		if strings.TrimSpace(item.Remove) != "" && len(item.InVariants) == 0 {
			t.Errorf("%s: declares remove but no in-variants", label)
		}
	}
	removable := 0
	for _, category := range registry.Categories {
		for _, tmpl := range category.Templates {
			check(tmpl.Name, tmpl)
			if tmpl.Removable() {
				removable++
			}
			for _, ext := range tmpl.Extensions {
				check(tmpl.Name+"+"+ext.Name, ext)
			}
		}
	}
	assert.Equal(t, 8, removable, "glow, lazygit, superfile, differ, just, ttt, firefox, google-chrome")
}

func TestRemovable(t *testing.T) {
	assert.True(t, (&Template{InVariants: []string{"base"}, Remove: "run rm -f /x"}).Removable())
	assert.False(t, (&Template{InVariants: []string{"base"}}).Removable(), "no remove step")
	assert.False(t, (&Template{Remove: "run rm -f /x"}).Removable(), "in no image")
	assert.False(t, (&Template{InVariants: []string{"base"}, Remove: "  \n"}).Removable(), "blank step")
}
