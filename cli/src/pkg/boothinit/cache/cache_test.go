// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package cache

import (
	"archive/zip"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// createTestZip creates a zip file at zipPath with the given entries.
// Each entry is a path→content pair. Directories should end with "/".
func createTestZip(t *testing.T, zipPath string, entries map[string]string) {
	t.Helper()
	f, err := os.Create(zipPath)
	require.NoError(t, err)
	defer f.Close()

	w := zip.NewWriter(f)
	for name, content := range entries {
		fw, err := w.Create(name)
		require.NoError(t, err)
		_, err = fw.Write([]byte(content))
		require.NoError(t, err)
	}
	require.NoError(t, w.Close())
}

func TestExtractTemplatesZip_ValidZip(t *testing.T) {
	tmpDir := t.TempDir()
	zipPath := filepath.Join(tmpDir, "test.zip")

	createTestZip(t, zipPath, map[string]string{
		"templates/languages/meta.toml":          "display-name = \"Languages\"\norder = 1\n",
		"templates/languages/go/template.toml":   "display-name = \"Go\"\n",
		"templates/tools/meta.toml":              "display-name = \"Tools\"\norder = 3\n",
		"templates/tools/neovim/template.toml":   "display-name = \"Neovim\"\n",
	})

	destDir := filepath.Join(tmpDir, "extracted")
	require.NoError(t, os.MkdirAll(destDir, 0755))

	err := ExtractTemplatesZip(zipPath, destDir)
	require.NoError(t, err)

	// Verify files exist
	content, err := os.ReadFile(filepath.Join(destDir, "templates", "languages", "meta.toml"))
	require.NoError(t, err)
	assert.Contains(t, string(content), "Languages")

	content, err = os.ReadFile(filepath.Join(destDir, "templates", "languages", "go", "template.toml"))
	require.NoError(t, err)
	assert.Contains(t, string(content), "Go")

	content, err = os.ReadFile(filepath.Join(destDir, "templates", "tools", "neovim", "template.toml"))
	require.NoError(t, err)
	assert.Contains(t, string(content), "Neovim")
}

func TestExtractTemplatesZip_RejectsPathTraversal(t *testing.T) {
	tmpDir := t.TempDir()
	zipPath := filepath.Join(tmpDir, "evil.zip")

	createTestZip(t, zipPath, map[string]string{
		"../etc/passwd": "root:x:0:0",
	})

	destDir := filepath.Join(tmpDir, "extracted")
	require.NoError(t, os.MkdirAll(destDir, 0755))

	err := ExtractTemplatesZip(zipPath, destDir)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "path traversal")
}

func TestExtractTemplatesZip_RejectsNestedPathTraversal(t *testing.T) {
	tmpDir := t.TempDir()
	zipPath := filepath.Join(tmpDir, "evil.zip")

	createTestZip(t, zipPath, map[string]string{
		"templates/../../etc/passwd": "root:x:0:0",
	})

	destDir := filepath.Join(tmpDir, "extracted")
	require.NoError(t, os.MkdirAll(destDir, 0755))

	err := ExtractTemplatesZip(zipPath, destDir)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "path traversal")
}

func TestExtractTemplatesZip_MissingZipFile(t *testing.T) {
	tmpDir := t.TempDir()
	destDir := filepath.Join(tmpDir, "extracted")
	require.NoError(t, os.MkdirAll(destDir, 0755))

	err := ExtractTemplatesZip(filepath.Join(tmpDir, "nonexistent.zip"), destDir)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "opening zip")
}

func TestExtractTemplatesZip_EmptyZip(t *testing.T) {
	tmpDir := t.TempDir()
	zipPath := filepath.Join(tmpDir, "empty.zip")

	createTestZip(t, zipPath, map[string]string{})

	destDir := filepath.Join(tmpDir, "extracted")
	require.NoError(t, os.MkdirAll(destDir, 0755))

	err := ExtractTemplatesZip(zipPath, destDir)
	require.NoError(t, err)
}

func TestExtractTemplatesZip_PreservesFileContent(t *testing.T) {
	tmpDir := t.TempDir()
	zipPath := filepath.Join(tmpDir, "test.zip")

	expectedContent := `display-name = "Go"
display-disc = "Go language toolchain"
display-order = 10
tags = ["go", "golang", "backend"]

[segments]
Boothfile = """
setup go ${GO_VERSION}
"""
`

	createTestZip(t, zipPath, map[string]string{
		"templates/languages/go/template.toml": expectedContent,
	})

	destDir := filepath.Join(tmpDir, "extracted")
	require.NoError(t, os.MkdirAll(destDir, 0755))

	err := ExtractTemplatesZip(zipPath, destDir)
	require.NoError(t, err)

	actual, err := os.ReadFile(filepath.Join(destDir, "templates", "languages", "go", "template.toml"))
	require.NoError(t, err)
	assert.Equal(t, expectedContent, string(actual))
}

func TestExtractTemplatesZip_CreatesDirectories(t *testing.T) {
	tmpDir := t.TempDir()
	zipPath := filepath.Join(tmpDir, "test.zip")

	createTestZip(t, zipPath, map[string]string{
		"templates/deep/nested/dir/file.txt": "content",
	})

	destDir := filepath.Join(tmpDir, "extracted")
	require.NoError(t, os.MkdirAll(destDir, 0755))

	err := ExtractTemplatesZip(zipPath, destDir)
	require.NoError(t, err)

	info, err := os.Stat(filepath.Join(destDir, "templates", "deep", "nested", "dir"))
	require.NoError(t, err)
	assert.True(t, info.IsDir())
}
