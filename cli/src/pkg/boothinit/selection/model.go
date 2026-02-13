// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package selection handles parsing the --select DSL and resolving
// selections against a template registry.
package selection

import (
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// SelectMode indicates how a template or extension was selected.
type SelectMode int

const (
	ExplicitSelect   SelectMode = iota // user explicitly selected
	AutoSelected                       // auto-select=true on extension
	DependencySelect                   // required by another template
)

// ParsedSelection is the raw result of parsing a --select DSL string.
type ParsedSelection struct {
	Items []ParsedItem
}

// ParsedItem is a single template selection from the DSL.
// e.g., "go:1.24+linter~credential" → Name="go", Params=["1.24"], Extensions=["linter"], Excludes=["credential"]
type ParsedItem struct {
	Name       string
	Params     []string
	Extensions []string
	Excludes   []string // extensions to exclude (from ~ operator)
}

// ResolvedSelection is a validated selection ready for output generation.
type ResolvedSelection struct {
	Templates []SelectedTemplate
}

// SelectedTemplate represents a fully resolved template selection.
type SelectedTemplate struct {
	Template    *tmpl.Template
	ParamValues map[string]string
	Extensions  []SelectedExtension
	SelectMode  SelectMode
}

// SelectedExtension represents a selected extension within a template.
type SelectedExtension struct {
	Extension  *tmpl.Template
	SelectMode SelectMode
}
