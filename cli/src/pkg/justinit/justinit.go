// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package justinit writes a project's starter Justfile: recipes that run the
// same from the host and from inside the booth (`booth just-init`).
package justinit

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
)

// Starter is the starter Justfile. Its user-facing copy is docs/just/Justfile,
// which the docs link to on GitHub; TestStarterMatchesDocs keeps the two
// byte-identical.
//
//go:embed Justfile
var Starter string

// justfileNames are the names just itself looks for at a project root.
var justfileNames = []string{"Justfile", "justfile", ".justfile", "JUSTFILE"}

// FindJustfile returns the path of dir's existing Justfile, under any name just
// would pick up, or "" when there is none.
func FindJustfile(dir string) string {
	for _, name := range justfileNames {
		path := filepath.Join(dir, name)
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}

// BackupPath returns where path would be backed up to: path.bak, or path.bak.N
// for the first N that is free, so an earlier backup is never overwritten.
func BackupPath(path string) string {
	candidate := path + ".bak"
	for n := 1; ; n++ {
		if _, err := os.Lstat(candidate); os.IsNotExist(err) {
			return candidate
		}
		candidate = fmt.Sprintf("%s.bak.%d", path, n)
	}
}

// Backup moves path aside to BackupPath(path) and returns where it went.
func Backup(path string) (string, error) {
	backup := BackupPath(path)
	if err := os.Rename(path, backup); err != nil {
		return "", err
	}
	return backup, nil
}

// Write writes the starter to dir/Justfile. It refuses when dir already has a
// Justfile under any name: moving that aside first (Backup) is the caller's call.
func Write(dir string) (string, error) {
	if existing := FindJustfile(dir); existing != "" {
		return "", fmt.Errorf("%s already exists", existing)
	}
	path := filepath.Join(dir, "Justfile")
	if err := os.WriteFile(path, []byte(Starter), 0644); err != nil {
		return "", err
	}
	return path, nil
}

// IsFirstConfigure reports whether dir's booth has never been configured: no
// .booth/Boothfile and no .booth/config.toml. The wrapper creates .booth/ itself
// before the CLI runs, so the folder alone says nothing. Ask before writing.
func IsFirstConfigure(dir string) bool {
	for _, name := range []string{"Boothfile", "config.toml"} {
		if _, err := os.Stat(filepath.Join(dir, ".booth", name)); err == nil {
			return false
		}
	}
	return true
}

// WriteIfMissing writes the starter unless dir already has a Justfile, which it
// leaves alone without asking. It returns the path it wrote, or "".
func WriteIfMissing(dir string) (string, error) {
	if FindJustfile(dir) != "" {
		return "", nil
	}
	return Write(dir)
}
