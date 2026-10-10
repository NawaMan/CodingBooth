// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package pathseed gives a Cache or Shared path its initial content.
//
// .booth/cache-seed/ and .booth/shared-seed/ are committed and use the Cache layout: the
// tree mirrors the container's root, a file stands for itself, and a folder holding a
// .mount-this marker stands for the whole folder. Apply copies each seed into
// .booth/cache/ or .booth/shared/ where the path is still missing, so a declared path
// starts with that content instead of empty — on every clone, since the seed is in git
// even when .booth/cache/ is not.
package pathseed

import (
	"io"
	"os"
	"path/filepath"
)

const mountMarker = ".mount-this"

// Apply copies each seed in seedDir into targetDir where the target is missing, and
// returns the paths it filled, relative to targetDir. It never replaces content:
//
//   - A file is seeded when the target is missing or empty. Empty counts as missing
//     because booth creates a declared path with no seed as an empty file, and a seed
//     added later must still reach it.
//   - A marked folder is copied whole, and only when the target folder does not exist,
//     so a file the user deleted from it stays deleted.
//   - Files at the seed root are skipped: they map to "/" (a README.md, say).
//
// A missing seedDir is not an error.
func Apply(seedDir, targetDir string) ([]string, error) {
	if info, err := os.Stat(seedDir); err != nil || !info.IsDir() {
		return nil, nil
	}
	var seeded []string
	err := walk(seedDir, targetDir, ".", &seeded)
	return seeded, err
}

func walk(seedDir, targetDir, rel string, seeded *[]string) error {
	src := filepath.Join(seedDir, rel)
	dst := filepath.Join(targetDir, rel)

	if rel != "." {
		if _, err := os.Stat(filepath.Join(src, mountMarker)); err == nil {
			if _, err := os.Stat(dst); err == nil {
				return nil
			}
			if err := copyTree(src, dst); err != nil {
				return err
			}
			*seeded = append(*seeded, rel)
			return nil
		}
	}

	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		childRel := filepath.Join(rel, entry.Name())
		if entry.IsDir() {
			if err := walk(seedDir, targetDir, childRel, seeded); err != nil {
				return err
			}
			continue
		}
		if rel == "." || !entry.Type().IsRegular() {
			continue
		}
		target := filepath.Join(targetDir, childRel)
		if info, err := os.Stat(target); err == nil && info.Size() > 0 {
			continue
		}
		if err := copyFile(filepath.Join(seedDir, childRel), target); err != nil {
			return err
		}
		*seeded = append(*seeded, childRel)
	}
	return nil
}

// copyTree copies the folder src to dst, which does not exist yet.
func copyTree(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, info.Mode().Perm()|0700)
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		return copyFile(path, target)
	})
}

// copyFile copies src over dst, creating parent folders and keeping src's permissions.
func copyFile(src, dst string) error {
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, info.Mode().Perm())
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
