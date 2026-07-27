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
func NormalizeInput(input string) string {
	// Remove spaces around "+" so extensions stay attached to their template
	for strings.Contains(input, " +") || strings.Contains(input, "+ ") {
		input = strings.ReplaceAll(input, " +", "+")
		input = strings.ReplaceAll(input, "+ ", "+")
	}
	// Remove spaces around "~" so exclusions stay attached to their template
	for strings.Contains(input, " ~") || strings.Contains(input, "~ ") {
		input = strings.ReplaceAll(input, " ~", "~")
		input = strings.ReplaceAll(input, "~ ", "~")
	}
	fields := strings.Fields(input)
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

// ParseSelectDSL parses a --select DSL string into a ParsedSelection.
//
// DSL format: name[:p1,p2][+ext1][+ext2][~exc1][~exc2]/name2[:p1,p2][+ext1][~exc1]
//
// Operator precedence: split "/" first, then "~", then "+", then ":" and "," last —
// except that "+" gives way to ":". Once a ":" has opened a param list, a "+" separates
// extensions only when a letter follows it, so a param value can hold one: "expose:+4567"
// is a booth-relative port, not an extension named "4567". See splitExtensions.
func ParseSelectDSL(input string) (*ParsedSelection, error) {
	normalized := NormalizeInput(input)
	parts := strings.Split(normalized, "/")

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
func splitExtensions(basePart string) []string {
	var parts []string
	start, inParams := 0, false

	for i := 0; i < len(basePart); i++ {
		switch basePart[i] {
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
	tildeParts := strings.Split(s, "~")
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
				pe.Params = strings.Split(paramStr, ",")
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
			params = strings.Split(paramStr, ",")
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
