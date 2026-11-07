// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package pathmount reads a .booth/cache/ or .booth/shared/ tree: what in it can be mounted
// (Walk), what config.toml declares (Declared), and so what is left over (Split) -- an item a
// deselected template made, which booth no longer mounts and `booth prune cache|shared` removes.
//
// The tree mirrors the container's root. A folder holding a .mount-this marker is one item (the
// whole folder) and the walk stops there; any other file is an item of its own, except one at the
// top of the tree (a README.md would land at /README.md).
package pathmount

import (
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/BurntSushi/toml"

	"github.com/nawaman/codingbooth/src/pkg/pathmode"
)

// Marker makes a folder in the tree one item: the whole folder is mounted.
const Marker = ".mount-this"

// Entry is one item of a tree: Rel is its slash path under the tree root (= its container path
// without the leading slash), Dir whether it is a marked folder.
type Entry struct {
	Rel string
	Dir bool
}

// Walk returns the items of tree, in walk order (names sorted, depth first). A missing tree has none.
func Walk(tree string) []Entry {
	var entries []Entry
	walk(tree, tree, &entries)
	return entries
}

func walk(base, dir string, out *[]Entry) {
	items, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	rel, err := filepath.Rel(base, dir)
	if err != nil {
		return
	}
	if rel != "." {
		for _, item := range items {
			if !item.IsDir() && item.Name() == Marker {
				*out = append(*out, Entry{Rel: filepath.ToSlash(rel), Dir: true})
				return // the whole folder is the item
			}
		}
	}
	for _, item := range items {
		if item.Name() == Marker {
			continue
		}
		full := filepath.Join(dir, item.Name())
		if item.IsDir() {
			walk(base, full, out)
		} else if dir != base {
			fileRel, err := filepath.Rel(base, full)
			if err != nil {
				continue
			}
			*out = append(*out, Entry{Rel: filepath.ToSlash(fileRel)})
		}
	}
}

// Declared returns the paths config.toml in boothDir declares for kind ("cache" or "shared"):
// <kind>-files and <kind>-dirs, mode suffixes dropped, in the slash form Walk gives. Never nil;
// a booth without config.toml (or with one that does not parse) declares nothing.
func Declared(boothDir, kind string) map[string]bool {
	declared := map[string]bool{}
	data, err := os.ReadFile(filepath.Join(boothDir, "config.toml"))
	if err != nil {
		return declared
	}
	var cfg map[string]any
	if _, err := toml.Decode(string(data), &cfg); err != nil {
		return declared
	}
	for _, key := range []string{kind + "-files", kind + "-dirs"} {
		list, _ := cfg[key].([]any)
		for _, v := range list {
			entry, ok := v.(string)
			if !ok {
				continue
			}
			p, _, err := pathmode.Split(entry)
			if err != nil {
				p = pathmode.Path(entry)
			}
			if rel := CleanRel(p); rel != "." && rel != "" {
				declared[rel] = true
			}
		}
	}
	return declared
}

// CleanRel turns a declared path ("home/coder/.x/", "./home//coder/.x", "/home/coder/.x") into
// the slash form Walk gives ("home/coder/.x").
func CleanRel(p string) string {
	return path.Clean(strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(p)), "/"))
}

// Covered reports whether rel is a declared path or inside one.
func Covered(declared map[string]bool, rel string) bool {
	for p := CleanRel(rel); p != "." && p != "/" && p != ""; p = path.Dir(p) {
		if declared[p] {
			return true
		}
	}
	return false
}

// Split parts entries into those config.toml declares (mounted) and the leftovers (not).
func Split(entries []Entry, declared map[string]bool) (kept, left []Entry) {
	for _, e := range entries {
		if Covered(declared, e.Rel) {
			kept = append(kept, e)
		} else {
			left = append(left, e)
		}
	}
	return kept, left
}

// Leftovers returns the items of boothDir's <kind> tree that its config.toml does not declare.
func Leftovers(boothDir, kind string) []Entry {
	_, left := Split(Walk(filepath.Join(boothDir, kind)), Declared(boothDir, kind))
	return left
}

// Display is how an item is named to the user: .booth/<kind>/<rel>, with a trailing slash for a
// folder.
func Display(kind string, e Entry) string {
	s := ".booth/" + kind + "/" + e.Rel
	if e.Dir {
		s += "/"
	}
	return s
}

// LeftoverNotice words the start's skip of leftovers, one block per tree; "" when there are none.
func LeftoverNotice(kind string, left []Entry) string {
	if len(left) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString("   Not mounting what config.toml does not declare (left by a deselected template?):\n")
	for _, e := range left {
		b.WriteString("     " + Display(kind, e) + "\n")
	}
	b.WriteString("   'booth prune " + kind + "' removes them; 'booth config --set " + kind + "-dirs=<path>' (or " +
		kind + "-files) keeps one mounted.\n")
	return b.String()
}
