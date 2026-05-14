// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package shellexpand provides bash-like variable expansion for booth
// configuration values. The supported subset is documented in
// docs/BOOTH_VARS.md.
package shellexpand

import (
	"fmt"
	"os"
	"strings"
)

// MaxDepth caps recursion through nested defaults (${A:-${B:-...}}).
const MaxDepth = 32

// LookupFunc resolves variable names to values. Mirrors os.LookupEnv: the
// second return is false when the name is unset.
type LookupFunc func(name string) (string, bool)

// DefaultLookup looks variables up in the process environment.
func DefaultLookup(name string) (string, bool) {
	return os.LookupEnv(name)
}

// SourceRef tags an expansion call with where the input came from so that
// errors can point the user at the offending line or field.
type SourceRef struct {
	File  string // optional, e.g. ".booth/.env"
	Line  int    // optional, 1-based; 0 if not applicable
	Field string // optional, e.g. `run-args[3]`, `image`
}

// Prefix renders the SourceRef as a human-readable error prefix.
func (s SourceRef) Prefix() string {
	parts := make([]string, 0, 2)
	switch {
	case s.File != "" && s.Line > 0:
		parts = append(parts, fmt.Sprintf("%s:%d", s.File, s.Line))
	case s.File != "":
		parts = append(parts, s.File)
	}
	if s.Field != "" {
		parts = append(parts, s.Field)
	}
	return strings.Join(parts, ": ")
}

// Error wraps an expansion failure with its SourceRef.
type Error struct {
	Source SourceRef
	Msg    string
}

func (e *Error) Error() string {
	prefix := e.Source.Prefix()
	if prefix == "" {
		return e.Msg
	}
	return prefix + ": " + e.Msg
}

// Expand applies the booth expansion rules to input and returns the result.
// See docs/BOOTH_VARS.md for the exact rule set.
func Expand(input string, lookup LookupFunc, src SourceRef) (string, error) {
	if lookup == nil {
		lookup = DefaultLookup
	}
	return expandWithDepth(input, lookup, src, 0)
}

func expandWithDepth(input string, lookup LookupFunc, src SourceRef, depth int) (string, error) {
	if depth > MaxDepth {
		return "", &Error{Source: src, Msg: "expansion nested too deeply (> " + itoa(MaxDepth) + ")"}
	}

	var out strings.Builder
	out.Grow(len(input))

	i := 0
	atStart := true       // true while no content has been emitted
	openedAtStart := false // true once we entered a "..." block while atStart was true
	inDQ := false
	inSQ := false

	for i < len(input) {
		c := input[i]

		// Single-quoted region: everything literal until the closing '.
		if inSQ {
			if c == '\'' {
				inSQ = false
				i++
				atStart = false
				continue
			}
			out.WriteByte(c)
			i++
			atStart = false
			continue
		}

		// Double-quoted region: $-expansion, escapes, but no '~' unless we
		// entered the region while at the start of the value.
		if inDQ {
			switch c {
			case '"':
				inDQ = false
				i++
				atStart = false
				openedAtStart = false
				continue
			case '\\':
				if i+1 >= len(input) {
					return "", &Error{Source: src, Msg: "trailing backslash"}
				}
				next := input[i+1]
				if next == '$' || next == '"' || next == '\\' || next == '~' {
					out.WriteByte(next)
					i += 2
				} else {
					out.WriteByte('\\')
					i++
				}
				atStart = false
				continue
			case '$':
				if err := expandDollar(input, &i, &out, lookup, src, depth); err != nil {
					return "", err
				}
				atStart = false
				continue
			case '~':
				if openedAtStart && atStart {
					home, _ := lookup("HOME")
					out.WriteString(home)
					i++
					atStart = false
					continue
				}
				out.WriteByte(c)
				i++
				atStart = false
				continue
			default:
				out.WriteByte(c)
				i++
				atStart = false
				continue
			}
		}

		// Unquoted region.
		switch c {
		case '"':
			inDQ = true
			i++
			if atStart {
				openedAtStart = true
			}
			continue
		case '\'':
			inSQ = true
			i++
			// atStart stays true only if it was already true and the
			// upcoming ' content begins immediately — but since '...' never
			// allows ~ expansion anyway, we can just leave atStart as-is.
			// Once we exit the sq region we'll see content was emitted (if
			// any), so atStart will be cleared then.
			continue
		case '\\':
			if i+1 >= len(input) {
				return "", &Error{Source: src, Msg: "trailing backslash"}
			}
			next := input[i+1]
			if next == '$' || next == '"' || next == '\\' || next == '~' || next == '\'' {
				out.WriteByte(next)
				i += 2
			} else {
				out.WriteByte('\\')
				i++
			}
			atStart = false
			continue
		case '$':
			if err := expandDollar(input, &i, &out, lookup, src, depth); err != nil {
				return "", err
			}
			atStart = false
			continue
		case '~':
			if atStart {
				home, _ := lookup("HOME")
				out.WriteString(home)
				i++
				atStart = false
				continue
			}
			out.WriteByte(c)
			i++
			atStart = false
			continue
		default:
			out.WriteByte(c)
			i++
			atStart = false
			continue
		}
	}

	if inDQ {
		return "", &Error{Source: src, Msg: "unterminated double-quote"}
	}
	if inSQ {
		return "", &Error{Source: src, Msg: "unterminated single-quote"}
	}

	return out.String(), nil
}

// expandDollar handles either ${...} or $NAME starting at input[*i] == '$'.
// On success it advances *i past the consumed text and writes to out.
func expandDollar(input string, i *int, out *strings.Builder, lookup LookupFunc, src SourceRef, depth int) error {
	// Skip the '$'.
	pos := *i + 1
	if pos >= len(input) {
		// Trailing $ — literal.
		out.WriteByte('$')
		*i = pos
		return nil
	}

	if input[pos] == '{' {
		// ${...} form
		body, end, err := readBraceBody(input, pos+1, src)
		if err != nil {
			return err
		}
		if err := expandBraced(body, out, lookup, src, depth); err != nil {
			return err
		}
		*i = end
		return nil
	}

	// $NAME form: greedy [A-Za-z_][A-Za-z0-9_]*
	if !isNameStart(input[pos]) {
		// $ not followed by a name char — emit literal $.
		out.WriteByte('$')
		*i = pos
		return nil
	}
	nameStart := pos
	pos++
	for pos < len(input) && isNameCont(input[pos]) {
		pos++
	}
	name := input[nameStart:pos]
	if val, ok := lookup(name); ok {
		out.WriteString(val)
	}
	*i = pos
	return nil
}

// readBraceBody reads characters starting just after the opening '{' until
// the matching '}', honoring nested ${...}, single- and double-quoted
// regions, and backslash escapes. Returns the body (excluding the braces)
// and the index just past the closing '}'.
func readBraceBody(input string, start int, src SourceRef) (string, int, error) {
	depth := 1
	pos := start
	inDQ := false
	inSQ := false

	for pos < len(input) {
		c := input[pos]
		switch {
		case inSQ:
			if c == '\'' {
				inSQ = false
			}
			pos++
			continue
		case inDQ:
			if c == '\\' && pos+1 < len(input) {
				pos += 2
				continue
			}
			if c == '"' {
				inDQ = false
			}
			pos++
			continue
		}

		switch c {
		case '\\':
			if pos+1 < len(input) {
				pos += 2
				continue
			}
			pos++
		case '\'':
			inSQ = true
			pos++
		case '"':
			inDQ = true
			pos++
		case '$':
			if pos+1 < len(input) && input[pos+1] == '{' {
				depth++
				pos += 2
				continue
			}
			pos++
		case '{':
			pos++
		case '}':
			depth--
			if depth == 0 {
				return input[start:pos], pos + 1, nil
			}
			pos++
		default:
			pos++
		}
	}

	return "", 0, &Error{Source: src, Msg: "unterminated ${...}"}
}

// expandBraced expands the body of a ${...} construct (the substring
// between the braces) and writes the result to out.
func expandBraced(body string, out *strings.Builder, lookup LookupFunc, src SourceRef, depth int) error {
	if body == "" {
		return &Error{Source: src, Msg: "empty ${} reference"}
	}
	if !isNameStart(body[0]) {
		return &Error{Source: src, Msg: "invalid variable name in ${" + body + "}"}
	}

	nameEnd := 1
	for nameEnd < len(body) && isNameCont(body[nameEnd]) {
		nameEnd++
	}
	name := body[:nameEnd]
	rest := body[nameEnd:]

	val, set := lookup(name)

	switch {
	case rest == "":
		if set {
			out.WriteString(val)
		}
		return nil
	case strings.HasPrefix(rest, ":-"):
		if !set || val == "" {
			expanded, err := expandWithDepth(rest[2:], lookup, src, depth+1)
			if err != nil {
				return err
			}
			out.WriteString(expanded)
			return nil
		}
		out.WriteString(val)
		return nil
	case strings.HasPrefix(rest, ":?"):
		if !set || val == "" {
			raw := rest[2:]
			var msg string
			if raw == "" {
				msg = "required variable " + name + " is not set"
			} else {
				expanded, err := expandWithDepth(raw, lookup, src, depth+1)
				if err != nil {
					return err
				}
				msg = expanded
			}
			return &Error{Source: src, Msg: msg}
		}
		out.WriteString(val)
		return nil
	}

	// Anything else — :=, :+, #, %, /, ^, , — is unsupported.
	return &Error{Source: src, Msg: "unsupported operator in ${" + body + "} (only :- and :? are supported)"}
}

func isNameStart(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func isNameCont(c byte) bool {
	return isNameStart(c) || (c >= '0' && c <= '9')
}

// itoa is a tiny int-to-string used in fixed error messages so we don't pull
// strconv in for a single call site.
func itoa(n int) string {
	return fmt.Sprintf("%d", n)
}
