// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothfile

import (
	"embed"
	"strings"
)

// builtinScriptsFile lists the setup/install scripts shipped in the base image.
// Regenerate with build/gen-builtin-scripts.sh.
//
//go:embed builtin-scripts.txt
var builtinScriptsFS embed.FS

// BuiltinScripts returns the names of the setup and install scripts that the base
// image provides (without the --setup.sh / --install.sh suffix).
//
// The list is embedded at build time rather than discovered on disk: end users have
// only the binary, so FindBuiltinSetupsDir() finds nothing for them and validation
// used to switch off entirely -- or, once a project added .booth/setups/, flag every
// built-in as unknown.
func BuiltinScripts() (setupScripts []string, installScripts []string) {
	data, err := builtinScriptsFS.ReadFile("builtin-scripts.txt")
	if err != nil {
		return nil, nil
	}

	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		kind, name, found := strings.Cut(line, " ")
		if !found {
			continue
		}
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		switch kind {
		case "setup":
			setupScripts = append(setupScripts, name)
		case "install":
			installScripts = append(installScripts, name)
		}
	}

	return setupScripts, installScripts
}

// KnownBuiltinScripts returns the built-in script names, merging the embedded list
// with a scan of dir when dir is non-empty.
//
// The scan keeps a CodingBooth checkout honest: a script added under
// variants/base/setups/ is usable before the embedded list is regenerated.
func KnownBuiltinScripts(dir string) (setupScripts []string, installScripts []string) {
	setupScripts, installScripts = BuiltinScripts()

	scannedSetups, scannedInstalls := ScanSetupsDir(dir)
	setupScripts = union(setupScripts, scannedSetups)
	installScripts = union(installScripts, scannedInstalls)

	return setupScripts, installScripts
}

// union appends the entries of extra that are not already in base.
func union(base []string, extra []string) []string {
	if len(extra) == 0 {
		return base
	}

	seen := make(map[string]bool, len(base))
	for _, s := range base {
		seen[s] = true
	}

	for _, s := range extra {
		if !seen[s] {
			seen[s] = true
			base = append(base, s)
		}
	}

	return base
}
