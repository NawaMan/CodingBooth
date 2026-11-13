// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Order is the order of booth dashboard's rows (ctrl+↑/↓), kept in a file so
// the next dashboard opens with it. It is a list of keys, first on top: a
// group's ("repo:<root>", or a booth in no repository's name@engine) and a
// linked worktree's within its group ("worktree:<path>"). Each is remembered
// with its folder: once the folder is gone, the entry is dropped. A missing or
// broken file only means no order yet.
type Order struct {
	Path string
}

// OrderEntry is one key of the order, with the folder it is about.
type OrderEntry struct {
	Key  string `json:"key"`
	Path string `json:"path"`
}

// DefaultOrder is the store beside the hidden rows, under the user's cache
// directory.
func DefaultOrder() Order {
	base, err := os.UserCacheDir()
	if err != nil {
		return Order{}
	}
	return Order{Path: filepath.Join(base, "codingbooth", "dashboard", "order.json")}
}

// Load is the order, first on top. Entries whose folder is gone are dropped
// from the file.
func (o Order) Load() []OrderEntry {
	if o.Path == "" {
		return nil
	}
	data, err := os.ReadFile(o.Path)
	if err != nil {
		return nil
	}
	var list []OrderEntry
	if json.Unmarshal(data, &list) != nil {
		return nil
	}
	kept := list[:0:0]
	seen := map[string]bool{}
	for _, e := range list {
		if e.Key == "" || seen[e.Key] {
			continue
		}
		if e.Path != "" {
			if info, err := os.Stat(e.Path); err != nil || !info.IsDir() {
				continue
			}
		}
		seen[e.Key] = true
		kept = append(kept, e)
	}
	if len(kept) != len(list) {
		_ = o.Save(kept)
	}
	return kept
}

// Save replaces the order.
func (o Order) Save(entries []OrderEntry) error {
	if o.Path == "" {
		return nil
	}
	if entries == nil {
		entries = []OrderEntry{}
	}
	return writeJSON(o.Path, entries)
}
