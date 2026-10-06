// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Setup-header templates
//
// A project's own setup script can make itself selectable in `booth config`
// without a template.toml: a `# cb-template:` line in its leading comment block
// turns .booth/setups/<name>--setup.sh into a template named <name>, whose only
// content is one `setup <name> ${PARAM}...` line.
//
//	#!/bin/bash
//	# cb-template: DB seed                         (required: marker + display name)
//	# cb-disc:     Load fixture data into Postgres
//	# cb-detail:   Longer text for the detail pane
//	# cb-band:     90                              (Boothfile order; default 50)
//	# cb-requires: postgresql
//	# cb-tags:     db, fixtures
//	# cb-param:    SEED_SET default=small suggests=small,full
//
// Params are passed to the script positionally, in the order of their lines.
// Anything more (run-args, extensions, startup segments, files) needs a real
// template.toml, which wins over a header of the same name.
//
// This is for project-local setups only. End users never have the stock
// scripts, only the binary and templates.zip, so the catalog keeps template.toml.

const (
	// ProjectCategoryName is the category setup-header templates land in — the
	// same one the examples use for their .booth/templates/project/ templates.
	ProjectCategoryName = "project"
	// ProjectCategoryDisplayName and ProjectCategoryOrder apply when the project
	// has no project/meta.toml of its own.
	ProjectCategoryDisplayName = "This project"
	ProjectCategoryOrder       = 0

	setupScriptSuffix = "--setup.sh"
	defaultSetupBand  = 50
)

var (
	headerKeyLine = regexp.MustCompile(`^#\s*cb-([a-z][a-z-]*):\s*(.*?)\s*$`)
	paramNameRe   = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
)

// ProjectSetupsDir returns <projectRoot>/.booth/setups.
func ProjectSetupsDir(projectRoot string) string {
	if projectRoot == "" {
		projectRoot = "."
	}
	return filepath.Join(projectRoot, ".booth", "setups")
}

// LoadSetupHeaderTemplates returns a template for every *--setup.sh in dir whose
// leading comment block has a `# cb-template:` line. Scripts without one are
// ignored. A missing dir yields no templates and no error.
func LoadSetupHeaderTemplates(dir string) ([]*Template, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("reading setups directory: %w", err)
	}

	var templates []*Template
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), setupScriptSuffix) {
			continue
		}
		name := strings.TrimSuffix(entry.Name(), setupScriptSuffix)
		if name == "" {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		t, err := loadSetupHeaderTemplate(path, name)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", entry.Name(), err)
		}
		if t != nil {
			templates = append(templates, t)
		}
	}

	// Display order follows the name, so the list is stable without a key for it.
	sort.Slice(templates, func(i, j int) bool { return templates[i].Name < templates[j].Name })
	for i, t := range templates {
		t.DisplayOrder = i + 1
	}
	return templates, nil
}

func loadSetupHeaderTemplate(path, name string) (*Template, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return ParseSetupHeader(lines, name)
}

// ParseSetupHeader builds a template from a setup script's lines, or returns nil
// when its leading comment block has no `# cb-template:` line. Only that block is
// read — from the top (after any shebang) to the first line that is neither blank
// nor a comment — so a `cb-…:` string further down the script is never a key.
func ParseSetupHeader(lines []string, name string) (*Template, error) {
	type keyLine struct {
		key, value string
		lineNo     int
	}
	var keys []keyLine
	for i, raw := range lines {
		line := strings.TrimSpace(raw)
		if i == 0 && strings.HasPrefix(line, "#!") {
			continue
		}
		if line == "" {
			continue
		}
		if !strings.HasPrefix(line, "#") {
			break
		}
		if m := headerKeyLine.FindStringSubmatch(line); m != nil {
			keys = append(keys, keyLine{key: m[1], value: m[2], lineNo: i + 1})
		}
	}

	marked := false
	for _, k := range keys {
		if k.key == "template" {
			marked = true
			break
		}
	}
	if !marked {
		return nil, nil
	}

	t := &Template{
		Name:         name,
		CategoryName: ProjectCategoryName,
		Primary:      true,
	}
	band := defaultSetupBand
	seen := map[string]int{}

	for _, k := range keys {
		if k.key != "param" && k.key != "requires" && k.key != "tags" {
			if prev, dup := seen[k.key]; dup {
				return nil, fmt.Errorf("line %d: cb-%s already set on line %d", k.lineNo, k.key, prev)
			}
			seen[k.key] = k.lineNo
		}

		switch k.key {
		case "template":
			t.DisplayName = k.value
			if t.DisplayName == "" {
				t.DisplayName = name
			}
		case "disc":
			t.DisplayDesc = k.value
		case "detail":
			t.DisplayDetail = k.value
		case "version":
			t.CBVersion = k.value
		case "band":
			n, err := strconv.Atoi(k.value)
			if err != nil || n < 0 {
				return nil, fmt.Errorf("line %d: cb-band must be a non-negative number, got %q", k.lineNo, k.value)
			}
			band = n
		case "requires":
			t.Requires = append(t.Requires, splitList(k.value)...)
		case "tags":
			t.Tags = append(t.Tags, splitList(k.value)...)
		case "param":
			pname, p, err := parseHeaderParam(k.value)
			if err != nil {
				return nil, fmt.Errorf("line %d: %w", k.lineNo, err)
			}
			if _, dup := t.Params[pname]; dup {
				return nil, fmt.Errorf("line %d: param %s declared twice", k.lineNo, pname)
			}
			if t.Params == nil {
				t.Params = map[string]Param{}
			}
			t.Params[pname] = p
			t.ParamOrder = append(t.ParamOrder, pname)
		default:
			return nil, fmt.Errorf("line %d: unknown key cb-%s (known: cb-template, cb-disc, cb-detail, cb-band, cb-requires, cb-tags, cb-param, cb-version)", k.lineNo, k.key)
		}
	}

	setupLine := "setup " + name
	for _, p := range t.ParamOrder {
		setupLine += " ${" + p + "}"
	}
	t.BoothfileSegments = []Segment{{Order: band, Content: setupLine + "\n"}}
	return t, nil
}

// parseHeaderParam parses `NAME [default=VALUE] [suggests=A,B,...]`.
func parseHeaderParam(value string) (string, Param, error) {
	fields := strings.Fields(value)
	if len(fields) == 0 {
		return "", Param{}, fmt.Errorf("cb-param needs a name")
	}
	name := fields[0]
	if !paramNameRe.MatchString(name) {
		return "", Param{}, fmt.Errorf("cb-param name %q must be letters, digits and underscores", name)
	}

	var p Param
	for _, field := range fields[1:] {
		attr, val, ok := strings.Cut(field, "=")
		if !ok {
			return "", Param{}, fmt.Errorf("cb-param %s: %q is not attr=value (use default= or suggests=)", name, field)
		}
		switch attr {
		case "default":
			p.Default = val
		case "suggests":
			p.Suggests = splitList(val)
		default:
			return "", Param{}, fmt.Errorf("cb-param %s: unknown attribute %q (use default= or suggests=)", name, attr)
		}
	}
	return name, p, nil
}

// splitList splits a comma- and/or space-separated list, dropping empties.
func splitList(s string) []string {
	return strings.FieldsFunc(s, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' })
}
