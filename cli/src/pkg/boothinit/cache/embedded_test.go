// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package cache

import (
	"archive/zip"
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// useEmbedded makes the binary carry a catalog for version (none when version is
// empty), and points the cache at an empty directory so nothing else can answer.
func useEmbedded(t *testing.T, version string) {
	t.Helper()
	var data []byte
	if version != "" {
		var buf bytes.Buffer
		w := zip.NewWriter(&buf)
		require.NoError(t, w.SetComment(version))
		fw, err := w.Create("templates/languages/go/template.toml")
		require.NoError(t, err)
		_, err = fw.Write([]byte("display-name = \"Go\"\n"))
		require.NoError(t, err)
		require.NoError(t, w.Close())
		data = buf.Bytes()
	}
	previous := embeddedZipData
	embeddedZipData = func() []byte { return data }
	t.Cleanup(func() { embeddedZipData = previous })
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
}

func TestEmbedded_UsedForItsOwnVersion(t *testing.T) {
	useEmbedded(t, "1.2.3")
	assert.Equal(t, "1.2.3", EmbeddedVersion())

	for name, resolve := range map[string]func(string) (string, func(), error){
		"ResolveTemplatesDir":       ResolveTemplatesDir,
		"ResolveCachedTemplatesDir": ResolveCachedTemplatesDir,
	} {
		dir, cleanup, err := resolve("1.2.3")
		require.NoError(t, err, name)
		content, err := os.ReadFile(filepath.Join(dir, "languages", "go", "template.toml"))
		require.NoError(t, err, name)
		assert.Contains(t, string(content), "Go", name)

		cleanup()
		_, err = os.Stat(dir)
		assert.True(t, os.IsNotExist(err), "%s: cleanup removes the extracted catalog", name)
	}
}

// Another version's catalog is not the embedded one: the cache answers, and here it is empty.
func TestEmbedded_NotUsedForAnotherVersion(t *testing.T) {
	useEmbedded(t, "1.2.3")

	_, _, err := ResolveCachedTemplatesDir("1.2.4")
	assert.Error(t, err)
	_, _, err = ResolveCachedTemplatesDir("")
	assert.Error(t, err)
}

// A cached templates.zip still serves a version the binary does not carry.
func TestEmbedded_CacheServesAnotherVersion(t *testing.T) {
	useEmbedded(t, "1.2.3")
	cacheDir, err := getCacheDir()
	require.NoError(t, err)
	require.NoError(t, os.MkdirAll(filepath.Join(cacheDir, "1.2.4"), 0755))
	createTestZip(t, filepath.Join(cacheDir, "1.2.4", templateFile), map[string]string{
		"templates/tools/neovim/template.toml": "display-name = \"Neovim\"\n",
	})

	dir, cleanup, err := ResolveTemplatesDir("1.2.4")
	require.NoError(t, err)
	defer cleanup()
	_, err = os.Stat(filepath.Join(dir, "tools", "neovim", "template.toml"))
	assert.NoError(t, err)
	_, err = os.Stat(filepath.Join(dir, "languages"))
	assert.True(t, os.IsNotExist(err), "the embedded catalog is not mixed in")
}

func TestEmbedded_AbsentWhenBuiltWithoutIt(t *testing.T) {
	useEmbedded(t, "")
	assert.Equal(t, "", EmbeddedVersion())
	_, _, err := ResolveCachedTemplatesDir("1.2.3")
	assert.Error(t, err)
}
