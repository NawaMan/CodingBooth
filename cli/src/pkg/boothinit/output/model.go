// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package output defines the data model for booth init output and serialization
// to the .booth/ directory structure.
package output

// BoothOutput holds all generated content to be written to .booth/.
type BoothOutput struct {
	Command       string // Exact command used to generate (e.g., "booth init new . --select go")
	AdjustCommand string // Reformatted command for easy adjustment (--select last)
	Config        *ConfigToml
	Boothfile *BoothfileContent
	Startups  []FileContent
	Setups    []FileContent
	Home      []FileContent
	HomeSeed  []FileContent
	Cache     []FileContent // Files to touch in .booth/cache/ (paths mirror container filesystem)
	CacheDirs []FileContent // Directories to create in .booth/cache/ with .mount-this marker
}

// ConfigToml represents the content of .booth/config.toml.
// Scalar fields use match-or-error merge strategy.
// Array fields use combine-and-dedup merge strategy.
type ConfigToml struct {
	Variant  string
	Port     string
	Timezone string
	Dind     bool
	Cmds     []string
	RunArgs  []string
	BuildArgs []string

	// Overrides holds extra key-value pairs from --set flags.
	// These are written to config.toml after the known fields above.
	Overrides map[string]interface{}
}

// BoothfileContent represents the content of .booth/Boothfile.
// Content is the raw text of the Boothfile (already merged/ordered segments).
type BoothfileContent struct {
	Content string
}

// FileContent represents a file to be written to a target location.
// Either SourcePath (file-based) or Content (inline) is set, not both.
// RelPath is the path relative to the target directory (e.g., ".config/myapp/config.yaml").
type FileContent struct {
	SourcePath string // absolute path to source file (empty for inline)
	RelPath    string
	Content    string // inline content (empty for file-based)
}
