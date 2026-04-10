// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import "testing"

// TestParseArgs_WritableBooth verifies the --writable-booth flag sets WritableBooth true.
func TestParseArgs_WritableBooth(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		Args: []string{"--writable-booth"},
	})

	if !res.Ctx.WritableBooth() {
		t.Fatal("expected WritableBooth to be true with --writable-booth flag")
	}
}

// TestParseArgs_NoWritableBooth verifies the --no-writable-booth flag sets WritableBooth false.
func TestParseArgs_NoWritableBooth(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		Args: []string{"--no-writable-booth"},
	})

	if res.Ctx.WritableBooth() {
		t.Fatal("expected WritableBooth to be false with --no-writable-booth flag")
	}
}

// TestParseArgs_NoWritableBooth_OverridesToml verifies --no-writable-booth overrides config.toml.
func TestParseArgs_NoWritableBooth_OverridesToml(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		Args: []string{"--no-writable-booth"},
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `writable-booth = true`,
		}},
	})

	if res.Ctx.WritableBooth() {
		t.Fatal("expected --no-writable-booth to override config.toml writable-booth=true")
	}
}

// TestParseArgs_WritableBooth_OverridesToml verifies --writable-booth overrides config.toml false.
func TestParseArgs_WritableBooth_OverridesToml(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		Args: []string{"--writable-booth"},
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `writable-booth = false`,
		}},
	})

	if !res.Ctx.WritableBooth() {
		t.Fatal("expected --writable-booth to override config.toml writable-booth=false")
	}
}

// TestParseArgs_WritableBooth_DefaultFalse verifies WritableBooth defaults to false.
func TestParseArgs_WritableBooth_DefaultFalse(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{})

	if res.Ctx.WritableBooth() {
		t.Fatal("expected WritableBooth to default to false")
	}
}
