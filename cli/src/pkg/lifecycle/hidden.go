// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
)

// Hidden is the rows booth dashboard hides (h), kept in a file so they stay
// hidden the next time it opens. A row is named by the dashboard's key for it
// (a booth's name@engine, a worktree's "worktree:<path>") and remembered with
// its folder: once the folder is gone, the entry is dropped. A missing or
// broken file only means nothing is hidden.
type Hidden struct {
	Path string
}

type hiddenEntry struct {
	Key  string `json:"key"`
	Path string `json:"path"` // the row's folder: a booth's code path, or the worktree
}

// DefaultHidden is the store beside the seen booths, under the user's cache
// directory.
func DefaultHidden() Hidden {
	base, err := os.UserCacheDir()
	if err != nil {
		return Hidden{}
	}
	return Hidden{Path: filepath.Join(base, "codingbooth", "dashboard", "hidden.json")}
}

// Keys is the hidden rows' keys. Entries whose folder is gone are dropped
// from the file.
func (h Hidden) Keys() map[string]bool {
	keys := map[string]bool{}
	if h.Path == "" {
		return keys
	}
	entries := h.load()
	changed := false
	for key, e := range entries {
		if e.Path != "" {
			if info, err := os.Stat(e.Path); err != nil || !info.IsDir() {
				delete(entries, key)
				changed = true
				continue
			}
		}
		keys[key] = true
	}
	if changed {
		h.save(entries)
	}
	return keys
}

// Set hides the row named key (whose folder is path), or shows it again.
func (h Hidden) Set(key, path string, hidden bool) error {
	if h.Path == "" || key == "" {
		return nil
	}
	entries := h.load()
	if hidden {
		entries[key] = hiddenEntry{Key: key, Path: path}
	} else {
		if _, had := entries[key]; !had {
			return nil
		}
		delete(entries, key)
	}
	return h.save(entries)
}

func (h Hidden) load() map[string]hiddenEntry {
	entries := map[string]hiddenEntry{}
	data, err := os.ReadFile(h.Path)
	if err != nil {
		return entries
	}
	var list []hiddenEntry
	if json.Unmarshal(data, &list) != nil {
		return entries
	}
	for _, e := range list {
		if e.Key != "" {
			entries[e.Key] = e
		}
	}
	return entries
}

func (h Hidden) save(entries map[string]hiddenEntry) error {
	list := make([]hiddenEntry, 0, len(entries))
	for _, e := range entries {
		list = append(list, e)
	}
	sort.Slice(list, func(i, j int) bool { return list[i].Key < list[j].Key })
	return writeJSON(h.Path, list)
}
