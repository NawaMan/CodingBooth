// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// CopyFiles copies a list of FileContent entries into the given target directory.
// Each file's RelPath is resolved relative to targetDir.
// Parent directories are created as needed.
func CopyFiles(files []FileContent, targetDir string) error {
	for _, f := range files {
		dest := filepath.Join(targetDir, f.RelPath)
		if err := copyFile(f.SourcePath, dest); err != nil {
			return fmt.Errorf("copying %s to %s: %w", f.SourcePath, dest, err)
		}
	}
	return nil
}

// copyFile copies a single file from src to dst, creating parent directories.
// File permissions are preserved from the source.
func copyFile(src, dst string) error {
	srcInfo, err := os.Stat(src)
	if err != nil {
		return fmt.Errorf("stat source: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return fmt.Errorf("creating parent dirs: %w", err)
	}

	srcFile, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("opening source: %w", err)
	}
	defer srcFile.Close()

	dstFile, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, srcInfo.Mode())
	if err != nil {
		return fmt.Errorf("creating destination: %w", err)
	}
	defer dstFile.Close()

	if _, err := io.Copy(dstFile, srcFile); err != nil {
		return fmt.Errorf("copying content: %w", err)
	}

	return nil
}
