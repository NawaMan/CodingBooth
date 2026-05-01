// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nawaman/codingbooth/src/pkg/boothfile"
)

// emitDockerfile compiles a Boothfile and prints the generated Dockerfile to stdout.
func emitDockerfile() {
	// Parse arguments: emit-dockerfile [--code <path>] [--boothfile <path>] [--strict]
	codePath := "."
	boothfilePath := ""
	strict := false

	args := os.Args[2:] // Skip "codingbooth" and "emit-dockerfile"
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--code":
			if i+1 < len(args) {
				codePath = args[i+1]
				i++
			} else {
				fmt.Fprintln(os.Stderr, "Error: --code requires a path argument")
				os.Exit(1)
			}
		case "--boothfile":
			if i+1 < len(args) {
				boothfilePath = args[i+1]
				i++
			} else {
				fmt.Fprintln(os.Stderr, "Error: --boothfile requires a path argument")
				os.Exit(1)
			}
		case "--strict":
			strict = true
		default:
			fmt.Fprintf(os.Stderr, "Error: unknown option: %s\n", args[i])
			fmt.Fprintln(os.Stderr, "Usage: booth emit-dockerfile [--code <path>] [--boothfile <path>] [--strict]")
			os.Exit(1)
		}
	}

	// Determine Boothfile path
	if boothfilePath == "" {
		// Auto-detect from code path
		boothfilePath = filepath.Join(codePath, ".booth", "Boothfile")
	}

	// Check if Boothfile exists
	if _, err := os.Stat(boothfilePath); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "Error: Boothfile not found at '%s'\n", boothfilePath)
		os.Exit(1)
	}

	// Read Boothfile
	content, err := os.ReadFile(boothfilePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to read Boothfile '%s': %v\n", boothfilePath, err)
		os.Exit(1)
	}

	// Parse
	parser := boothfile.NewParser()
	if strict {
		parser = boothfile.NewStrictParser()
	}
	parseResult := parser.ParseString(string(content))

	// Check for parse errors
	if parseResult.HasErrors() {
		fmt.Fprintf(os.Stderr, "Error: Boothfile compilation failed:\n")
		for _, e := range parseResult.Errors {
			fmt.Fprintf(os.Stderr, "  %s\n", e.Error())
		}
		os.Exit(1)
	}

	// Show warnings
	if parseResult.HasWarnings() {
		for _, w := range parseResult.Warnings {
			fmt.Fprintf(os.Stderr, "Warning: %s\n", w.Error())
		}
	}

	// Compile with custom setups directory if it exists
	customSetupsDir := filepath.Join(codePath, ".booth", "setups")
	hasCustomSetups := isDir(customSetupsDir)

	// Scan for custom scripts
	customSetupScripts, customInstallScripts := boothfile.ScanSetupsDir(customSetupsDir)

	// Scan for built-in scripts (if we can find the directory)
	builtinSetupsDir := boothfile.FindBuiltinSetupsDir()
	builtinSetupScripts, builtinInstallScripts := boothfile.ScanSetupsDir(builtinSetupsDir)

	compilerOpts := boothfile.CompilerOptions{
		CustomSetupsDir:      ".booth/setups",
		HasCustomSetups:      hasCustomSetups,
		KnownSetupScripts:    builtinSetupScripts,
		KnownInstallScripts:  builtinInstallScripts,
		CustomSetupScripts:   customSetupScripts,
		CustomInstallScripts: customInstallScripts,
	}
	compiler := boothfile.NewCompilerWithOptions(compilerOpts)
	compileResult := compiler.Compile(parseResult)

	// Check for compile errors
	if compileResult.HasErrors() {
		fmt.Fprintf(os.Stderr, "Error: Boothfile compilation failed:\n")
		for _, e := range compileResult.Errors {
			fmt.Fprintf(os.Stderr, "  %s\n", e.Error())
		}
		os.Exit(1)
	}

	// Handle warnings
	if compileResult.HasWarnings() {
		for _, w := range compileResult.Warnings {
			fmt.Fprintf(os.Stderr, "Warning: %s\n", w.Error())
		}
		// In strict mode, warnings are errors
		if strict {
			fmt.Fprintf(os.Stderr, "Error: Boothfile compilation failed due to warnings (--strict mode)\n")
			os.Exit(1)
		}
	}

	// Print to stdout
	fmt.Print(compileResult.Dockerfile)
}

// isDir checks if a path is a directory.
func isDir(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.IsDir()
}

