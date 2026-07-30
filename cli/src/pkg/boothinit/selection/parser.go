// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ReadSelectInput resolves a --select value to its raw content with projectRoot ".".
// Prefer ReadSelectInputWithProject when the config target directory is known.
//
// Stdin ("-") should be handled by the caller before calling this function.
func ReadSelectInput(value string) (string, error) {
	return ReadSelectInputWithProject(value, ".")
}

// ReadSelectInputWithProject resolves a --select value to its raw content.
//
//   - "@@…" is always a URL. If the remainder has no scheme, https:// is assumed
//     (e.g. @@codingbooth.io/r.recipe → https://codingbooth.io/r.recipe).
//   - "@…" is a recipe reference:
//     - path-shaped (/…, ./…, ../…, ~/…, C:\…, or containing ://) → read that path/URL
//     - otherwise → <projectRoot>/.booth/recipes/<name>.recipe
//       (.recipe is appended when the name has no extension)
//   - anything else is returned as-is (plain DSL)
//
// projectRoot is the booth project directory (config target), not necessarily cwd.
// Stdin ("-") should be handled by the caller before calling this function.
func ReadSelectInputWithProject(value, projectRoot string) (string, error) {
	if strings.HasPrefix(value, "@@") {
		return fetchURL(normalizeRecipeURL(strings.TrimPrefix(value, "@@")))
	}
	if strings.HasPrefix(value, "@") {
		return readRecipeRef(strings.TrimPrefix(value, "@"), projectRoot)
	}
	return value, nil
}

// NormalizeInput normalizes whitespace in selection input.
// Spaces around "+" and "~" are removed so "java + maven" becomes "java+maven"
// and "firebase ~ credential" becomes "firebase~credential".
// Remaining whitespace (newlines, tabs, multiple spaces) is collapsed
// and treated as "/" separators, so heredoc and file inputs work the
// same as inline DSL.
//
// Whitespace inside a quoted param value is left alone -- a quoted value is one
// value, not two items. See quoting.go.
func NormalizeInput(input string) string {
	fields := fieldsUnquoted(stripSpacesAroundOperators(input))
	// Join "+"- or "~"-prefixed fields to the previous field (continuation lines)
	var merged []string
	for _, f := range fields {
		if (strings.HasPrefix(f, "+") || strings.HasPrefix(f, "~")) && len(merged) > 0 {
			merged[len(merged)-1] += f
		} else {
			merged = append(merged, f)
		}
	}
	return strings.Join(merged, "/")
}

// stripSpacesAroundOperators drops the whitespace that sits next to a "+" or a
// "~" and collapses every other run to a single space, so the caller can split
// on whitespace. Runs inside a quoted value are kept verbatim.
func stripSpacesAroundOperators(input string) string {
	out := make([]byte, 0, len(input))
	quote := byte(0)

	for i := 0; i < len(input); i++ {
		c := input[i]

		if quote != 0 {
			out = append(out, c)
			if c == quote {
				quote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			quote = c
			out = append(out, c)
			continue
		}
		if !isDSLSpace(c) {
			out = append(out, c)
			continue
		}

		// A whitespace run touching an operator on either side belongs to that
		// operator ("java:25,temurin\n  + maven"), so it goes away entirely.
		end := i
		for end < len(input) && isDSLSpace(input[end]) {
			end++
		}
		prevIsOp := len(out) > 0 && isDSLOperator(out[len(out)-1])
		nextIsOp := end < len(input) && isDSLOperator(input[end])
		if !prevIsOp && !nextIsOp {
			out = append(out, ' ')
		}
		i = end - 1
	}

	return string(out)
}

// ParseSelectDSL parses a --select DSL string into a ParsedSelection.
//
// DSL format: name[:p1,p2][+ext1][+ext2][~exc1][~exc2]/name2[:p1,p2][+ext1][~exc1]
//
// Operator precedence: split "/" first, then "~", then "+", then ":" and "," last —
// except that "+" gives way to ":". Once a ":" has opened a param list, a "+" separates
// extensions only when a letter follows it, so a param value can hold one: "expose:+4567"
// is a booth-relative port, not an extension named "4567". See splitExtensions.
//
// No separator at any of those levels separates inside a quoted param value, which is
// how a value that is itself made of separators — a Go module path — is written:
// go+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest". See quoting.go.
func ParseSelectDSL(input string) (*ParsedSelection, error) {
	normalized := NormalizeInput(input)
	parts := splitUnquoted(normalized, '/')

	var items []ParsedItem
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		item, err := parseItem(part)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}

	if len(items) == 0 {
		return nil, fmt.Errorf("empty selection")
	}

	return &ParsedSelection{Items: items}, nil
}

// splitExtensions splits "name[:params][+ext[:params]]..." on the "+" that introduce
// extensions, leaving any "+" that belongs to a param value in place.
//
// A "+" inside a param list is only an extension separator when it introduces an
// extension *name*, and names are always identifiers — they never start with a digit or
// a "+". So once a ":" has opened a param list, a "+" followed by anything but a letter
// is part of the value. That is what lets a port param carry a booth-relative offset
// ("expose:+4567" → host port = booth port + 4567, resolved at start) and, incidentally,
// what lets a package param name a package with a "+" in it ("apt-pkg:libstdc++6").
//
// Before any ":" every "+" still separates, so a malformed "go++linter" or a trailing
// "go+" reports an empty extension name exactly as it did before.
//
// Inside a quoted value that heuristic does not apply at all: a quoted "+" is part of
// the value whatever follows it.
func splitExtensions(basePart string) []string {
	var parts []string
	start, inParams := 0, false
	quote := byte(0)

	for i := 0; i < len(basePart); i++ {
		c := basePart[i]
		if quote != 0 {
			if c == quote {
				quote = 0
			}
			continue
		}
		switch c {
		case '"', '\'':
			quote = c
		case ':':
			inParams = true
		case '+':
			if inParams && !startsExtensionName(basePart[i+1:]) {
				continue // part of the param value, not a separator
			}
			parts = append(parts, basePart[start:i])
			start, inParams = i+1, false
		}
	}
	return append(parts, basePart[start:])
}

// startsExtensionName reports whether s opens with a character an extension name can
// begin with. Template and extension names are identifiers, so that means a letter.
func startsExtensionName(s string) bool {
	if s == "" {
		return false
	}
	c := s[0]
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// parseItem parses a single template selection: "name[:p1,p2][+ext1][+ext2][~exc1][~exc2]"
func parseItem(s string) (ParsedItem, error) {
	// Split by "~" — first part is template[+extensions], rest are exclusions
	tildeParts := splitUnquoted(s, '~')
	basePart := tildeParts[0]

	var excludes []string
	for _, exc := range tildeParts[1:] {
		exc = strings.TrimSpace(exc)
		if exc == "" {
			return ParsedItem{}, fmt.Errorf("empty exclusion name in %q", s)
		}
		excludes = append(excludes, exc)
	}

	// Split base part by "+" — first part is template, rest are extensions
	plusParts := splitExtensions(basePart)
	templatePart := plusParts[0]

	var extensions []ParsedExtension
	for _, ext := range plusParts[1:] {
		ext = strings.TrimSpace(ext)
		if ext == "" {
			return ParsedItem{}, fmt.Errorf("empty extension name in %q", s)
		}
		pe := ParsedExtension{}
		if colonIdx := strings.Index(ext, ":"); colonIdx >= 0 {
			pe.Name = ext[:colonIdx]
			paramStr := ext[colonIdx+1:]
			if paramStr != "" {
				pe.Params = unquoteAll(splitUnquoted(paramStr, ','))
			}
		} else {
			pe.Name = ext
		}
		if pe.Name == "" {
			return ParsedItem{}, fmt.Errorf("empty extension name in %q", s)
		}
		extensions = append(extensions, pe)
	}

	// Split template part by ":" — name and params
	var name string
	var params []string
	if colonIdx := strings.Index(templatePart, ":"); colonIdx >= 0 {
		name = templatePart[:colonIdx]
		paramStr := templatePart[colonIdx+1:]
		if paramStr != "" {
			params = unquoteAll(splitUnquoted(paramStr, ','))
		}
	} else {
		name = templatePart
	}

	if name == "" {
		return ParsedItem{}, fmt.Errorf("empty template name in %q", s)
	}

	return ParsedItem{
		Name:       name,
		Params:     params,
		Extensions: extensions,
		Excludes:   excludes,
	}, nil
}

// fetchURL fetches the content of a URL and returns it as a string.
func fetchURL(url string) (string, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return "", fmt.Errorf("fetching selection URL %q: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("fetching selection URL %q: HTTP %d", url, resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("reading response from %q: %w", url, err)
	}
	return string(data), nil
}
