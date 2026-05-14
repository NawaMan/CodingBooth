// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package shellexpand

import (
	"strings"
	"testing"
)

func mapLookup(m map[string]string) LookupFunc {
	return func(name string) (string, bool) {
		v, ok := m[name]
		return v, ok
	}
}

func TestExpand_Basic(t *testing.T) {
	env := map[string]string{
		"HOME":  "/home/nawa",
		"USER":  "nawa",
		"EMPTY": "",
		"FOO":   "bar",
		"PATH":  "/usr/bin:/bin",
	}
	cases := []struct {
		name string
		in   string
		out  string
	}{
		{"plain", "hello", "hello"},
		{"empty", "", ""},
		{"DollarVar", "$FOO", "bar"},
		{"DollarVarPath", "$FOO/baz", "bar/baz"},
		{"BraceVar", "${FOO}", "bar"},
		{"BraceVarCat", "x${FOO}y", "xbary"},
		{"UnsetVarEmpty", "$UNSET_XYZ/x", "/x"},
		{"TildeOnly", "~", "/home/nawa"},
		{"TildeSlash", "~/.config", "/home/nawa/.config"},
		{"TildeMidLiteral", "/path/~/file", "/path/~/file"},
		{"DQTilde", `"~/x"`, "/home/nawa/x"},
		{"SQTildeLiteral", `'~/x'`, "~/x"},
		{"DQVar", `"hi $USER"`, "hi nawa"},
		{"SQVar", `'$USER'`, "$USER"},
		{"MidDQ", `prefix"$USER"suffix`, "prefixnawasuffix"},
		{"EscapeDollar", `\$FOO`, "$FOO"},
		{"EscapeBackslash", `a\\b`, `a\b`},
		{"EscapeTilde", `\~`, "~"},
		{"DQEscapeDollar", `"\$x"`, "$x"},
		{"DefaultUsedWhenUnset", `${MISSING:-fallback}`, "fallback"},
		{"DefaultUsedWhenEmpty", `${EMPTY:-fallback}`, "fallback"},
		{"DefaultIgnoredWhenSet", `${FOO:-fallback}`, "bar"},
		{"DefaultIsExpanded", `${MISSING:-$FOO/x}`, "bar/x"},
		{"NestedDefaults", `${MISSING:-${FOO:-zzz}}`, "bar"},
		{"NestedDefaultsChain", `${MISSING_A:-${MISSING_B:-z}}`, "z"},
		{"TrailingDollarLiteral", "abc$", "abc$"},
		{"DollarThenNonName", "$ ", "$ "},
		{"MultipleVars", "$FOO/$USER", "bar/nawa"},
		{"BraceWithUnsetEmpty", "${MISSING}", ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Expand(tc.in, mapLookup(env), SourceRef{})
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.out {
				t.Errorf("Expand(%q) = %q, want %q", tc.in, got, tc.out)
			}
		})
	}
}

func TestExpand_RequiredVar(t *testing.T) {
	env := map[string]string{"SET": "x", "EMPTY": ""}
	src := SourceRef{File: ".booth/.env", Line: 12}

	cases := []struct {
		name    string
		in      string
		wantErr string
	}{
		{"UnsetEmptyMsg", "${MISSING:?}", ".booth/.env:12: required variable MISSING is not set"},
		{"UnsetWithMsg", "${MISSING:?required for app boot}", ".booth/.env:12: required for app boot"},
		{"EmptyTriggers", "${EMPTY:?must be set}", ".booth/.env:12: must be set"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Expand(tc.in, mapLookup(env), src)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
			if err.Error() != tc.wantErr {
				t.Errorf("got %q, want %q", err.Error(), tc.wantErr)
			}
		})
	}

	// :? must NOT fire when value is set and non-empty.
	got, err := Expand("${SET:?should not fire}", mapLookup(env), src)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "x" {
		t.Errorf("got %q, want %q", got, "x")
	}
}

func TestExpand_Errors(t *testing.T) {
	env := map[string]string{"FOO": "bar"}
	src := SourceRef{Field: "run-args[3]"}

	cases := []struct {
		name    string
		in      string
		wantSub string
	}{
		{"UnterminatedDQ", `"hi`, "unterminated double-quote"},
		{"UnterminatedSQ", `'hi`, "unterminated single-quote"},
		{"UnterminatedBrace", "${FOO", "unterminated ${...}"},
		{"EmptyBraces", "${}", "empty ${} reference"},
		{"BadOperatorAssign", "${X:=y}", "unsupported operator"},
		{"BadOperatorAlt", "${X:+y}", "unsupported operator"},
		{"BadOperatorNoColon", "${X-y}", "unsupported operator"},
		{"BadOperatorRandom", "${X#y}", "unsupported operator"},
		{"InvalidNameDigit", "${1FOO}", "invalid variable name"},
		{"TrailingBackslash", `a\`, "trailing backslash"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Expand(tc.in, mapLookup(env), src)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
			if !strings.Contains(err.Error(), tc.wantSub) {
				t.Errorf("error %q does not contain %q", err.Error(), tc.wantSub)
			}
			if !strings.Contains(err.Error(), "run-args[3]") {
				t.Errorf("error %q does not include source prefix", err.Error())
			}
		})
	}
}

func TestExpand_RecursionLimit(t *testing.T) {
	// Build a deeply nested default that overshoots MaxDepth.
	in := strings.Repeat("${X:-", MaxDepth+2) + "z" + strings.Repeat("}", MaxDepth+2)
	_, err := Expand(in, mapLookup(map[string]string{}), SourceRef{})
	if err == nil {
		t.Fatal("expected recursion error, got nil")
	}
	if !strings.Contains(err.Error(), "too deeply") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestExpand_SQNoEscape(t *testing.T) {
	got, err := Expand(`'\n\t$FOO'`, mapLookup(map[string]string{"FOO": "bar"}), SourceRef{})
	if err != nil {
		t.Fatalf("unexpected: %v", err)
	}
	if got != `\n\t$FOO` {
		t.Errorf("got %q, want %q", got, `\n\t$FOO`)
	}
}

func TestExpand_DQLiteralNewlineMarker(t *testing.T) {
	// "\n" inside DQ stays literal (we don't interpret escape sequences).
	got, err := Expand(`"\n"`, mapLookup(map[string]string{}), SourceRef{})
	if err != nil {
		t.Fatalf("unexpected: %v", err)
	}
	if got != `\n` {
		t.Errorf("got %q, want %q", got, `\n`)
	}
}

func TestSourceRef_Prefix(t *testing.T) {
	cases := []struct {
		ref  SourceRef
		want string
	}{
		{SourceRef{}, ""},
		{SourceRef{File: ".booth/.env"}, ".booth/.env"},
		{SourceRef{File: ".booth/.env", Line: 7}, ".booth/.env:7"},
		{SourceRef{Field: "image"}, "image"},
		{SourceRef{File: "config.toml", Field: "run-args[2]"}, "config.toml: run-args[2]"},
	}
	for _, tc := range cases {
		got := tc.ref.Prefix()
		if got != tc.want {
			t.Errorf("Prefix(%+v) = %q, want %q", tc.ref, got, tc.want)
		}
	}
}
