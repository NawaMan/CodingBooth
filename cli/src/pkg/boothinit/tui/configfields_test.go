// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// TestFieldTableCoversSchema is the lock that keeps the field table and
// AppConfig from drifting apart. They did drift, and while they were apart a
// config TUI save deleted every setting the table had fallen behind on.
//
// Adding a field to AppConfig now fails here until it is either given a display
// entry or written down in unrenderedKeys with the reason it is not offered.
func TestFieldTableCoversSchema(t *testing.T) {
	rendered := make(map[string]bool)
	for _, f := range allConfigFields {
		if !f.TUIOnly {
			rendered[f.Key] = true
		}
	}

	for key := range appctx.ConfigKeys() {
		if rendered[key] {
			if reason, alsoExcluded := unrenderedKeys[key]; alsoExcluded {
				t.Errorf("key %q is both rendered and listed as unrendered (%q) — pick one", key, reason)
			}
			continue
		}
		if reason, ok := unrenderedKeys[key]; !ok || reason == "" {
			t.Errorf("config key %q has no TUI field and no entry in unrenderedKeys.\n"+
				"Add a fieldDisplay for it, or record in unrenderedKeys why the TUI does not offer it.", key)
		}
	}
}

// TestNoStaleDisplayEntries catches the mirror case: metadata for a key booth no
// longer reads. Such a field renders, accepts input and writes a line nothing
// consumes — the dead-field problem that put Public and TLS Cert in the TUI.
func TestNoStaleDisplayEntries(t *testing.T) {
	schema := appctx.ConfigKeys()
	for _, d := range fieldDisplays {
		if d.TUIOnly {
			continue
		}
		if _, ok := schema[d.Key]; !ok {
			t.Errorf("fieldDisplay %q is not a config.toml key — remove it, or mark it TUIOnly "+
				"and route its value somewhere other than a --set", d.Key)
		}
	}
}

// TestUnrenderedKeysAreRealKeys keeps the exclusion list honest: an entry for a
// key that no longer exists silently weakens TestFieldTableCoversSchema.
func TestUnrenderedKeysAreRealKeys(t *testing.T) {
	schema := appctx.ConfigKeys()
	for key := range unrenderedKeys {
		if _, ok := schema[key]; !ok {
			t.Errorf("unrenderedKeys lists %q, which is not a config.toml key", key)
		}
	}
}

// TestRenderedFieldsWriteBackAsTheirShape checks the widget a key gets can
// actually round-trip that key's TOML shape. A list key behind a single-value
// text box would silently keep only the last entry; a bool behind a plain text
// box would write `keep-alive = "true"` and fail the decode.
func TestRenderedFieldsWriteBackAsTheirShape(t *testing.T) {
	schema := appctx.ConfigKeys()
	for _, f := range allConfigFields {
		if f.TUIOnly {
			continue
		}
		spec := schema[f.Key]

		switch spec.Kind {
		case appctx.KeyList:
			if f.Kind != fieldKindList {
				t.Errorf("%q is a list key but is rendered as kind %d", f.Key, f.Kind)
			}
		case appctx.KeyInt:
			if f.Kind != fieldKindInt {
				t.Errorf("%q is an integer key but is rendered as kind %d", f.Key, f.Kind)
			}
		case appctx.KeyBool:
			// A cycle is allowed here — that is how a tri-state is offered — but
			// only over the three values a bool key can hold.
			if f.Kind == fieldKindCycle {
				for _, opt := range f.Options {
					if opt != "" && opt != "true" && opt != "false" {
						t.Errorf("%q is a boolean key with non-boolean cycle option %q", f.Key, opt)
					}
				}
				continue
			}
			if f.Kind != fieldKindBool {
				t.Errorf("%q is a boolean key but is rendered as kind %d", f.Key, f.Kind)
			}
		default:
			if f.Kind != fieldKindString && f.Kind != fieldKindCycle {
				t.Errorf("%q is a string key but is rendered as kind %d", f.Key, f.Kind)
			}
		}
	}
}

// TestRenderedConfigKeysRoles checks the write-back roles a save reads. The
// interesting one is sudo: a bool key that must be written as `sudo=false`
// rather than as a bare toggle, because "unset" and "false" differ — sudo
// defaults to on, so losing an explicit false silently restores passwordless
// sudo.
func TestRenderedConfigKeysRoles(t *testing.T) {
	roles := RenderedConfigKeys()

	expected := map[string]ConfigFieldRole{
		"keep-alive":       ConfigFieldToggle,
		"sudo":             ConfigFieldScalar,
		"name":             ConfigFieldScalar,
		"idle-time":        ConfigFieldScalar,
		"egress-mode":      ConfigFieldScalar,
		"egress-allowlist": ConfigFieldList,
		"cmds":             ConfigFieldList,
	}
	for key, want := range expected {
		got, ok := roles[key]
		if !ok {
			t.Errorf("%q is not reported as a rendered config key", key)
			continue
		}
		if got != want {
			t.Errorf("%q: role = %d, want %d", key, got, want)
		}
	}

	// TUI-only fields are not config keys and must never be written as --set.
	for _, key := range []string{"booth-version", "templates-version", "debug", "env", "expose", "mount"} {
		if _, ok := roles[key]; ok {
			t.Errorf("%q is TUI-only but is reported as a rendered config key", key)
		}
	}
}

// TestFieldGroupsAreContiguous guards a rendering assumption: the row builder
// emits a group header every time the group changes, so a group split across
// two runs of the table would show its header twice.
func TestFieldGroupsAreContiguous(t *testing.T) {
	seen := make(map[string]bool)
	last := ""
	for _, f := range allConfigFields {
		if f.Group == last {
			continue
		}
		if seen[f.Group] {
			t.Errorf("group %q appears in more than one run of the field table", f.Group)
		}
		seen[f.Group] = true
		last = f.Group
	}
}

// TestIntFieldsRejectNonDigits covers the keystroke filter. An int key holding
// "soon" fails the TOML decode and takes the whole booth down with it, and
// there is no good moment to reject it later: refusing at save time would mean
// losing every other edit in the session.
func TestIntFieldsRejectNonDigits(t *testing.T) {
	for _, ch := range []byte("0123456789-") {
		if !acceptsEditChar(fieldKindInt, ch) {
			t.Errorf("int field rejected %q", ch)
		}
	}
	for _, ch := range []byte("a .\"") {
		if acceptsEditChar(fieldKindInt, ch) {
			t.Errorf("int field accepted %q", ch)
		}
	}
	for _, ch := range []byte("a .\"") {
		if !acceptsEditChar(fieldKindString, ch) {
			t.Errorf("string field rejected %q", ch)
		}
	}
}

// TestBuildConfigFieldsDropsRemovedKeys pins the behaviour that makes removing
// an AppConfig field safe: the field goes with it, rather than staying on as a
// widget that writes a key nothing reads.
func TestBuildConfigFieldsDropsRemovedKeys(t *testing.T) {
	schema := appctx.ConfigKeys()
	delete(schema, "keep-alive")

	for _, f := range buildConfigFields(schema) {
		if f.Key == "keep-alive" {
			t.Fatal("keep-alive still rendered after being removed from the schema")
		}
	}
}
