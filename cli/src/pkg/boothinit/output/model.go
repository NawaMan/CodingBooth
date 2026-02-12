// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package output defines the data model for booth init output and serialization
// to the .booth/ directory structure.
package output

// BoothOutput holds all generated content to be written to .booth/.
type BoothOutput struct {
	Config    *ConfigToml
	Boothfile *BoothfileContent
	Startup   *StartupContent
	Setups    []FileContent
	Home      []FileContent
	HomeSeed  []FileContent
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
}

// BoothfileContent represents the content of .booth/Boothfile.
// Content is the raw text of the Boothfile (already merged/ordered segments).
type BoothfileContent struct {
	Content string
}

// StartupContent represents the content of .booth/startup.sh.
// Content is the raw body of the startup script (already merged/ordered segments).
type StartupContent struct {
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
