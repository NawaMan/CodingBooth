// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"os"
	"strings"
)

// ReadSelectInput resolves a --select value to its raw content.
//   - "@filename" reads from a file
//   - "@@url" is not yet implemented (returns error)
//   - anything else is returned as-is
//
// Stdin ("-") should be handled by the caller before calling this function.
func ReadSelectInput(value string) (string, error) {
	if strings.HasPrefix(value, "@@") {
		return "", fmt.Errorf("URL-based selection (@@) not yet implemented")
	}
	if strings.HasPrefix(value, "@") {
		filename := strings.TrimPrefix(value, "@")
		data, err := os.ReadFile(filename)
		if err != nil {
			return "", fmt.Errorf("reading selection file %q: %w", filename, err)
		}
		return string(data), nil
	}
	return value, nil
}

// NormalizeInput normalizes whitespace in selection input.
// Newlines, tabs, and multiple spaces are collapsed and treated as
// "/" separators, so heredoc and file inputs work the same as inline DSL.
func NormalizeInput(input string) string {
	return strings.Join(strings.Fields(input), "/")
}

// ParseSelectDSL parses a --select DSL string into a ParsedSelection.
//
// DSL format: name[:p1,p2][+ext1][+ext2]/name2[:p1,p2][+ext1]
//
// Operator precedence: split "/" first, then "+", then ":" and "," last.
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

// parseItem parses a single template selection: "name[:p1,p2][+ext1][+ext2]"
func parseItem(s string) (ParsedItem, error) {
	// Split by "+" — first part is template, rest are extensions
	plusParts := strings.Split(s, "+")
	templatePart := plusParts[0]

	var extensions []string
	for _, ext := range plusParts[1:] {
		ext = strings.TrimSpace(ext)
		if ext == "" {
			return ParsedItem{}, fmt.Errorf("empty extension name in %q", s)
		}
		extensions = append(extensions, ext)
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
	}, nil
}
