// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package compiler

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func boolPtr(b bool) *bool { return &b }

// --- Single template ---

func TestCompile_SingleTemplateBoothfile(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "go",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "run apt-get install -y golang\n"},
					},
				},
				ParamValues: map[string]string{"GO_VERSION": "1.24"},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "arg GO_VERSION=1.24")
	assert.Contains(t, out.Boothfile.Content, "run apt-get install -y golang")
}

func TestCompile_SingleTemplateStartup(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "go",
					StartupSegments: []tmpl.Segment{
						{Order: 50, Content: "go version\n"},
					},
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.Len(t, out.Startups, 1)
	assert.Equal(t, "50-go--startup.sh", out.Startups[0].RelPath)
	assert.Equal(t, "go version\n", out.Startups[0].Content)
}

func TestCompile_SingleTemplateConfig(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name:    "go",
					Variant: "bookworm",
					Port:    "8080",
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Config)
	assert.Equal(t, "bookworm", out.Config.Variant)
	assert.Equal(t, "8080", out.Config.Port)
}

// --- No segments or params ---

func TestCompile_EmptyTemplate(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "empty"},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	assert.Nil(t, out.Boothfile)
	assert.Empty(t, out.Startups)
	require.NotNil(t, out.Config)
}

func TestCompile_NoTemplates(t *testing.T) {
	resolved := &selection.ResolvedSelection{}

	out, err := Compile(resolved)
	require.NoError(t, err)
	assert.Nil(t, out.Boothfile)
	assert.Empty(t, out.Startups)
	require.NotNil(t, out.Config)
}

// --- Segment merging ---

func TestCompile_SegmentOrdering(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "alpha",
					BoothfileSegments: []tmpl.Segment{
						{Order: 90, Content: "# last\n"},
						{Order: 10, Content: "# first\n"},
					},
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	assert.Equal(t, "# first\n# last\n", out.Boothfile.Content)
}

func TestCompile_SegmentTiebreakBySourceName(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "beta",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "# beta\n"},
					},
				},
				ParamValues: map[string]string{},
			},
			{
				Template: &tmpl.Template{
					Name: "alpha",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "# alpha\n"},
					},
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	// alpha comes before beta at same order
	assert.Equal(t, "# alpha\n# beta\n", out.Boothfile.Content)
}

func TestCompile_MultiTemplateSegmentsMerged(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "go",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "run install-go\n"},
					},
				},
				ParamValues: map[string]string{},
			},
			{
				Template: &tmpl.Template{
					Name: "python",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "run install-python\n"},
					},
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	// go < python alphabetically
	assert.Equal(t, "run install-go\nrun install-python\n", out.Boothfile.Content)
}

// --- Params ---

func TestCompile_ParamArgLines(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "go"},
				ParamValues: map[string]string{"GO_VERSION": "1.24", "ARCH": "amd64"},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	// ARG lines sorted alphabetically: ARCH before GO_VERSION
	assert.Contains(t, out.Boothfile.Content, "arg ARCH=amd64\narg GO_VERSION=1.24\n")
}

func TestCompile_ParamConflict(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "go"},
				ParamValues: map[string]string{"VERSION": "1.24"},
			},
			{
				Template:    &tmpl.Template{Name: "python"},
				ParamValues: map[string]string{"VERSION": "3.12"},
			},
		},
	}

	_, err := Compile(resolved)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "conflict")
	assert.Contains(t, err.Error(), "VERSION")
}

func TestCompile_ParamSameValueNoDuplicate(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "go"},
				ParamValues: map[string]string{"SHARED": "val"},
			},
			{
				Template:    &tmpl.Template{Name: "python"},
				ParamValues: map[string]string{"SHARED": "val"},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	assert.Equal(t, "arg SHARED=val\n\n", out.Boothfile.Content)
}

// --- Config scalars ---

func TestCompile_VariantConflict(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "go", Variant: "bookworm"},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "python", Variant: "bullseye"},
				ParamValues: map[string]string{},
			},
		},
	}

	_, err := Compile(resolved)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "conflicting variant")
}

func TestCompile_VariantSameValueOK(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "go", Variant: "bookworm"},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "python", Variant: "bookworm"},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	assert.Equal(t, "bookworm", out.Config.Variant)
}

func TestCompile_PortConflict(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", Port: "8080"},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", Port: "3000"},
				ParamValues: map[string]string{},
			},
		},
	}

	_, err := Compile(resolved)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "conflicting port")
}

func TestCompile_TimezoneConflict(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", Timezone: "UTC"},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", Timezone: "Asia/Bangkok"},
				ParamValues: map[string]string{},
			},
		},
	}

	_, err := Compile(resolved)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "conflicting timezone")
}

func TestCompile_DindConflict(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", Dind: boolPtr(true)},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", Dind: boolPtr(false)},
				ParamValues: map[string]string{},
			},
		},
	}

	_, err := Compile(resolved)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "conflicting dind")
}

func TestCompile_DindSameValueOK(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", Dind: boolPtr(true)},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", Dind: boolPtr(true)},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	assert.True(t, out.Config.Dind)
}

func TestCompile_CmdsConflict(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", Cmds: []string{"bash"}},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", Cmds: []string{"zsh"}},
				ParamValues: map[string]string{},
			},
		},
	}

	_, err := Compile(resolved)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "conflicting cmds")
}

func TestCompile_CmdsSameValueOK(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", Cmds: []string{"bash"}},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", Cmds: []string{"bash"}},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	assert.Equal(t, []string{"bash"}, out.Config.Cmds)
}

// --- Config arrays (combine and dedup) ---

func TestCompile_RunArgsCombined(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", RunArgs: []string{"-e", "FOO=1"}},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", RunArgs: []string{"-e", "BAR=2"}},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	// Each -e + value is a distinct pair
	assert.Equal(t, []string{"-e", "FOO=1", "-e", "BAR=2"}, out.Config.RunArgs)
}

func TestCompile_BuildArgsCombined(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "a", BuildArgs: []string{"--build-arg", "X=1"}},
				ParamValues: map[string]string{},
			},
			{
				Template:    &tmpl.Template{Name: "b", BuildArgs: []string{"--build-arg", "Y=2"}},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	assert.Equal(t, []string{"--build-arg", "X=1", "Y=2"}, out.Config.BuildArgs)
}

// --- Extensions ---

func TestCompile_ExtensionSegments(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "go",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "run install-go\n"},
					},
				},
				ParamValues: map[string]string{},
				Extensions: []selection.SelectedExtension{
					{
						Extension: &tmpl.Template{
							Name: "linter",
							BoothfileSegments: []tmpl.Segment{
								{Order: 60, Content: "run install-linter\n"},
							},
						},
					},
				},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	// go segment at 50, linter at 60
	assert.Equal(t, "run install-go\nrun install-linter\n", out.Boothfile.Content)
}

func TestCompile_ExtensionConfig(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{Name: "go"},
				ParamValues: map[string]string{},
				Extensions: []selection.SelectedExtension{
					{
						Extension: &tmpl.Template{
							Name:    "proxy",
							RunArgs: []string{"-e", "HTTP_PROXY=http://proxy:3128"},
						},
					},
				},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	assert.Equal(t, []string{"-e", "HTTP_PROXY=http://proxy:3128"}, out.Config.RunArgs)
}

func TestCompile_ExtensionConfigConflict(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "go", Variant: "bookworm"},
				ParamValues: map[string]string{},
				Extensions: []selection.SelectedExtension{
					{
						Extension: &tmpl.Template{
							Name:    "ext",
							Variant: "bullseye",
						},
					},
				},
			},
		},
	}

	_, err := Compile(resolved)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "conflicting variant")
	assert.Contains(t, err.Error(), "go+ext")
}

func TestCompile_ExtensionSourceName(t *testing.T) {
	// Extension segments should be sourced as "parent+ext"
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "go",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "# go\n"},
					},
				},
				ParamValues: map[string]string{},
				Extensions: []selection.SelectedExtension{
					{
						Extension: &tmpl.Template{
							Name: "linter",
							BoothfileSegments: []tmpl.Segment{
								{Order: 50, Content: "# linter\n"},
							},
						},
					},
				},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	// Same order=50: "go" < "go+linter" alphabetically
	assert.Equal(t, "# go\n# linter\n", out.Boothfile.Content)
}

func TestCompile_ExtensionParams(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "deno",
					BoothfileSegments: []tmpl.Segment{
						{Order: 50, Content: "setup deno ${DENO_VERSION}\n"},
					},
				},
				ParamValues: map[string]string{"DENO_VERSION": "latest"},
				Extensions: []selection.SelectedExtension{
					{
						Extension: &tmpl.Template{
							Name: "pkg",
							BoothfileSegments: []tmpl.Segment{
								{Order: 60, Content: "install deno-pkg ${DENO_PKGS}\n"},
							},
						},
						ParamValues: map[string]string{"DENO_PKGS": "cowsay,figlet"},
					},
				},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "arg DENO_PKGS=cowsay,figlet")
	assert.Contains(t, out.Boothfile.Content, "arg DENO_VERSION=latest")
	assert.Contains(t, out.Boothfile.Content, "setup deno ${DENO_VERSION}")
	assert.Contains(t, out.Boothfile.Content, "install deno-pkg ${DENO_PKGS}")
}

// --- Files ---

func TestCompile_FilesCollected(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "go",
					Setups: []tmpl.FileRef{
						{SourcePath: "/templates/go/setups/install.sh", RelPath: "install.sh"},
					},
					Home: []tmpl.FileRef{
						{SourcePath: "/templates/go/home/.bashrc", RelPath: ".bashrc"},
					},
					HomeSeed: []tmpl.FileRef{
						{SourcePath: "/templates/go/home-seed/.gitconfig", RelPath: ".gitconfig"},
					},
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.Len(t, out.Setups, 1)
	assert.Equal(t, "install.sh", out.Setups[0].RelPath)
	require.Len(t, out.Home, 1)
	assert.Equal(t, ".bashrc", out.Home[0].RelPath)
	require.Len(t, out.HomeSeed, 1)
	assert.Equal(t, ".gitconfig", out.HomeSeed[0].RelPath)
}

func TestCompile_ExtensionFilesCollected(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{Name: "go"},
				ParamValues: map[string]string{},
				Extensions: []selection.SelectedExtension{
					{
						Extension: &tmpl.Template{
							Name: "linter",
							Setups: []tmpl.FileRef{
								{SourcePath: "/ext/linter/setups/lint.sh", RelPath: "lint.sh"},
							},
						},
					},
				},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.Len(t, out.Setups, 1)
	assert.Equal(t, "lint.sh", out.Setups[0].RelPath)
}

func TestCompile_InlineFilesPassedThrough(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name: "tool",
					HomeSeed: []tmpl.FileRef{
						{RelPath: ".config/tool.json", Content: `{"inline": true}`},
					},
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.Len(t, out.HomeSeed, 1)
	assert.Equal(t, ".config/tool.json", out.HomeSeed[0].RelPath)
	assert.Equal(t, `{"inline": true}`, out.HomeSeed[0].Content)
	assert.Empty(t, out.HomeSeed[0].SourcePath)
}

func TestCompile_ExtensionInlineFiles(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    &tmpl.Template{Name: "parent"},
				ParamValues: map[string]string{},
				Extensions: []selection.SelectedExtension{
					{
						Extension: &tmpl.Template{
							Name: "child",
							HomeSeed: []tmpl.FileRef{
								{RelPath: ".settings", Content: "ext content"},
							},
						},
					},
				},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.Len(t, out.HomeSeed, 1)
	assert.Equal(t, ".settings", out.HomeSeed[0].RelPath)
	assert.Equal(t, "ext content", out.HomeSeed[0].Content)
}

func TestCompile_MultiTemplateFilesCombined(t *testing.T) {
	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template: &tmpl.Template{
					Name:   "go",
					Setups: []tmpl.FileRef{{SourcePath: "/go/s", RelPath: "go.sh"}},
				},
				ParamValues: map[string]string{},
			},
			{
				Template: &tmpl.Template{
					Name:   "python",
					Setups: []tmpl.FileRef{{SourcePath: "/py/s", RelPath: "py.sh"}},
				},
				ParamValues: map[string]string{},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)
	require.Len(t, out.Setups, 2)
}

// --- Helper functions ---

func TestMergeSegments_Empty(t *testing.T) {
	assert.Equal(t, "", mergeSegments(nil))
}

func TestMergeSegments_Single(t *testing.T) {
	segs := []sourcedSegment{{Order: 50, Content: "hello\n", SourceName: "a"}}
	assert.Equal(t, "hello\n", mergeSegments(segs))
}

func TestMergeSegments_TrailingNewlineNormalized(t *testing.T) {
	segs := []sourcedSegment{{Order: 50, Content: "hello\n\n\n", SourceName: "a"}}
	assert.Equal(t, "hello\n", mergeSegments(segs))
}

func TestBuildArgLines_Empty(t *testing.T) {
	assert.Equal(t, "", buildArgLines(map[string]string{}))
}

func TestBuildArgLines_Sorted(t *testing.T) {
	params := map[string]string{"Z_VAR": "z", "A_VAR": "a"}
	result := buildArgLines(params)
	assert.Equal(t, "arg A_VAR=a\narg Z_VAR=z\n\n", result)
}

func TestDedup_NoDuplicates(t *testing.T) {
	assert.Equal(t, []string{"a", "b", "c"}, dedup([]string{"a", "b", "c"}))
}

func TestDedup_WithDuplicates(t *testing.T) {
	assert.Equal(t, []string{"a", "b", "c"}, dedup([]string{"a", "b", "a", "c", "b"}))
}

func TestDedup_Empty(t *testing.T) {
	assert.Nil(t, dedup(nil))
	assert.Nil(t, dedup([]string{}))
}

func TestDedup_PreservesOrder(t *testing.T) {
	assert.Equal(t, []string{"c", "a", "b"}, dedup([]string{"c", "a", "b", "a", "c"}))
}

// --- End-to-end with real registry ---

func TestCompile_EndToEnd(t *testing.T) {
	// Simulate go:1.24+linter / python:3.12
	goTemplate := &tmpl.Template{
		Name:    "go",
		Variant: "bookworm",
		Port:    "8080",
		BoothfileSegments: []tmpl.Segment{
			{Order: 50, Content: "run apt-get install -y golang=${GO_VERSION}\n"},
		},
		StartupSegments: []tmpl.Segment{
			{Order: 50, Content: "go version\n"},
		},
		RunArgs: []string{"-e", "GOPATH=/home/dev/go"},
	}
	linterExt := &tmpl.Template{
		Name: "linter",
		BoothfileSegments: []tmpl.Segment{
			{Order: 70, Content: "run go install golangci-lint\n"},
		},
	}
	pythonTemplate := &tmpl.Template{
		Name:    "python",
		Variant: "bookworm",
		BoothfileSegments: []tmpl.Segment{
			{Order: 50, Content: "run apt-get install -y python=${PYTHON_VERSION}\n"},
		},
		StartupSegments: []tmpl.Segment{
			{Order: 50, Content: "python --version\n"},
		},
		RunArgs: []string{"-e", "PYTHONPATH=/home/dev"},
	}

	resolved := &selection.ResolvedSelection{
		Templates: []selection.SelectedTemplate{
			{
				Template:    goTemplate,
				ParamValues: map[string]string{"GO_VERSION": "1.24"},
				Extensions: []selection.SelectedExtension{
					{Extension: linterExt},
				},
			},
			{
				Template:    pythonTemplate,
				ParamValues: map[string]string{"PYTHON_VERSION": "3.12"},
			},
		},
	}

	out, err := Compile(resolved)
	require.NoError(t, err)

	// Config
	assert.Equal(t, "bookworm", out.Config.Variant)
	assert.Equal(t, "8080", out.Config.Port)
	// RunArgs combined and deduped: each -e + value is a distinct pair
	assert.Equal(t, []string{"-e", "GOPATH=/home/dev/go", "-e", "PYTHONPATH=/home/dev"}, out.Config.RunArgs)

	// Boothfile: ARG lines + segments sorted
	require.NotNil(t, out.Boothfile)
	content := out.Boothfile.Content
	assert.Contains(t, content, "arg GO_VERSION=1.24")
	assert.Contains(t, content, "arg PYTHON_VERSION=3.12")
	// go segment at 50, python at 50 (go < python), linter at 70
	assert.Contains(t, content, "run apt-get install -y golang=${GO_VERSION}")
	assert.Contains(t, content, "run apt-get install -y python=${PYTHON_VERSION}")
	assert.Contains(t, content, "run go install golangci-lint")

	// Startups
	require.NotEmpty(t, out.Startups)
	var startupContents string
	for _, s := range out.Startups {
		startupContents += s.Content
	}
	assert.Contains(t, startupContents, "go version")
	assert.Contains(t, startupContents, "python --version")
}
