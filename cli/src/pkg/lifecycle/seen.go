// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// StateGone is the State of a booth booth dashboard remembers but whose
// container no longer exists: its folder and its .booth are still there.
const StateGone = "gone"

// Gone reports whether b is a remembered booth with no container.
func (b Booth) Gone() bool { return b.State == StateGone }

// Seen is the booths booth dashboard has seen, kept in a file so they still
// show after their containers are removed. It is a cache: a missing or broken
// file only means nothing is remembered.
type Seen struct {
	Path string
	// Engine, when set, limits what Remember returns to that engine's booths
	// (booth dashboard --engine).
	Engine string
	// Now is the clock (when a booth was last seen); nil is time.Now.
	Now func() time.Time
}

type seenEntry struct {
	Name     string `json:"name"`
	Engine   string `json:"engine"`
	Variant  string `json:"variant,omitempty"`
	CodePath string `json:"codePath"`
	BoothDir string `json:"boothDir,omitempty"`
	LastSeen string `json:"lastSeen"` // RFC 3339
}

func seenKey(name, engine string) string { return name + "@" + engine }

// DefaultSeen is the store under the user's cache directory.
func DefaultSeen(engine string) Seen {
	base, err := os.UserCacheDir()
	if err != nil {
		return Seen{Engine: engine}
	}
	return Seen{Path: filepath.Join(base, "codingbooth", "dashboard", "seen.json"), Engine: engine}
}

// Remember records the live booths, then returns the remembered booths that
// have no container now, as booths whose State is StateGone (FinishedAt is
// when they were last seen). A booth whose folder or .booth is gone is
// forgotten. Booths of an engine named in warnings (it did not answer) are
// kept but not returned: their containers may well exist.
func (s Seen) Remember(live []Booth, warnings []string) []Booth {
	if s.Path == "" {
		return nil
	}
	now := time.Now
	if s.Now != nil {
		now = s.Now
	}
	entries := s.load()
	changed := false
	liveKeys := map[string]bool{}
	stamp := now().UTC().Format(time.RFC3339)
	for _, b := range live {
		if b.CodePath == "" {
			continue
		}
		key := seenKey(b.Name, b.Engine)
		liveKeys[key] = true
		e := seenEntry{Name: b.Name, Engine: b.Engine, Variant: b.Variant, CodePath: b.CodePath,
			BoothDir: b.BoothDir, LastSeen: stamp}
		old, had := entries[key]
		// Rewrite the file only when something besides the time changed, or
		// the time is a minute old: a refresh every two seconds should not.
		if had && old.Variant == e.Variant && old.CodePath == e.CodePath && old.BoothDir == e.BoothDir &&
			!stale(old.LastSeen, now()) {
			continue
		}
		entries[key] = e
		changed = true
	}

	var gone []Booth
	for key, e := range entries {
		if liveKeys[key] {
			continue
		}
		if !stillThere(e) {
			delete(entries, key)
			changed = true
			continue
		}
		if s.Engine != "" && e.Engine != s.Engine {
			continue
		}
		if engineWarned(e.Engine, warnings) {
			continue
		}
		gone = append(gone, Booth{Name: e.Name, Engine: e.Engine, State: StateGone, Variant: e.Variant,
			CodePath: e.CodePath, BoothDir: e.BoothDir, FinishedAt: e.LastSeen})
	}
	if changed {
		s.save(entries)
	}
	sort.Slice(gone, func(i, j int) bool {
		return seenKey(gone[i].Name, gone[i].Engine) < seenKey(gone[j].Name, gone[j].Engine)
	})
	return gone
}

// Forget drops a remembered booth. Its folder is not touched.
func (s Seen) Forget(name, engine string) error {
	if s.Path == "" {
		return nil
	}
	entries := s.load()
	delete(entries, seenKey(name, engine))
	return s.save(entries)
}

func (s Seen) load() map[string]seenEntry {
	entries := map[string]seenEntry{}
	data, err := os.ReadFile(s.Path)
	if err != nil {
		return entries
	}
	var list []seenEntry
	if json.Unmarshal(data, &list) != nil {
		return entries
	}
	for _, e := range list {
		if e.Name != "" && e.CodePath != "" {
			entries[seenKey(e.Name, e.Engine)] = e
		}
	}
	return entries
}

func (s Seen) save(entries map[string]seenEntry) error {
	list := make([]seenEntry, 0, len(entries))
	for _, e := range entries {
		list = append(list, e)
	}
	sort.Slice(list, func(i, j int) bool {
		return seenKey(list[i].Name, list[i].Engine) < seenKey(list[j].Name, list[j].Engine)
	})
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(s.Path), 0o755); err != nil {
		return err
	}
	// Write then rename, so a second dashboard never reads half a file.
	tmp, err := os.CreateTemp(filepath.Dir(s.Path), ".seen-*.json")
	if err != nil {
		return err
	}
	if _, err := tmp.Write(append(data, '\n')); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return os.Rename(tmp.Name(), s.Path)
}

// stillThere: the booth's folder and its .booth both exist.
func stillThere(e seenEntry) bool {
	if info, err := os.Stat(e.CodePath); err != nil || !info.IsDir() {
		return false
	}
	boothDir := e.BoothDir
	if boothDir == "" {
		boothDir = filepath.Join(e.CodePath, ".booth")
	}
	info, err := os.Stat(boothDir)
	return err == nil && info.IsDir()
}

func stale(stamp string, now time.Time) bool {
	t, err := time.Parse(time.RFC3339, stamp)
	return err != nil || now.Sub(t) > time.Minute
}

func engineWarned(engine string, warnings []string) bool {
	for _, w := range warnings {
		if strings.Contains(strings.ToLower(w), engine) {
			return true
		}
	}
	return false
}
