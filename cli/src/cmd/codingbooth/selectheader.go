// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import "strings"

// The "# Configured by: booth config …" header is two things at once: the record
// booth reads back to reconfigure a booth (readExistingBooth), and a command a
// user can paste into a shell. A select DSL may now carry quotes — a param value
// with a "/" in it needs them, see selection/quoting.go — and a bare '"' would be
// eaten by the shell on the way back in, leaving the DSL unquoted and broken.
//
// So the DSL is wrapped in single quotes on the way out, and one enclosing pair of
// single quotes is stripped on the way in. Both halves are deliberately narrow:
// only a value that actually needs it is quoted, so the header of every booth that
// has no such value is byte-for-byte what it was before.

// selectArg renders the "--select <dsl>" fragment of a generated header, quoted
// for a shell when the DSL holds a character a shell would otherwise consume.
func selectArg(dsl string) string {
	return "--select " + shellQuoteDSL(dsl)
}

// shellQuoteDSL wraps a select DSL in single quotes when it contains a quote
// character or whitespace, and returns it untouched otherwise.
//
// A DSL holding a "'" is returned as-is: single-quoting it would need the '\''
// dance, which the reader would then have to undo, and nothing emits one —
// QuoteParam reaches for "'" only for a value that already contains a '"', and no
// package spec contains either. A hand-written one still parses; it just is not
// re-quoted for the shell.
func shellQuoteDSL(dsl string) string {
	if dsl == "" || strings.Contains(dsl, "'") {
		return dsl
	}
	if !strings.ContainsAny(dsl, "\" \t") {
		return dsl
	}
	return "'" + dsl + "'"
}

// headerFields splits a recorded header command into arguments: whitespace
// separates, except inside a quoted run, and one enclosing pair of single quotes
// is then removed from each argument.
//
// Only the outer layer goes. The quotes the DSL itself uses are part of the value
// and must survive to reach ParseSelectDSL, which is also why a hand-written
// `--select go+go-pkg:"github.com/x@latest"` — no outer quotes at all — reads back
// unharmed.
func headerFields(cmd string) []string {
	var fields []string
	var cur []byte
	quote := byte(0)

	flush := func() {
		if len(cur) > 0 {
			fields = append(fields, unwrapSingleQuotes(string(cur)))
			cur = nil
		}
	}

	for i := 0; i < len(cmd); i++ {
		c := cmd[i]
		switch {
		case quote != 0:
			cur = append(cur, c)
			if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
			cur = append(cur, c)
		case c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f':
			flush()
		default:
			cur = append(cur, c)
		}
	}
	flush()

	return fields
}

// unwrapSingleQuotes strips one enclosing pair of single quotes.
func unwrapSingleQuotes(s string) string {
	if len(s) >= 2 && s[0] == '\'' && s[len(s)-1] == '\'' {
		return s[1 : len(s)-1]
	}
	return s
}
