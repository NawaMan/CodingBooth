// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// A kept booth keeps the image it was created from. It falls behind in two
// ways, which booth dashboard flags:
//
//   - Older: the CodingBooth version that built it is older than the one
//     `booth` uses in its project now: the project's .booth/tools/codingbooth.lock,
//     else the running CLI.
//   - Rebuilt: its image name now points to a newer build (the Boothfile or a
//     setup changed and `booth` rebuilt it), as staleImageWarning says at start.

// Fresh is how a booth stands against what `booth` would build now.
type Fresh struct {
	Want    string // the version `booth` uses in its project now; "" when unknown
	Older   bool   // built with a version older than Want
	Rebuilt bool   // its image name now points to another image
}

// Freshness reports each booth's Fresh, keyed name@engine. cliVersion stands
// in for a project that pins no version.
func Freshness(booths []Booth, cliVersion string) map[string]Fresh {
	current := currentImages(booths)
	out := make(map[string]Fresh, len(booths))
	for _, b := range booths {
		want := pinnedVersion(b)
		if want == "" {
			want = cliVersion
		}
		f := Fresh{Want: want, Older: versionOlder(b.Version, want)}
		if id, ok := current[b.Engine+"|"+b.ImageRef]; ok {
			f.Rebuilt = id != "" && b.ImageID != "" && id != b.ImageID
		}
		out[b.Name+"@"+b.Engine] = f
	}
	return out
}

// pinnedVersion is the version in the booth's project lock file, or "".
func pinnedVersion(b Booth) string {
	dir := b.BoothDir
	if dir == "" {
		if b.CodePath == "" {
			return ""
		}
		dir = filepath.Join(b.CodePath, ".booth")
	}
	file, err := os.Open(filepath.Join(dir, "tools", "codingbooth.lock"))
	if err != nil {
		return ""
	}
	defer file.Close()
	return lockVersion(bufio.NewScanner(file))
}

// lockVersion reads the version= line of a codingbooth.lock.
func lockVersion(lines *bufio.Scanner) string {
	for lines.Scan() {
		if value, ok := strings.CutPrefix(strings.TrimSpace(lines.Text()), "version="); ok {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

// versionOlder reports whether have's x.y.z is below want's. A session or
// release-candidate suffix (--rc1, --feature) is not compared, and a version
// that does not parse is never older.
func versionOlder(have, want string) bool {
	h, ok1 := versionTriple(have)
	w, ok2 := versionTriple(want)
	if !ok1 || !ok2 {
		return false
	}
	for i := range h {
		if h[i] != w[i] {
			return h[i] < w[i]
		}
	}
	return false
}

func versionTriple(version string) ([3]int, bool) {
	var out [3]int
	version = strings.TrimPrefix(strings.TrimSpace(version), "v")
	if i := strings.Index(version, "--"); i >= 0 {
		version = version[:i]
	}
	if i := strings.IndexAny(version, "-+"); i >= 0 {
		version = version[:i]
	}
	parts := strings.Split(version, ".")
	if len(parts) != 3 {
		return out, false
	}
	for i, part := range parts {
		n, err := strconv.Atoi(part)
		if err != nil {
			return out, false
		}
		out[i] = n
	}
	return out, true
}

// currentImages is the image ID each booth's image name points to now, keyed
// engine|name; a name that no longer resolves is left out. Answers are kept
// for a while: images change on a build, not every refresh.
func currentImages(booths []Booth) map[string]string {
	out := map[string]string{}
	for _, b := range booths {
		if b.ImageRef == "" {
			continue
		}
		key := b.Engine + "|" + b.ImageRef
		if _, done := out[key]; done {
			continue
		}
		if id, ok := imageCache.get(key, func() (string, bool) {
			text, err := docker.DockerOutput(docker.DockerFlags{Silent: true, Engine: b.Engine}, "image", ilist.NewList(
				ilist.NewList("inspect"), ilist.NewList("--format", "{{.Id}}"), ilist.NewList(b.ImageRef)))
			return strings.TrimSpace(text), err == nil
		}); ok {
			out[key] = id
		}
	}
	return out
}

// imageCache remembers image IDs for imageCacheTTL.
var imageCache = &ttlCache{entries: map[string]ttlEntry{}}

const imageCacheTTL = 30 * time.Second

type ttlCache struct {
	mu      sync.Mutex
	entries map[string]ttlEntry
	now     func() time.Time
}

type ttlEntry struct {
	value string
	ok    bool
	at    time.Time
}

func (c *ttlCache) get(key string, load func() (string, bool)) (string, bool) {
	now := time.Now
	if c.now != nil {
		now = c.now
	}
	c.mu.Lock()
	entry, found := c.entries[key]
	c.mu.Unlock()
	if found && now().Sub(entry.at) < imageCacheTTL {
		return entry.value, entry.ok
	}
	value, ok := load()
	c.mu.Lock()
	c.entries[key] = ttlEntry{value: value, ok: ok, at: now()}
	c.mu.Unlock()
	return value, ok
}
