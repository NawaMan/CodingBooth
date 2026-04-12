// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package template defines the data model for booth config templates
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
	DisplayName  string // from template.toml display-name
	DisplayDesc   string // from template.toml display-disc (short description for list view)
	DisplayDetail string // from template.toml display-detail (long description for show view)
	DisplayOrder  int    // from template.toml display-order
	Tags         []string
	Primary      bool  // shown by default in list/search; non-primary only shown with --full
	AutoSelect   *bool // extension only: auto-select when parent is selected

	// Config scalar values (match-or-error merge strategy)
	Variant  string
	Port     string
	Timezone string
	Dind     *bool
	Sudo     *bool

	// Config array values (combine-and-dedup merge strategy)
	Cmds      []string
	BuildArgs []string
	RunArgs   []string

	// Dependencies
	Requires []string

	// Parameters
	Params     map[string]Param
	ParamOrder []string // declaration order from template.toml

	// Content segments (ordered by Order, tiebreak alphabetically by source)
	BoothfileSegments []Segment
	StartupSegments   []Segment

	// Files to copy
	Setups   []FileRef
	Home     []FileRef
	HomeSeed []FileRef

	// Cache files to touch in .booth/cache/ (paths mirror container filesystem)
	CacheFiles []string

	// Cache directories to create in .booth/cache/ with .mount-this marker
	CacheDirs []string

	// Extensions (sub-templates)
	Extensions []*Template
}

// Param defines a template parameter with default and suggested values.
type Param struct {
	Default  string
	Suggests []string
	Variadic bool // if true, absorbs all remaining positional values joined with ","
}

// Segment represents an ordered content fragment (Boothfile or startup).
type Segment struct {
	Order   int
	Content string
}

// FileRef references a file to be copied from a template to the output.
// Either SourcePath (file-based) or Content (inline) is set, not both.
type FileRef struct {
	SourcePath string // absolute path to source file (empty for inline)
	RelPath    string // relative path within target directory
	Content    string // inline content from TOML (empty for file-based)
}
