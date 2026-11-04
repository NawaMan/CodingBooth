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
	"path"
	"path/filepath"
	"strings"
)

const mountMarker = ".mount-this"

// Apply copies each seed in seedDir into targetDir where the target is missing, and
// returns the paths it filled, relative to targetDir. It never replaces content:
//
//   - A file is seeded when the target is missing or empty. Empty counts as missing
//     because booth creates a declared path with no seed as an empty file, and a seed
//     added later must still reach it.
//   - A marked folder is copied whole when the target folder is missing or empty --
//     holding nothing but the .mount-this marker counts as empty, because booth creates
//     a declared folder with no seed that way, and a seed added later must still reach
//     it. A folder with anything else in it is the user's, so a file deleted from it
//     stays deleted.
//   - Files at the seed root are skipped: they map to "/" (a README.md, say).
//
// A missing seedDir is not an error.
func Apply(seedDir, targetDir string) ([]string, error) {
	seeded, _, err := ApplyDeclared(seedDir, targetDir, nil)
	return seeded, err
}

// ApplyDeclared is Apply limited to the declared paths: a seed is copied only when its
// path is one of them or lies inside one (a declared folder). The others are returned as
// skipped. A seed alone must not make a path mount: the declaration -- a template's
// cache-files/-dirs, or config.toml's -- is what does, so deselecting the template
// stops the seeding (content already copied stays until deleted). declared holds paths
// relative to targetDir, without a :mode suffix; nil means every seed.
func ApplyDeclared(seedDir, targetDir string, declared []string) (seeded, skipped []string, err error) {
	if info, err := os.Stat(seedDir); err != nil || !info.IsDir() {
		return nil, nil, nil
	}
	w := walker{seedDir: seedDir, targetDir: targetDir}
	if declared != nil {
		w.declared = map[string]bool{}
		for _, d := range declared {
			w.declared[cleanRel(d)] = true
		}
	}
	err = w.walk(".")
	return w.seeded, w.skipped, err
}

// cleanRel turns a declared path ("home/coder/.x/", "./home//coder/.x", "/home/coder/.x")
// into the slash form the walk compares against ("home/coder/.x").
func cleanRel(p string) string {
	return path.Clean(strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(p)), "/"))
}

type walker struct {
	seedDir, targetDir string
	declared           map[string]bool // nil: every seed applies
	seeded, skipped    []string
}

// covered reports whether rel is a declared path or inside one.
func (w *walker) covered(rel string) bool {
	if w.declared == nil {
		return true
	}
	for p := filepath.ToSlash(rel); p != "." && p != "/" && p != ""; p = path.Dir(p) {
		if w.declared[p] {
			return true
		}
	}
	return false
}

func (w *walker) walk(rel string) error {
	seedDir, targetDir := w.seedDir, w.targetDir
	src := filepath.Join(seedDir, rel)
	dst := filepath.Join(targetDir, rel)

	if rel != "." {
		if _, err := os.Stat(filepath.Join(src, mountMarker)); err == nil {
			if !w.covered(rel) {
				w.skipped = append(w.skipped, rel)
				return nil
			}
			if _, err := os.Stat(dst); err == nil && !onlyMarker(dst) {
				return nil
			}
			if err := copyTree(src, dst); err != nil {
				return err
			}
			w.seeded = append(w.seeded, rel)
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
			if err := w.walk(childRel); err != nil {
				return err
			}
			continue
		}
		if rel == "." || !entry.Type().IsRegular() {
			continue
		}
		if !w.covered(childRel) {
			w.skipped = append(w.skipped, childRel)
			continue
		}
		target := filepath.Join(targetDir, childRel)
		if info, err := os.Stat(target); err == nil && info.Size() > 0 {
			continue
		}
		if err := copyFile(filepath.Join(seedDir, childRel), target); err != nil {
			return err
		}
		w.seeded = append(w.seeded, childRel)
	}
	return nil
}

// onlyMarker reports whether dir is a folder holding nothing but the .mount-this marker.
func onlyMarker(dir string) bool {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	for _, e := range entries {
		// The marker must be a plain file: a folder or symlink of that name is
		// something of the user's, and copying over it would fail or write elsewhere.
		if e.Name() != mountMarker || !e.Type().IsRegular() {
			return false
		}
	}
	return true
}

// copyTree copies the folder src into dst, which is missing or holds only the marker.
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
