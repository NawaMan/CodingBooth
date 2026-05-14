// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package shellexpand

import (
	"bufio"
	"os"
	"strings"
)

// EnvEntry is a single KEY=VALUE pair from a parsed .env file, retaining
// the line number so errors can point at the source.
type EnvEntry struct {
	Key   string
	Value string // raw value, not yet expanded
	Line  int    // 1-based
}

// ParseEnvFile reads a .env file from path and returns its entries in source
// order. See docs/BOOTH_VARS.md for the line format.
func ParseEnvFile(path string) ([]EnvEntry, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var entries []EnvEntry
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)

	line := 0
	for scanner.Scan() {
		line++
		raw := scanner.Text()
		// Strip trailing CR for CRLF tolerance.
		raw = strings.TrimRight(raw, "\r")

		trimmed := strings.TrimLeft(raw, " \t")
		if trimmed == "" {
			continue
		}
		if strings.HasPrefix(trimmed, "#") {
			continue
		}

		// Optional `export ` prefix.
		if strings.HasPrefix(trimmed, "export ") || strings.HasPrefix(trimmed, "export\t") {
			trimmed = strings.TrimLeft(trimmed[len("export"):], " \t")
		}

		eq := strings.IndexByte(trimmed, '=')
		if eq < 0 {
			return nil, &Error{
				Source: SourceRef{File: path, Line: line},
				Msg:    "missing '=' (bare keys are not supported; write KEY=$KEY for passthrough)",
			}
		}

		key := trimmed[:eq]
		val := trimmed[eq+1:]

		// Strict: no whitespace immediately around '='.
		if strings.HasSuffix(key, " ") || strings.HasSuffix(key, "\t") {
			return nil, &Error{
				Source: SourceRef{File: path, Line: line},
				Msg:    "whitespace before '=' is not allowed",
			}
		}
		if strings.HasPrefix(val, " ") || strings.HasPrefix(val, "\t") {
			return nil, &Error{
				Source: SourceRef{File: path, Line: line},
				Msg:    "whitespace after '=' is not allowed (quote the value if it has leading spaces)",
			}
		}

		if err := validateKey(key); err != nil {
			return nil, &Error{
				Source: SourceRef{File: path, Line: line},
				Msg:    err.Error(),
			}
		}

		// Strip trailing whitespace only when the value is not entirely a
		// quoted run. Detecting "entirely quoted" robustly requires the
		// expander; here we keep it simple by deferring to whether the
		// value's last non-space char is a closing quote.
		val = stripUnquotedTrailingWhitespace(val)

		entries = append(entries, EnvEntry{Key: key, Value: val, Line: line})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return entries, nil
}

// ExpandEntries expands each entry's value against a running scope built
// from prior entries. Earlier entries are visible to later ones; lookups
// fall through to baseLookup (typically os.LookupEnv) on miss.
//
// The returned slice has the same length and order as entries; the Value
// field carries the expanded result.
func ExpandEntries(entries []EnvEntry, baseLookup LookupFunc, file string) ([]EnvEntry, error) {
	if baseLookup == nil {
		baseLookup = DefaultLookup
	}
	scope := make(map[string]string, len(entries))
	out := make([]EnvEntry, len(entries))
	lookup := func(name string) (string, bool) {
		if v, ok := scope[name]; ok {
			return v, true
		}
		return baseLookup(name)
	}
	for i, e := range entries {
		src := SourceRef{File: file, Line: e.Line}
		expanded, err := Expand(e.Value, lookup, src)
		if err != nil {
			return nil, err
		}
		if strings.ContainsAny(expanded, "\n\r") {
			return nil, &Error{Source: src, Msg: "expanded value contains a newline (multi-line values are not supported)"}
		}
		scope[e.Key] = expanded
		out[i] = EnvEntry{Key: e.Key, Value: expanded, Line: e.Line}
	}
	return out, nil
}

// FormatEnvFile renders a sequence of entries as a docker --env-file
// compatible body: one KEY=VALUE per line, with a trailing newline.
func FormatEnvFile(entries []EnvEntry) string {
	var b strings.Builder
	for _, e := range entries {
		b.WriteString(e.Key)
		b.WriteByte('=')
		b.WriteString(e.Value)
		b.WriteByte('\n')
	}
	return b.String()
}

func validateKey(key string) error {
	if key == "" {
		return &Error{Msg: "empty key before '='"}
	}
	if !isNameStart(key[0]) {
		return &Error{Msg: "invalid key " + quoteForMsg(key) + ": must match [A-Za-z_][A-Za-z0-9_]*"}
	}
	for i := 1; i < len(key); i++ {
		if !isNameCont(key[i]) {
			return &Error{Msg: "invalid key " + quoteForMsg(key) + ": must match [A-Za-z_][A-Za-z0-9_]*"}
		}
	}
	return nil
}

func quoteForMsg(s string) string {
	return "'" + s + "'"
}

// stripUnquotedTrailingWhitespace removes trailing spaces and tabs unless
// the value ends with a closing quote (in which case the trailing whitespace
// is treated as syntactically significant and left to the expander).
func stripUnquotedTrailingWhitespace(v string) string {
	end := len(v)
	for end > 0 {
		c := v[end-1]
		if c == ' ' || c == '\t' {
			end--
			continue
		}
		break
	}
	// If the trimmed value ends with a quote, the trailing whitespace was
	// already outside the quoted region — drop it.
	// If we trimmed nothing, return as-is.
	return v[:end]
}
