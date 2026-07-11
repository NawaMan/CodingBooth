// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ManifestName is the sidecar recording a hash of each file `booth config` wrote.
//
// The `# Configured by:` header alone cannot answer the question that matters
// before an overwrite — "is this content still ours?" — because a generated file
// keeps its header after a human edits it. The hash can: content that no longer
// matches what we wrote has been touched, and overwriting it destroys work.
//
// It is committed alongside the Boothfile, not gitignored: drift detection has to
// survive a clone.
const ManifestName = ".generated"

// GuardedFiles are the files WriteOutput regenerates wholesale. They are the ones
// whose hand-written content a reconfigure would silently destroy — the rest of
// .booth/ is either copied, no-clobbered, or cleaned up by header.
var GuardedFiles = []string{"Boothfile", "config.toml"}

// hashContent fingerprints generated content for the manifest.
func hashContent(content string) string {
	sum := sha256.Sum256([]byte(content))
	return "sha256:" + hex.EncodeToString(sum[:])
}

// readManifest loads .booth/.generated as a file name → hash map.
// A missing or unreadable manifest is not an error — it just means nothing is
// tracked yet, which the caller resolves via the provenance header.
func readManifest(boothDir string) map[string]string {
	f, err := os.Open(filepath.Join(boothDir, ManifestName))
	if err != nil {
		return map[string]string{}
	}
	defer f.Close()

	entries := map[string]string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		name, hash, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		entries[strings.TrimSpace(name)] = strings.TrimSpace(hash)
	}
	return entries
}

// writeManifest merges the freshly-written hashes into .booth/.generated,
// preserving entries for files this run did not touch (an empty selection writes
// no Boothfile, and dropping its hash would silently un-track it).
func writeManifest(boothDir string, written map[string]string) error {
	if len(written) == 0 {
		return nil
	}

	entries := readManifest(boothDir)
	for name, hash := range written {
		entries[name] = hash
	}

	names := make([]string, 0, len(entries))
	for name := range entries {
		names = append(names, name)
	}
	sort.Strings(names)

	var b strings.Builder
	b.WriteString("# Written by booth config — a fingerprint of the files it generated.\n")
	b.WriteString("# `booth config` compares against this to detect hand-edits before\n")
	b.WriteString("# overwriting them. Commit it. Delete it to have those files treated\n")
	b.WriteString("# as hand-written (booth config will then refuse to clobber them).\n")
	for _, name := range names {
		fmt.Fprintf(&b, "%s=%s\n", name, entries[name])
	}

	return writeFile(filepath.Join(boothDir, ManifestName), b.String(), 0644)
}

// Drifted returns the guarded files under targetPath holding content that
// `booth config` did not write — either hand-authored from the start, or
// generated and then hand-edited. Overwriting these destroys the user's work,
// so callers must get explicit consent first.
//
// Classification per file:
//
//	absent                      → not at risk (nothing to lose)
//	hash recorded, matches      → ours, untouched   → safe to regenerate
//	hash recorded, mismatch     → generated, then hand-edited → DRIFTED
//	no hash, has our header     → generated before the manifest existed; adopt it
//	no hash, no header          → hand-authored → DRIFTED
//
// The "adopt it" case is what keeps every pre-existing booth from crying wolf on
// its first run. The cost is honest and bounded: a booth generated *and then
// edited* before manifests existed gets adopted on its header and can still be
// overwritten. That is no worse than today, where it is overwritten with no
// warning at all, and it self-heals — the file gains a hash the moment it is
// next written, and every edit after that is caught.
func Drifted(targetPath string) []string {
	boothDir := filepath.Join(targetPath, ".booth")
	manifest := readManifest(boothDir)

	var drifted []string
	for _, name := range GuardedFiles {
		path := filepath.Join(boothDir, name)
		content, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if recorded, tracked := manifest[name]; tracked {
			if recorded != hashContent(string(content)) {
				drifted = append(drifted, name)
			}
			continue
		}
		if !isGeneratedFile(path) {
			drifted = append(drifted, name)
		}
	}
	return drifted
}

// BackupDrifted copies each named file in .booth/ to <name>.bak before it is
// overwritten. Called only when the user has confirmed destroying hand-written
// content — insurance at the moment of destruction, rather than .bak clutter on
// every save. (.booth/ is normally committed, so git already covers the rest.)
func BackupDrifted(targetPath string, names []string) error {
	boothDir := filepath.Join(targetPath, ".booth")
	for _, name := range names {
		content, err := os.ReadFile(filepath.Join(boothDir, name))
		if err != nil {
			continue
		}
		backup := filepath.Join(boothDir, name+".bak")
		if err := os.WriteFile(backup, content, 0644); err != nil {
			return fmt.Errorf("backing up %s: %w", name, err)
		}
	}
	return nil
}
