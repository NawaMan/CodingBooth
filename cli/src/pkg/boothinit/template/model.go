// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package template defines the data model for booth init templates
// and provides loading from a directory tree.
package template

// TemplateRegistry holds all loaded categories and templates.
type TemplateRegistry struct {
	Categories []*Category
	ByName     map[string]*Template // global lookup by template name (unique across categories)
}

// Category represents a template category (languages, frameworks, tools, etc.).
type Category struct {
	Name        string      // directory name
	DisplayName string      // from meta.toml
	Order       int         // from meta.toml
	Templates   []*Template // sorted by DisplayOrder
}

// Template represents a single template or extension within a category.
type Template struct {
	Name         string // directory name (unique across all categories for top-level templates)
	CategoryName string // parent category name
	DisplayName  string // from spec.toml display-name
	DisplayDesc  string // from spec.toml display-disc
	DisplayOrder int    // from spec.toml display-order
	Tags         []string
	AutoSelect   *bool // extension only: auto-select when parent is selected

	// Config scalar values (match-or-error merge strategy)
	Variant  string
	Port     string
	Timezone string
	Dind     *bool

	// Config array values (combine-and-dedup merge strategy)
	Cmds      []string
	BuildArgs []string
	RunArgs   []string

	// Dependencies
	Requires []string

	// Parameters
	Params map[string]Param

	// Content segments (ordered by Order, tiebreak alphabetically by source)
	BoothfileSegments []Segment
	StartupSegments   []Segment

	// Files to copy
	Setups   []FileRef
	Home     []FileRef
	HomeSeed []FileRef

	// Extensions (sub-templates)
	Extensions []*Template
}

// Param defines a template parameter with default and suggested values.
type Param struct {
	Default  string
	Suggests []string
}

// Segment represents an ordered content fragment (Boothfile or startup).
type Segment struct {
	Order   int
	Content string
}

// FileRef references a file to be copied from a template to the output.
type FileRef struct {
	SourcePath string // absolute path to source file
	RelPath    string // relative path within target directory
}
