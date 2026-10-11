// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package mountoverlap finds where a Cache entry and a Shared entry claim the same
// container path, or one lies inside the other.
//
// The two trees are walked separately and neither can overlap itself: a folder
// with .mount-this stops the walk, so nothing below it is mounted on its own. Across
// the two trees nothing stopped them, and both shapes cost something:
//
//   - The same path twice is two mounts on one target, which Docker refuses with
//     "Duplicate mount point" — an error that names neither .booth/ folder.
//   - One inside the other mounts, but splits a tool's data between git and not-git
//     without saying so. Chrome's +profile-cache (.chrome-data) with
//     +bookmarks-shared (.chrome-data/Default) sends cookies and saved logins,
//     which live in Default/, to git.
package mountoverlap

import (
	"fmt"
	"sort"
	"strings"
)

// Kinds of entry.
const (
	Cache  = "cache"
	Shared = "shared"
)

// Entry is one Cache or Shared path, as the container sees it ("/home/coder/x").
type Entry struct {
	Kind string // Cache or Shared
	Path string // container path, "/"-rooted, no trailing "/"
	Dir  bool   // mounted as a whole folder (.mount-this / *-dirs), not a single file
}

// Overlap is a pair of entries of different kinds. Outer.Path == Inner.Path is a
// duplicate; otherwise Inner lies inside Outer, which is a folder.
type Overlap struct {
	Outer Entry
	Inner Entry
}

// Find reports every duplicate and every nesting between entries of different kinds,
// sorted by path so the output is stable.
func Find(entries []Entry) (duplicates, nested []Overlap) {
	for i, a := range entries {
		for _, b := range entries[i+1:] {
			if a.Kind == b.Kind {
				continue
			}
			switch {
			case a.Path == b.Path:
				outer, inner := a, b
				if outer.Kind != Cache {
					outer, inner = b, a
				}
				duplicates = append(duplicates, Overlap{Outer: outer, Inner: inner})
			case a.Dir && strings.HasPrefix(b.Path, a.Path+"/"):
				nested = append(nested, Overlap{Outer: a, Inner: b})
			case b.Dir && strings.HasPrefix(a.Path, b.Path+"/"):
				nested = append(nested, Overlap{Outer: b, Inner: a})
			}
		}
	}
	sortOverlaps(duplicates)
	sortOverlaps(nested)
	return duplicates, nested
}

func sortOverlaps(list []Overlap) {
	sort.SliceStable(list, func(i, j int) bool {
		if list[i].Outer.Path != list[j].Outer.Path {
			return list[i].Outer.Path < list[j].Outer.Path
		}
		return list[i].Inner.Path < list[j].Inner.Path
	})
}

// Notice is the one line a nested overlap earns: which part of the outer folder goes
// to git and which does not.
func Notice(o Overlap) string {
	if o.Inner.Kind == Shared {
		return fmt.Sprintf("Notice: Shared %s (committed to git) lies inside Cache %s: what is under %s goes to git, the rest of %s stays out of it.",
			o.Inner.Path, o.Outer.Path, o.Inner.Path, o.Outer.Path)
	}
	return fmt.Sprintf("Notice: Cache %s (kept out of git) lies inside Shared %s: what is under %s stays out of git, the rest of %s goes to it.",
		o.Inner.Path, o.Outer.Path, o.Inner.Path, o.Outer.Path)
}

// DuplicateError explains paths that are both Cache and Shared. A booth cannot start
// with one: Docker refuses two mounts on one target.
func DuplicateError(duplicates []Overlap) error {
	var b strings.Builder
	fmt.Fprintf(&b, "%d container path(s) are both Cache and Shared:\n", len(duplicates))
	for _, d := range duplicates {
		fmt.Fprintf(&b, "  %s\t(.booth/cache%s and .booth/shared%s)\n", d.Outer.Path, d.Outer.Path, d.Inner.Path)
	}
	b.WriteString("  One path can be mounted from only one of them.\n")
	b.WriteString("  Remove the entry from .booth/cache/ or .booth/shared/ (and from cache-* or shared-* in config.toml).\n")
	b.WriteString("  Refusing to start")
	return fmt.Errorf("%s", b.String())
}

// FromConfig builds entries from config.toml-style lists: paths relative to the
// container root, a trailing ":0700" mode allowed on a folder. strip removes such a
// suffix (pathmode.Path); it is passed in so this package stays dependency-free.
// A path listed twice (by a template and again in config.toml) is one entry.
func FromConfig(cacheFiles, cacheDirs, sharedFiles, sharedDirs []string, strip func(string) string) []Entry {
	var entries []Entry
	seen := map[Entry]bool{}
	add := func(kind string, list []string, dir bool) {
		for _, p := range list {
			if dir {
				p = strip(p)
			}
			p = "/" + strings.Trim(p, "/")
			e := Entry{Kind: kind, Path: p, Dir: dir}
			if p == "/" || seen[e] {
				continue
			}
			seen[e] = true
			entries = append(entries, e)
		}
	}
	add(Cache, cacheFiles, false)
	add(Cache, cacheDirs, true)
	add(Shared, sharedFiles, false)
	add(Shared, sharedDirs, true)
	return entries
}
