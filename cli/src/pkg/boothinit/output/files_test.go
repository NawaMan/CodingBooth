// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCopyFiles_Empty(t *testing.T) {
	tmpDir := t.TempDir()
	err := CopyFiles(nil, tmpDir)
	assert.NoError(t, err)
}

func TestCopyFiles_SingleFile(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()

	// Create source file
	srcFile := filepath.Join(srcDir, "test.sh")
	require.NoError(t, os.WriteFile(srcFile, []byte("#!/bin/bash\necho hi\n"), 0755))

	files := []FileContent{
		{SourcePath: srcFile, RelPath: "test.sh"},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	// Verify file exists and content matches
	data, err := os.ReadFile(filepath.Join(dstDir, "test.sh"))
	require.NoError(t, err)
	assert.Equal(t, "#!/bin/bash\necho hi\n", string(data))
}

func TestCopyFiles_NestedRelPath(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()

	// Create source file
	srcFile := filepath.Join(srcDir, "config.yaml")
	require.NoError(t, os.WriteFile(srcFile, []byte("key: value\n"), 0644))

	files := []FileContent{
		{SourcePath: srcFile, RelPath: ".config/myapp/config.yaml"},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	// Verify nested directories and file were created
	data, err := os.ReadFile(filepath.Join(dstDir, ".config", "myapp", "config.yaml"))
	require.NoError(t, err)
	assert.Equal(t, "key: value\n", string(data))
}

func TestCopyFiles_PreservesPermissions(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()

	// Create executable source file
	srcFile := filepath.Join(srcDir, "run.sh")
	require.NoError(t, os.WriteFile(srcFile, []byte("#!/bin/bash\n"), 0755))

	files := []FileContent{
		{SourcePath: srcFile, RelPath: "run.sh"},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	info, err := os.Stat(filepath.Join(dstDir, "run.sh"))
	require.NoError(t, err)
	assert.True(t, info.Mode()&0100 != 0, "executable bit should be preserved")
}

func TestCopyFiles_MultipleFiles(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()

	// Create source files
	file1 := filepath.Join(srcDir, "a.txt")
	file2 := filepath.Join(srcDir, "b.txt")
	require.NoError(t, os.WriteFile(file1, []byte("aaa"), 0644))
	require.NoError(t, os.WriteFile(file2, []byte("bbb"), 0644))

	files := []FileContent{
		{SourcePath: file1, RelPath: "a.txt"},
		{SourcePath: file2, RelPath: "sub/b.txt"},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	data1, err := os.ReadFile(filepath.Join(dstDir, "a.txt"))
	require.NoError(t, err)
	assert.Equal(t, "aaa", string(data1))

	data2, err := os.ReadFile(filepath.Join(dstDir, "sub", "b.txt"))
	require.NoError(t, err)
	assert.Equal(t, "bbb", string(data2))
}

func TestCopyFiles_SourceNotFound(t *testing.T) {
	dstDir := t.TempDir()
	files := []FileContent{
		{SourcePath: "/nonexistent/file.txt", RelPath: "file.txt"},
	}
	err := CopyFiles(files, dstDir)
	assert.Error(t, err)
}

// --- Inline content ---

func TestCopyFiles_InlineContent(t *testing.T) {
	dstDir := t.TempDir()
	files := []FileContent{
		{RelPath: "config.json", Content: `{"key": "value"}`},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(dstDir, "config.json"))
	require.NoError(t, err)
	assert.Equal(t, `{"key": "value"}`, string(data))
}

func TestCopyFiles_InlineContentNested(t *testing.T) {
	dstDir := t.TempDir()
	files := []FileContent{
		{RelPath: ".claude/settings.json", Content: `{"defaultMode": "acceptEdits"}`},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(dstDir, ".claude", "settings.json"))
	require.NoError(t, err)
	assert.Equal(t, `{"defaultMode": "acceptEdits"}`, string(data))
}

func TestCopyFiles_InlineContentPermissions(t *testing.T) {
	dstDir := t.TempDir()
	files := []FileContent{
		{RelPath: "test.txt", Content: "hello"},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	info, err := os.Stat(filepath.Join(dstDir, "test.txt"))
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0644), info.Mode().Perm())
}

func TestCopyFiles_MixedSourceAndInline(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()

	srcFile := filepath.Join(srcDir, "from-disk.txt")
	require.NoError(t, os.WriteFile(srcFile, []byte("disk content"), 0644))

	files := []FileContent{
		{SourcePath: srcFile, RelPath: "from-disk.txt"},
		{RelPath: "from-inline.txt", Content: "inline content"},
	}
	err := CopyFiles(files, dstDir)
	require.NoError(t, err)

	data1, err := os.ReadFile(filepath.Join(dstDir, "from-disk.txt"))
	require.NoError(t, err)
	assert.Equal(t, "disk content", string(data1))

	data2, err := os.ReadFile(filepath.Join(dstDir, "from-inline.txt"))
	require.NoError(t, err)
	assert.Equal(t, "inline content", string(data2))
}
