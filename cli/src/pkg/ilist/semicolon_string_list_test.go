// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package ilist

import (
	"os"
	"testing"
)

func TestSemicolonStringList_Decode(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		{"Empty", "", []string{}},
		{"Whitespace", "   ", []string{}},
		{"Single", "a", []string{"a"}},
		{"Multiple", "a;b;c", []string{"a", "b", "c"}},
		{"TrimEdges", " a ; b ; c ", []string{"a", "b", "c"}},
		{"SkipEmpty", "a;;b", []string{"a", "b"}},
		{"Complex", " a ; ; b ; c ", []string{"a", "b", "c"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var list SemicolonStringList
			err := list.Decode(tt.input)
			if err != nil {
				t.Fatalf("Decode failed: %v", err)
			}

			if list.Length() != len(tt.expected) {
				t.Errorf("Length() = %d, want %d", list.Length(), len(tt.expected))
			}

			for i, want := range tt.expected {
				if got, _ := list.Get(i); got != want {
					t.Errorf("Get(%d) = %q, want %q", i, got, want)
				}
			}
		})
	}
}

func TestSemicolonStringList_Clone(t *testing.T) {
	var list SemicolonStringList
	list.Decode("original")

	cloned := list.Clone()

	// Verify deep copy by checking values
	if cloned.Length() != 1 {
		t.Errorf("Cloned Length() = %d, want 1", cloned.Length())
	}
	if v, _ := cloned.Get(0); v != "original" {
		t.Errorf("Cloned Get(0) = %q, want 'original'", v)
	}

	// Verify independence (we can't easily mutate List[string] externally without unsafe or re-decoding)
	// Re-decode original
	list.Decode("modified")

	if v, _ := cloned.Get(0); v != "original" {
		t.Errorf("Cloned list affected by original modification: got %q", v)
	}
}

func TestSemicolonStringList_UnmarshalTOML(t *testing.T) {
	tests := []struct {
		name     string
		input    interface{}
		expected []string
		wantErr  bool
	}{
		{"String", "-p;10005", []string{"-p", "10005"}, false},
		{"EmptyString", "", []string{}, false},
		{"SingleValue", "value", []string{"value"}, false},
		{"MultipleValues", "a;b;c", []string{"a", "b", "c"}, false},
		{"WithSpaces", " a ; b ; c ", []string{"a", "b", "c"}, false},
		{"NonString", 123, nil, false}, // Should return nil (let TOML handle type errors)
		// TOML array tests
		{"Array", []interface{}{"-v", "/host:/container"}, []string{"-v", "/host:/container"}, false},
		{"EmptyArray", []interface{}{}, []string{}, false},
		{"ArrayWithMixedTypes", []interface{}{"-e", 123, "VAR=value"}, []string{"-e", "VAR=value"}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var list SemicolonStringList
			err := list.UnmarshalTOML(tt.input)

			if (err != nil) != tt.wantErr {
				t.Errorf("UnmarshalTOML() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if tt.expected == nil {
				return // Skip validation for non-string inputs
			}

			if list.Length() != len(tt.expected) {
				t.Errorf("Length() = %d, want %d", list.Length(), len(tt.expected))
			}

			for i, want := range tt.expected {
				if got, _ := list.Get(i); got != want {
					t.Errorf("Get(%d) = %q, want %q", i, got, want)
				}
			}
		})
	}
}

func TestExpandEnv(t *testing.T) {
	// Set up test environment variables
	home := os.Getenv("HOME")
	os.Setenv("TEST_VAR", "test_value")
	os.Setenv("ANOTHER_VAR", "another")
	defer os.Unsetenv("TEST_VAR")
	defer os.Unsetenv("ANOTHER_VAR")

	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"NoExpansion", "/absolute/path", "/absolute/path"},
		{"TildeOnly", "~", home},
		{"TildeSlash", "~/config", home + "/config"},
		{"TildeDeep", "~/.config/app", home + "/.config/app"},
		{"DollarVar", "$TEST_VAR/path", "test_value/path"},
		{"BraceVar", "${TEST_VAR}/path", "test_value/path"},
		{"MultipleVars", "$TEST_VAR/$ANOTHER_VAR", "test_value/another"},
		{"TildeAndVar", "~/$TEST_VAR", home + "/test_value"},
		{"UnsetVar", "$UNSET_VAR_XYZ", ""},
		{"MidTilde", "/path/~/file", "/path/~/file"}, // ~ only expands at start
		{"EmptyString", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := expandEnv(tt.input)
			if got != tt.expected {
				t.Errorf("expandEnv(%q) = %q, want %q", tt.input, got, tt.expected)
			}
		})
	}
}
