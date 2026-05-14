// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package shellexpand

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTempFile(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	p := filepath.Join(dir, "test.env")
	if err := os.WriteFile(p, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestParseEnvFile_BasicLines(t *testing.T) {
	body := strings.Join([]string{
		"# top comment",
		"",
		"FOO=bar",
		"export BAZ=qux",
		"WITH_SPACES=hello world",
		"WITH_QUOTES=\"with $VAR\"",
		"LITERAL='$NOT'",
		"",
	}, "\n")

	entries, err := ParseEnvFile(writeTempFile(t, body))
	if err != nil {
		t.Fatalf("unexpected: %v", err)
	}

	want := []EnvEntry{
		{Key: "FOO", Value: "bar", Line: 3},
		{Key: "BAZ", Value: "qux", Line: 4},
		{Key: "WITH_SPACES", Value: "hello world", Line: 5},
		{Key: "WITH_QUOTES", Value: `"with $VAR"`, Line: 6},
		{Key: "LITERAL", Value: `'$NOT'`, Line: 7},
	}
	if len(entries) != len(want) {
		t.Fatalf("entries = %d, want %d (%+v)", len(entries), len(want), entries)
	}
	for i := range want {
		if entries[i] != want[i] {
			t.Errorf("entries[%d] = %+v, want %+v", i, entries[i], want[i])
		}
	}
}

func TestParseEnvFile_CRLF(t *testing.T) {
	body := "FOO=bar\r\nBAZ=qux\r\n"
	entries, err := ParseEnvFile(writeTempFile(t, body))
	if err != nil {
		t.Fatalf("unexpected: %v", err)
	}
	if len(entries) != 2 || entries[0].Value != "bar" || entries[1].Value != "qux" {
		t.Errorf("got %+v", entries)
	}
}

func TestParseEnvFile_TrailingWhitespaceStripped(t *testing.T) {
	body := "FOO=bar   \n"
	entries, err := ParseEnvFile(writeTempFile(t, body))
	if err != nil {
		t.Fatalf("unexpected: %v", err)
	}
	if entries[0].Value != "bar" {
		t.Errorf("want %q, got %q", "bar", entries[0].Value)
	}
}

func TestParseEnvFile_Errors(t *testing.T) {
	cases := []struct {
		name  string
		body  string
		want  string
	}{
		{"BareKey", "FOO\n", "missing '='"},
		{"WhitespaceBeforeEq", "FOO =bar\n", "whitespace before '='"},
		{"WhitespaceAfterEq", "FOO= bar\n", "whitespace after '='"},
		{"BadKeyDigit", "1FOO=bar\n", "invalid key"},
		{"BadKeyDash", "FOO-BAR=baz\n", "invalid key"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ParseEnvFile(writeTempFile(t, tc.body))
			if err == nil {
				t.Fatal("expected error, got nil")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("error %q does not contain %q", err.Error(), tc.want)
			}
		})
	}
}

func TestExpandEntries_ScopeAndPassthrough(t *testing.T) {
	// Bash-like scope: VAR1=$VAR1 reads host env; FOO=$VAR1 reads earlier definition.
	env := map[string]string{"VAR1": "fromhost", "HOME": "/h"}
	entries := []EnvEntry{
		{Key: "VAR1", Value: "$VAR1", Line: 1},
		{Key: "FOO", Value: "$VAR1/x", Line: 2},
		{Key: "DEFAULT", Value: "${MISSING:-fallback}", Line: 3},
		{Key: "TILDE", Value: "~/data", Line: 4},
	}
	got, err := ExpandEntries(entries, mapLookup(env), ".booth/.env")
	if err != nil {
		t.Fatalf("unexpected: %v", err)
	}
	want := map[string]string{
		"VAR1":    "fromhost",
		"FOO":     "fromhost/x",
		"DEFAULT": "fallback",
		"TILDE":   "/h/data",
	}
	for _, e := range got {
		if want[e.Key] != e.Value {
			t.Errorf("%s = %q, want %q", e.Key, e.Value, want[e.Key])
		}
	}
}

func TestExpandEntries_RequiredVarSourceLocation(t *testing.T) {
	entries := []EnvEntry{
		{Key: "DB_URL", Value: "${DATABASE_URL:?required for app boot}", Line: 12},
	}
	_, err := ExpandEntries(entries, mapLookup(map[string]string{}), ".booth/.env")
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	want := ".booth/.env:12: required for app boot"
	if err.Error() != want {
		t.Errorf("got %q, want %q", err.Error(), want)
	}
}

func TestFormatEnvFile_RoundTrip(t *testing.T) {
	entries := []EnvEntry{
		{Key: "FOO", Value: "bar"},
		{Key: "BAZ", Value: "qux quux"},
	}
	out := FormatEnvFile(entries)
	want := "FOO=bar\nBAZ=qux quux\n"
	if out != want {
		t.Errorf("got %q, want %q", out, want)
	}
}
