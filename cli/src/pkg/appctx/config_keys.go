// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"reflect"
	"sort"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

// KeyKind is the TOML shape a config.toml key expects. Writing a key with the
// wrong shape produces a file booth cannot load at all — a quoted "30" against
// an int field fails the decode outright — so anything generating config.toml
// has to know the kind before it writes the value.
type KeyKind int

const (
	KeyString KeyKind = iota
	KeyBool
	KeyInt
	KeyList
)

func (k KeyKind) String() string {
	switch k {
	case KeyBool:
		return "boolean"
	case KeyInt:
		return "integer"
	case KeyList:
		return "list"
	default:
		return "string"
	}
}

// KeySpec describes one config.toml key.
type KeySpec struct {
	Key  string
	Kind KeyKind

	// Read is false for keys booth accepts on the command line but never reads
	// back out of config.toml — the AppConfig fields tagged `toml:"-"`. Writing
	// one produces a line that looks effective and is silently ignored, so
	// callers should say so rather than pretend it took.
	Read bool
}

// extraConfigKeys are honored config.toml keys that do not live on AppConfig.
// They are read by their own ad-hoc structs — ensureCacheFromConfig in
// pkg/booth, and extractUserRunArgs in cmd/codingbooth — so reflection over
// AppConfig alone would report them as unknown and reject them.
//
// They are listed here so that ConfigKeys() is the single answer to "what may
// appear in a config.toml", whichever reader ends up consuming it.
var extraConfigKeys = []KeySpec{
	{Key: "cache-files", Kind: KeyList, Read: true},
	{Key: "cache-dirs", Kind: KeyList, Read: true},
	{Key: "shared-files", Kind: KeyList, Read: true},
	{Key: "shared-dirs", Kind: KeyList, Read: true},
}

// ConfigKeys returns every key a .booth/config.toml may hold, keyed by name.
//
// It is derived from the AppConfig struct tags rather than hand-listed, because
// a hand-kept copy drifts: the config TUI's own field table drifted from this
// struct and silently dropped user settings for as long as it did. Anything that
// needs to know the key set — validation, generation, the TUI — should ask here.
func ConfigKeys() map[string]KeySpec {
	specs := make(map[string]KeySpec)

	t := reflect.TypeOf(AppConfig{})
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		key := strings.Split(field.Tag.Get("toml"), ",")[0]

		// `toml:"-"` means booth never reads this from a file. The key is still
		// known — it is a real setting, reachable as a command-line flag — so it
		// is reported rather than dropped, with Read false to mark the gap.
		read := true
		if key == "-" {
			read = false
			key = strings.ToLower(field.Name)
		}
		if key == "" {
			key = strings.ToLower(field.Name)
		}

		specs[key] = KeySpec{Key: key, Kind: kindOf(field.Type), Read: read}
	}

	for _, spec := range extraConfigKeys {
		specs[spec.Key] = spec
	}

	return specs
}

// kindOf maps a struct field type onto the TOML shape it decodes from. The
// nillable and ilist wrappers are transparent here: what matters is the shape a
// user has to write, not how the field stores it.
func kindOf(t reflect.Type) KeyKind {
	switch t {
	case reflect.TypeOf(nillable.NillableBool{}):
		return KeyBool
	case reflect.TypeOf(nillable.NillableString{}):
		return KeyString
	case reflect.TypeOf(ilist.SemicolonStringList{}):
		return KeyList
	}

	switch t.Kind() {
	case reflect.Bool:
		return KeyBool
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return KeyInt
	case reflect.Slice:
		return KeyList
	default:
		return KeyString
	}
}

// SuggestConfigKey returns the known key closest to the given one, or "" when
// nothing is close enough to be worth suggesting. Used to turn a rejected typo
// into a pointer at what was meant.
func SuggestConfigKey(key string) string {
	const maxDistance = 3

	best, bestDistance := "", maxDistance+1
	keys := make([]string, 0, len(ConfigKeys()))
	for k := range ConfigKeys() {
		keys = append(keys, k)
	}
	sort.Strings(keys) // deterministic pick among equally-distant candidates

	for _, candidate := range keys {
		d := editDistance(key, candidate)
		if d < bestDistance {
			best, bestDistance = candidate, d
		}
	}
	if bestDistance > maxDistance {
		return ""
	}
	return best
}

// editDistance is the Levenshtein distance between two strings.
func editDistance(a, b string) int {
	if a == b {
		return 0
	}
	prev := make([]int, len(b)+1)
	curr := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		curr[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			curr[j] = min3(curr[j-1]+1, prev[j]+1, prev[j-1]+cost)
		}
		prev, curr = curr, prev
	}
	return prev[len(b)]
}

func min3(a, b, c int) int {
	m := a
	if b < m {
		m = b
	}
	if c < m {
		m = c
	}
	return m
}
