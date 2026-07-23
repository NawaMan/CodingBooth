// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestConfigKeys_KindsMatchTheStruct(t *testing.T) {
	keys := ConfigKeys()

	cases := []struct {
		key  string
		kind KeyKind
	}{
		{"variant", KeyString},
		{"timezone", KeyString},
		{"dind", KeyBool},
		{"persist-home", KeyBool},
		{"idle-time", KeyInt},
		{"idle-exit-code", KeyInt},
		{"run-args", KeyList},
		{"cmds", KeyList},
		{"egress-allowlist", KeyList},

		// Wrapper types are transparent: what matters is the shape a user writes,
		// not how the field stores it.
		{"dryrun", KeyBool},    // nillable.NillableBool
		{"version", KeyString}, // nillable.NillableString
	}

	for _, c := range cases {
		spec, ok := keys[c.key]
		assert.True(t, ok, "%s should be a known config key", c.key)
		assert.Equal(t, c.kind, spec.Kind, "kind of %s", c.key)
	}
}

func TestConfigKeys_IncludesKeysReadOutsideAppConfig(t *testing.T) {
	// cache-files and cache-dirs are honored config.toml keys read by their own
	// ad-hoc structs, not by AppConfig. Reflection alone would call them unknown
	// and any validation built on it would reject two perfectly valid keys.
	keys := ConfigKeys()

	for _, key := range []string{"cache-files", "cache-dirs"} {
		spec, ok := keys[key]
		assert.True(t, ok, "%s is read from config.toml and must be known", key)
		assert.Equal(t, KeyList, spec.Kind)
		assert.True(t, spec.Read)
	}
}

func TestConfigKeys_MarksKeysBoothNeverReadsFromFile(t *testing.T) {
	// Tagged toml:"-" — accepted as flags, never decoded from a file. They are
	// reported rather than dropped so callers can warn instead of pretending the
	// setting took effect.
	keys := ConfigKeys()

	for _, key := range []string{"public", "tlscert", "tlskey"} {
		spec, ok := keys[key]
		assert.True(t, ok, "%s should still be a known key", key)
		assert.False(t, spec.Read, "%s is never read from config.toml", key)
	}
}

func TestConfigKeys_OrdinaryKeysAreRead(t *testing.T) {
	assert.True(t, ConfigKeys()["variant"].Read)
}

func TestSuggestConfigKey(t *testing.T) {
	assert.Equal(t, "persist-home", SuggestConfigKey("persist-hom"))
	assert.Equal(t, "timezone", SuggestConfigKey("timzone"))
	assert.Equal(t, "idle-time", SuggestConfigKey("idletime"))

	// Nothing close enough is worth guessing at.
	assert.Equal(t, "", SuggestConfigKey("completely-unrelated-nonsense"))
}
