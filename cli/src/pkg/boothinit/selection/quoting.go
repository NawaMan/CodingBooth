// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import "strings"

// Quoting in the selection DSL.
//
// Every separator the DSL uses -- "/" between templates, "+" and "~" for
// extensions, "," between params -- is also a character package names are made
// of, and a Go module path is nothing but slashes. Unquoted, the documented
//
//	--select go+go-pkg:github.com/pocketbase/pocketbase/examples/base@latest
//
// parses as one template per path segment: go+go-pkg:github.com, then
// "pocketbase", "pocketbase", "examples", "base@latest". Nothing in the text
// tells those apart from "go:1.25.7/claude-code", where the "/" really does
// start a second template, so the DSL needs a way to say "this slash is part of
// the value".
//
// A param value may therefore be wrapped in quotes -- '"' or "'", whichever is
// easier to get past the shell -- and inside them no character separates
// anything:
//
//	go+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest"
//	nodejs+npm-pkg:"@types/node","@types/react"
//
// Quotes are stripped once, at the leaves, so a value never carries them into
// the generated Boothfile. Nothing else in the DSL is quotable: template and
// extension names are identifiers, and the shape of a selection is not
// something a quote should be able to change.

// dslQuoteTriggers are the characters that make a param value unreadable
// unquoted.
//
// "+" is deliberately absent. A "+" inside a param list already stays with the
// value unless a letter follows it (see splitExtensions), which is what lets
// "expose:+9000" and "apt-pkg:libstdc++6" be written plainly -- and quoting
// them now would rewrite the header of every booth that has one for no gain.
// ":" is absent for the same reason: only the first ":" of an item separates,
// so "deno-pkg:jsr:@luca/flag" already keeps its second one.
const dslQuoteTriggers = "/,~\"' \t\n\r\v\f"

// QuoteParam wraps v in quotes when its text would otherwise read as DSL
// punctuation, and returns it untouched when it would not. The quote character
// is the one v does not already contain, so the result needs no escaping.
//
// A value holding both quote characters is returned as-is: the DSL has no
// escape sequence, and no package spec needs one. It fails loudly at parse
// rather than silently selecting the wrong templates.
func QuoteParam(v string) string {
	if v == "" || !strings.ContainsAny(v, dslQuoteTriggers) {
		return v
	}
	switch {
	case !strings.Contains(v, `"`):
		return `"` + v + `"`
	case !strings.Contains(v, "'"):
		return "'" + v + "'"
	default:
		return v
	}
}

// QuoteVariadic quotes each element of a comma-joined variadic value, leaving
// the commas between them as separators. Blank elements are dropped, matching
// how the resolver canonicalizes such a list.
func QuoteVariadic(v string) string {
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		out = append(out, QuoteParam(p))
	}
	return strings.Join(out, ",")
}

// Unquote strips one enclosing pair of matching quotes from a param value.
func Unquote(s string) string {
	if len(s) >= 2 {
		q := s[0]
		if (q == '"' || q == '\'') && s[len(s)-1] == q {
			return s[1 : len(s)-1]
		}
	}
	return s
}

// splitUnquoted splits s on every sep that falls outside a quoted run.
func splitUnquoted(s string, sep byte) []string {
	var parts []string
	start, quote := 0, byte(0)
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case quote != 0:
			if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == sep:
			parts = append(parts, s[start:i])
			start = i + 1
		}
	}
	return append(parts, s[start:])
}

// fieldsUnquoted is strings.Fields for a string that may hold quoted runs:
// whitespace inside quotes keeps a value together instead of splitting it.
func fieldsUnquoted(s string) []string {
	var fields []string
	var cur []byte
	quote := byte(0)
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case quote != 0:
			cur = append(cur, c)
			if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
			cur = append(cur, c)
		case isDSLSpace(c):
			if len(cur) > 0 {
				fields = append(fields, string(cur))
				cur = nil
			}
		default:
			cur = append(cur, c)
		}
	}
	if len(cur) > 0 {
		fields = append(fields, string(cur))
	}
	return fields
}

// unquoteAll trims and unquotes a list of param values in place.
func unquoteAll(values []string) []string {
	for i, v := range values {
		values[i] = Unquote(strings.TrimSpace(v))
	}
	return values
}

// isDSLSpace reports whether c is whitespace the DSL treats as a separator.
// Byte-wise is safe: every byte of a multi-byte rune is >= 0x80.
func isDSLSpace(c byte) bool {
	switch c {
	case ' ', '\t', '\n', '\r', '\v', '\f':
		return true
	}
	return false
}

// isDSLOperator reports whether c is an operator that swallows the whitespace
// around it, so "java + maven" reads as "java+maven".
func isDSLOperator(c byte) bool {
	return c == '+' || c == '~'
}
