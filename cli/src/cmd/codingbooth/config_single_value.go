// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
)

// A single-value change edits one line, not the whole .booth/.
//
// `booth config --no-tui --apt-snapshot <id>` on an existing booth used to run the
// full reconfigure: recompile the selection, rewrite every guarded file, re-copy
// every template-owned one. Moving one date then meant consenting (--overwrite) to
// replace hand-added content anywhere in .booth/ — deny rules in a home-seed file,
// a changed startup, config.toml edits — or hand-editing the line and leaving the
// fingerprint stale. Here the run only rewrites the Boothfile's
// `env APT_SNAPSHOT=` line, and re-stamps the fingerprint when, and only when,
// the Boothfile was still booth config's own before the edit.

// snapshotOnlyFlags are the flags that may go with --apt-snapshot and still take
// the one-line path. --overwrite and --beside are consent for a full rewrite; with
// nothing but the snapshot to change there is nothing for them to consent to, so
// they are accepted (sync-apt-snapshot.sh and old habits pass --overwrite) and
// have no effect. Any other flag asks for a real reconfigure.
var snapshotOnlyFlags = []string{"--no-tui", "--overwrite", "--beside", "--dryrun", "--debug"}

// isSnapshotOnlyChange reports whether args (the flags after `config` and the
// optional path) ask for nothing but a new apt snapshot.
func isSnapshotOnlyChange(args []string) bool {
	sawSnapshot := false
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--apt-snapshot":
			if i+1 >= len(args) {
				return false
			}
			sawSnapshot = true
			i++
		case slices.Contains(snapshotOnlyFlags, args[i]):
		default:
			return false
		}
	}
	return sawSnapshot
}

// setAptSnapshotLine returns content with its first `env APT_SNAPSHOT=` line set to
// id, and the id that line held before (found false when there was none). A
// Boothfile without the line gets one where booth config puts it: after the
// leading comment header and the blank line that ends it.
func setAptSnapshotLine(content, id string) (updated, previous string, found bool) {
	lines := strings.Split(content, "\n")
	for i, line := range lines {
		trimmed := strings.TrimLeft(line, " \t")
		rest, ok := strings.CutPrefix(trimmed, "env APT_SNAPSHOT=")
		if !ok {
			continue
		}
		indent := line[:len(line)-len(trimmed)]
		lines[i] = indent + "env APT_SNAPSHOT=" + id
		return strings.Join(lines, "\n"), strings.TrimSpace(rest), true
	}

	at := 0
	for at < len(lines) && strings.HasPrefix(strings.TrimSpace(lines[at]), "#") {
		at++
	}
	insert := []string{"env APT_SNAPSHOT=" + id, ""}
	if at > 0 {
		// Keep one blank line between the header and the new directive.
		if at < len(lines) && strings.TrimSpace(lines[at]) == "" {
			at++
		} else {
			insert = append([]string{""}, insert...)
		}
	}
	lines = slices.Insert(lines, at, insert...)
	return strings.Join(lines, "\n"), "", false
}

// snapshotChange is what changeAptSnapshotOnly did, for the caller to report.
type snapshotChange struct {
	previous    string // the id the line held; "" for none or no freeze
	hadLine     bool   // the Boothfile had an `env APT_SNAPSHOT=` line
	changed     bool   // the line's value differs from the requested one
	handWritten bool   // the Boothfile was not booth config's own before the edit
	content     string // the Boothfile as it is (or, under dryrun, would be) after
}

// changeAptSnapshotOnly sets the apt snapshot of the booth at targetPath to id by
// rewriting that one Boothfile line. Nothing else in .booth/ is read for writing
// or touched. When the Boothfile was booth config's own before the edit (Drifted
// does not list it), its fingerprint is re-stamped so it stays generated; a
// hand-written Boothfile keeps its hand-written status — its line is changed
// because that was asked for, but the rest of it is still the user's.
func changeAptSnapshotOnly(targetPath, id string, dryrun bool) (snapshotChange, error) {
	path := filepath.Join(targetPath, ".booth", "Boothfile")
	info, err := os.Stat(path)
	if err != nil {
		return snapshotChange{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return snapshotChange{}, err
	}

	updated, previous, hadLine := setAptSnapshotLine(string(data), id)
	change := snapshotChange{
		previous:    previous,
		hadLine:     hadLine,
		changed:     !hadLine || previous != id,
		handWritten: slices.Contains(output.Drifted(targetPath), "Boothfile"),
		content:     string(data),
	}
	if !change.changed {
		return change, nil
	}
	change.content = updated
	if dryrun {
		return change, nil
	}

	if err := os.WriteFile(path, []byte(updated), info.Mode().Perm()); err != nil {
		return change, fmt.Errorf("writing %s: %w", path, err)
	}
	if !change.handWritten {
		if err := output.RefreshManifest(targetPath, []string{"Boothfile"}); err != nil {
			return change, fmt.Errorf("updating %s: %w", output.ManifestName, err)
		}
	}
	return change, nil
}

// runConfigSnapshotOnly is the one-line path for `booth config --no-tui
// --apt-snapshot <id>` on a booth that already has a Boothfile. ok is false when
// there is no Boothfile — a first configure, which the full path handles.
func runConfigSnapshotOnly(version, targetPath string, flags initFlags) (ok bool) {
	boothfile := filepath.Join(targetPath, ".booth", "Boothfile")
	if _, err := os.Stat(boothfile); err != nil {
		return false
	}

	change, err := changeAptSnapshotOnly(targetPath, flags.aptSnapshot, flags.dryrun)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	reportSnapshotChange(os.Stdout, targetPath, flags.aptSnapshot, flags.dryrun, change)
	if change.changed {
		warnSnapshotOlderThanImage(os.Stderr, targetPath, version, change.content)
	}
	return true
}

// showSnapshot names an id for a message; the empty one is "none" (no freeze).
func showSnapshot(id string) string {
	if id == "" {
		return "none"
	}
	return id
}

func reportSnapshotChange(w io.Writer, targetPath, id string, dryrun bool, change snapshotChange) {
	rel := filepath.Join(".booth", "Boothfile")
	if targetPath != "." {
		rel = filepath.Join(targetPath, rel)
	}
	if !change.changed {
		fmt.Fprintf(w, "apt snapshot is already %s in %s; nothing changed.\n", showSnapshot(id), rel)
		return
	}

	verb := "Set"
	if dryrun {
		verb = "Would set"
	}
	from := showSnapshot(change.previous)
	if !change.hadLine {
		from = "no line"
	}
	fmt.Fprintf(w, "%s apt snapshot in %s: %s -> %s (that line only; the rest of .booth/ is untouched).\n",
		verb, rel, from, showSnapshot(id))
	if change.handWritten {
		fmt.Fprintf(w, "%s is hand-written, so it stays hand-written: %s was not re-stamped.\n",
			rel, output.ManifestName)
	}
}

// warnSnapshotOlderThanImage is warnAptSnapshotOlderThanImage for the one-line
// path, which has no compiled output: the image settings come from the booth's
// config.toml as it is on disk.
func warnSnapshotOlderThanImage(w io.Writer, targetPath, version, boothfile string) {
	out := &output.BoothOutput{
		Boothfile: &output.BoothfileContent{Content: boothfile},
		Config:    readConfigImageSettings(targetPath),
	}
	warnAptSnapshotOlderThanImage(w, out, targetPath, version)
}

// readConfigImageSettings reads the image-relevant keys of .booth/config.toml into
// the shape configImageSettings takes. A missing or unreadable file gives the
// zero config, which names the default image as a run would.
func readConfigImageSettings(targetPath string) *output.ConfigToml {
	cfg := &output.ConfigToml{Overrides: map[string]any{}}
	var raw map[string]any
	if _, err := toml.DecodeFile(filepath.Join(targetPath, ".booth", "config.toml"), &raw); err != nil {
		return cfg
	}
	if v, ok := raw["variant"].(string); ok {
		cfg.Variant = v
	}
	if v, ok := raw["dind"].(bool); ok {
		cfg.Dind = v
	}
	for _, key := range []string{"version", "engine", "image", "egress"} {
		if v, ok := raw[key]; ok {
			cfg.Overrides[key] = v
		}
	}
	return cfg
}
