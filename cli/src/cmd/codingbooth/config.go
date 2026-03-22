// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/tui"
)

// runConfig handles the "config" command — interactive TUI for booth configuration.
func runConfig(version string) {
	args := os.Args[2:] // skip "codingbooth" and "config"

	if len(args) > 0 && (args[0] == "help" || args[0] == "--help" || args[0] == "-h") {
		printConfigHelp()
		return
	}

	// Parse target path (first non-flag argument)
	targetPath := "."
	flagArgs := args
	if len(args) > 0 && !strings.HasPrefix(args[0], "--") {
		targetPath = args[0]
		flagArgs = args[1:]
	}

	flags := parseInitFlags(flagArgs)

	// Resolve templates
	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()
	flags.templatesPath = templatesPath

	// Load registry
	registry, err := tmpl.LoadRegistry(flags.templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	// Read existing .booth/ configuration as baseline
	existingFlags := readExistingBooth(targetPath)

	// Merge: existing booth is the baseline, CLI flags override
	mergedFlags := mergeFlags(existingFlags, flags)

	// Build pre-selection from merged flags
	pre := buildPreSelection(registry, mergedFlags)

	// Run TUI
	result, err := tui.RunConfig(registry, pre)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if !result.Confirmed {
		fmt.Fprintln(os.Stderr, "Cancelled.")
		return
	}

	// Apply TUI results back to flags
	if result.SelectDSL != "" {
		flags.selectDSLs = []string{result.SelectDSL}
		flags.selectDSL = result.SelectDSL
	}
	if result.Variant != "" {
		flags.variant = result.Variant
	}
	if result.Port != "" {
		flags.port = result.Port
	}

	// Run the init pipeline
	var out *output.BoothOutput
	var resolved *selection.ResolvedSelection

	if flags.selectDSL == "" {
		out, resolved = compileEmpty(flags)
	} else {
		out, resolved = compileSelection(flags)
	}

	out.Command = buildInitCommand(targetPath, flags)
	out.AdjustCommand = buildAdjustCommand(flags)

	// Check for conflicts
	conflicts := output.FindConflicts(out, targetPath)
	if len(conflicts) > 0 && !flags.overwrite {
		fmt.Fprintf(os.Stderr, "\nThe following %d file(s) already exist:\n", len(conflicts))
		for _, c := range conflicts {
			rel, _ := filepath.Rel(targetPath, c)
			fmt.Fprintf(os.Stderr, "  %s\n", rel)
		}
		fmt.Fprint(os.Stderr, "\nOverwrite? [y/N] ")
		var answer string
		fmt.Scanln(&answer)
		if answer != "y" && answer != "Y" {
			fmt.Fprintln(os.Stderr, "Aborted.")
			os.Exit(1)
		}
	}

	if err := output.WriteOutput(out, targetPath); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("\nInitialized .booth/ in %s\n", targetPath)
	printSummary(resolved)

	if flags.start {
		fmt.Printf("Starting booth in %s ...\n", targetPath)
		runBooth(version, []string{os.Args[0], "--code", targetPath})
		return
	}

	absTarget, _ := filepath.Abs(targetPath)
	absCwd, _ := os.Getwd()
	if absTarget == absCwd {
		fmt.Printf("\nTo start:  %s\n", filepath.Base(os.Args[0]))
	} else {
		fmt.Printf("\nTo start:  cd %s && %s\n", targetPath, filepath.Base(os.Args[0]))
	}
}

// readExistingBooth reads the "# Adjust with :" header from an existing .booth/Boothfile
// and parses it into initFlags. Returns empty flags if no existing booth is found.
func readExistingBooth(targetPath string) initFlags {
	boothfilePath := filepath.Join(targetPath, ".booth", "Boothfile")
	f, err := os.Open(boothfilePath)
	if err != nil {
		return initFlags{}
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	linesRead := 0
	for scanner.Scan() && linesRead < 10 {
		line := scanner.Text()
		linesRead++

		if strings.HasPrefix(line, "# Adjust with : ") {
			cmd := strings.TrimPrefix(line, "# Adjust with : ")
			return parseAdjustCommand(cmd)
		}
		if strings.HasPrefix(line, "# Adjust with :") {
			cmd := strings.TrimPrefix(line, "# Adjust with :")
			cmd = strings.TrimSpace(cmd)
			return parseAdjustCommand(cmd)
		}
	}

	return initFlags{}
}

// parseAdjustCommand parses a command string like "booth init adjust --select go/python --variant codeserver"
// into initFlags.
func parseAdjustCommand(cmd string) initFlags {
	// Split into args, skipping "booth init adjust" prefix
	parts := strings.Fields(cmd)
	var args []string
	skip := 0
	for _, p := range parts {
		if skip < 3 && (p == "booth" || p == "init" || p == "adjust" || p == "new") {
			skip++
			continue
		}
		args = append(args, p)
	}

	if len(args) == 0 {
		return initFlags{}
	}

	// Reconstruct quoted --select values that may have been split
	// The adjust command stores --select as a single value, but it may contain spaces
	// For safety, just use parseInitFlags which handles all flag parsing
	return parseInitFlags(args)
}

// mergeFlags merges existing booth flags (baseline) with CLI flags (overrides).
// CLI flags take precedence over existing values.
func mergeFlags(existing, cli initFlags) initFlags {
	merged := existing

	// CLI overrides
	if len(cli.selectDSLs) > 0 {
		merged.selectDSLs = cli.selectDSLs
		merged.selectDSL = cli.selectDSL
	}
	if cli.variant != "" {
		merged.variant = cli.variant
	}
	if cli.port != "" {
		merged.port = cli.port
	}
	if len(cli.cmds) > 0 {
		merged.cmds = cli.cmds
	}
	if len(cli.exposes) > 0 {
		merged.exposes = cli.exposes
	}
	if len(cli.envs) > 0 {
		merged.envs = cli.envs
	}
	if len(cli.mounts) > 0 {
		merged.mounts = cli.mounts
	}
	if len(cli.sets) > 0 {
		merged.sets = cli.sets
	}
	if cli.templatesPath != "" {
		merged.templatesPath = cli.templatesPath
	}
	if cli.version != "" {
		merged.version = cli.version
	}
	if cli.debug {
		merged.debug = true
	}
	if cli.start {
		merged.start = true
	}
	if cli.overwrite {
		merged.overwrite = true
	}

	return merged
}

// buildPreSelection converts CLI flags into a TUI pre-selection.
func buildPreSelection(registry *tmpl.TemplateRegistry, flags initFlags) *tui.PreSelection {
	pre := &tui.PreSelection{
		SelectedTemplates: make(map[string]bool),
		SelectedExts:      make(map[string]map[string]bool),
		Variant:           flags.variant,
		Port:              flags.port,
	}

	if len(flags.selectDSLs) == 0 {
		return pre
	}

	// Parse DSL to pre-populate selections
	rawInput := strings.Join(flags.selectDSLs, "/")
	parsed, err := selection.ParseSelectDSL(rawInput)
	if err != nil {
		return pre // silently fall back to empty pre-selection
	}

	for _, item := range parsed.Items {
		if _, ok := registry.ByName[item.Name]; !ok {
			continue
		}
		pre.SelectedTemplates[item.Name] = true

		if len(item.Extensions) > 0 {
			if pre.SelectedExts[item.Name] == nil {
				pre.SelectedExts[item.Name] = make(map[string]bool)
			}
			for _, ext := range item.Extensions {
				pre.SelectedExts[item.Name][ext.Name] = true
			}
		}
	}

	return pre
}

func printConfigHelp() {
	fmt.Println(`Usage: codingbooth config [path] [flags]

Interactive TUI for configuring a CodingBooth environment.
Browse and select templates, set variant and port, then generate .booth/ files.

If the target path already contains a .booth/Boothfile, the existing
configuration is loaded as the baseline. CLI flags override the existing values.

Flags:
  --select <selection>     Pre-select templates (same DSL as init)
  --variant <variant>      Pre-set variant
  --port <port>            Pre-set port
  --templates-path <dir>   Use local templates directory
  --version <ver>          Use templates from a specific release version
  --overwrite              Overwrite existing files without prompting
  --start                  Start the booth after creation
  --cmd <command>          Set default start command (repeatable)
  --expose <port>          Expose extra port (repeatable)
  --env <KEY=VALUE>        Set environment variable (repeatable)
  --mount <host:container> Mount volume (repeatable)
  --set <key=value>        Set config.toml value (repeatable)

TUI Controls:
  ↑↓             Navigate templates
  Space          Select / deselect
  Tab            Switch between config fields and tree
  ◄►             Change variant (when focused)
  Enter          Edit port (when focused)
  Ctrl+S         Save and run init
  Ctrl+Q/Ctrl+C  Quit (asks for confirmation)

Examples:
  codingbooth config
  codingbooth config ./my-project
  codingbooth config --select go+linter --variant codeserver
  codingbooth config --port 10080`)
}
