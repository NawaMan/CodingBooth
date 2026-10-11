// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package mountoverlap

import (
	"strings"
	"testing"
)

func noStrip(s string) string { return strings.TrimSuffix(s, ":0700") }

func TestFind_SameKindNeverOverlaps(t *testing.T) {
	// Two Shared extensions on one folder (chrome +bookmarks-shared and
	// +settings-shared both take Default/) are one mount, not a conflict.
	entries := FromConfig(nil, []string{"home/coder/.chrome-data"}, nil,
		[]string{"home/coder/.chrome-data/Default", "home/coder/.chrome-data/Default"}, noStrip)
	entries = append(entries, Entry{Kind: Cache, Path: "/home/coder/.chrome-data/x", Dir: false})
	dups, nested := Find(entries)
	if len(dups) != 0 {
		t.Fatalf("duplicates = %v, want none", dups)
	}
	// The Default entry, listed twice, is one entry and nests in the Cache folder once;
	// the Cache file inside the Cache folder is not reported.
	if len(nested) != 1 {
		t.Fatalf("nested = %v, want 1", nested)
	}
}

func TestFind_Duplicate(t *testing.T) {
	entries := FromConfig([]string{"home/coder/.zsh_history"}, nil, []string{"/home/coder/.zsh_history"}, nil, noStrip)
	dups, nested := Find(entries)
	if len(nested) != 0 || len(dups) != 1 {
		t.Fatalf("dups=%v nested=%v, want 1 duplicate", dups, nested)
	}
	if dups[0].Outer.Kind != Cache || dups[0].Inner.Kind != Shared {
		t.Errorf("duplicate = %+v, want Outer=cache Inner=shared", dups[0])
	}
	msg := DuplicateError(dups).Error()
	for _, want := range []string{".booth/cache/home/coder/.zsh_history", ".booth/shared/home/coder/.zsh_history", "Refusing to start"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error %q lacks %q", msg, want)
		}
	}
}

func TestFind_DuplicateFolderAndFile(t *testing.T) {
	// A file on one side and a folder on the other at one path is still one target.
	entries := []Entry{{Kind: Shared, Path: "/a/b", Dir: false}, {Kind: Cache, Path: "/a/b", Dir: true}}
	dups, _ := Find(entries)
	if len(dups) != 1 || dups[0].Outer.Kind != Cache {
		t.Fatalf("dups = %v, want 1 with Cache outer", dups)
	}
}

func TestFind_NestedBothWays(t *testing.T) {
	entries := FromConfig(
		nil, []string{"home/coder/.local/share/code-server", "home/coder/.gnupg:0700"},
		[]string{"home/coder/.local/share/code-server/User/settings.json"}, []string{"home/coder"},
		noStrip)
	_, nested := Find(entries)
	// Cache code-server and Cache .gnupg lie inside Shared /home/coder; Shared
	// settings.json lies inside Cache code-server. A file never contains anything.
	got := []string{}
	for _, n := range nested {
		got = append(got, n.Outer.Kind+":"+n.Outer.Path+" > "+n.Inner.Kind+":"+n.Inner.Path)
	}
	want := []string{
		"shared:/home/coder > cache:/home/coder/.gnupg",
		"shared:/home/coder > cache:/home/coder/.local/share/code-server",
		"cache:/home/coder/.local/share/code-server > shared:/home/coder/.local/share/code-server/User/settings.json",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("nested =\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestFind_PrefixIsNotNesting(t *testing.T) {
	// /home/coder/.mozilla-old is not inside /home/coder/.mozilla.
	entries := []Entry{{Kind: Cache, Path: "/home/coder/.mozilla", Dir: true}, {Kind: Shared, Path: "/home/coder/.mozilla-old", Dir: true}}
	dups, nested := Find(entries)
	if len(dups)+len(nested) != 0 {
		t.Fatalf("dups=%v nested=%v, want none", dups, nested)
	}
}

func TestNotice(t *testing.T) {
	shared := Notice(Overlap{Outer: Entry{Cache, "/c", true}, Inner: Entry{Shared, "/c/s", true}})
	if !strings.Contains(shared, "Shared /c/s (committed to git) lies inside Cache /c") {
		t.Errorf("notice = %q", shared)
	}
	cache := Notice(Overlap{Outer: Entry{Shared, "/s", true}, Inner: Entry{Cache, "/s/c", false}})
	if !strings.Contains(cache, "Cache /s/c (kept out of git) lies inside Shared /s") {
		t.Errorf("notice = %q", cache)
	}
}
