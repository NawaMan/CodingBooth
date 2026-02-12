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

// CopyFiles writes a list of FileContent entries into the given target directory.
// For entries with Content set, the content is written directly.
// For entries with SourcePath set, the file is copied from the source.
// Parent directories are created as needed.
func CopyFiles(files []FileContent, targetDir string) error {
	for _, f := range files {
		dest := filepath.Join(targetDir, f.RelPath)
		if f.Content != "" {
			if err := writeInlineFile(dest, f.Content); err != nil {
				return fmt.Errorf("writing inline file %s: %w", f.RelPath, err)
			}
		} else {
			if err := copyFile(f.SourcePath, dest); err != nil {
				return fmt.Errorf("copying %s to %s: %w", f.SourcePath, dest, err)
			}
		}
	}
	return nil
}

// writeInlineFile writes inline content to a file, creating parent directories.
func writeInlineFile(dest, content string) error {
	if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
		return fmt.Errorf("creating parent dirs: %w", err)
	}
	return os.WriteFile(dest, []byte(content), 0644)
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
