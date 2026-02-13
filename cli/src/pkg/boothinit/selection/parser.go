// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// ReadSelectInput resolves a --select value to its raw content.
//   - "@filename" reads from a file
//   - "@@url" fetches from a URL
//   - anything else is returned as-is
//
// Stdin ("-") should be handled by the caller before calling this function.
func ReadSelectInput(value string) (string, error) {
	if strings.HasPrefix(value, "@@") {
		url := strings.TrimPrefix(value, "@@")
		return fetchURL(url)
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
// Operator precedence: split "/" first, then "~", then "+", then ":" and "," last.
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
	plusParts := strings.Split(basePart, "+")
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
