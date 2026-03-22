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

// runConfig handles the "config" command — booth configuration via TUI or CLI.
//
//	booth config                        → TUI (empty)
//	booth config --select go            → TUI pre-populated
//	booth config --no-tui --select go   → CLI mode
//	booth config --dryrun --select go   → TUI, dryrun on confirm
//	booth config --no-tui --dryrun ...  → CLI dryrun
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

	if flags.noTUI {
		runConfigCLI(version, targetPath, flags)
	} else {
		runConfigTUI(version, targetPath, flags)
	}
}

// runConfigCLI handles non-interactive mode (--no-tui).
func runConfigCLI(version string, targetPath string, flags initFlags) {
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

	var out *output.BoothOutput
	var resolved *selection.ResolvedSelection

	if len(flags.selectDSLs) == 0 {
		out, resolved = compileEmpty(flags)
	} else {
		templatesPath, cleanup := resolveTemplatesPath(flags, version)
		defer cleanup()
		flags.templatesPath = templatesPath
		out, resolved = compileSelection(flags)
	}

	out.Command = buildConfigCommand(targetPath, flags)
	out.AdjustCommand = buildConfigAdjustCommand(flags)

	if flags.debug {
		printDebug(resolved, out)
	}

	if flags.dryrun {
		printDryrun(out)
		return
	}

	// Check for existing files that would be overwritten
	conflicts := output.FindConflicts(out, targetPath)
	if len(conflicts) > 0 && !flags.overwrite {
		fmt.Fprintf(os.Stderr, "The following %d file(s) already exist:\n", len(conflicts))
		for _, c := range conflicts {
			rel, _ := filepath.Rel(targetPath, c)
			fmt.Fprintf(os.Stderr, "  %s\n", rel)
		}
		fmt.Fprint(os.Stderr, "\nOverwrite? [y/N] ")
		reader := bufio.NewReader(os.Stdin)
		answer, _ := reader.ReadString('\n')
		answer = strings.TrimSpace(answer)
		if answer != "y" && answer != "Y" {
			fmt.Fprintln(os.Stderr, "Aborted.")
			os.Exit(1)
		}
	}

	if err := output.WriteOutput(out, targetPath); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Initialized .booth/ in %s\n", targetPath)
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

// runConfigTUI handles interactive TUI mode (default).
func runConfigTUI(version string, targetPath string, flags initFlags) {
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

	// Apply string fields
	if v := result.StringFields["variant"]; v != "" {
		flags.variant = v
	}
	if v := result.StringFields["port"]; v != "" {
		flags.port = v
	}
	if v := result.StringFields["version"]; v != "" {
		flags.version = v
	}

	// Apply bool fields as --set overrides
	boolSetKeys := map[string]string{
		"dind":           "dind",
		"keep-alive":     "keep-alive",
		"daemon":         "daemon",
		"writable-booth": "writable-booth",
		"public":         "public",
		"sandboxed":      "sandboxed",
		"silence-build":  "silence-build",
		"pull":           "pull",
		"strict":         "strict",
		"verbose":        "verbose",
		"dryrun":         "dryrun",
		"debug":          "debug",
	}
	for tuiKey, setKey := range boolSetKeys {
		if result.BoolFields[tuiKey] {
			flags.sets = append(flags.sets, setKey)
		}
	}

	// Apply sudo as a tri-state: "" (default/omit), "true", "false"
	if v := result.StringFields["sudo"]; v != "" {
		flags.sets = append(flags.sets, "sudo="+v)
	}

	// Apply remaining string fields as --set overrides
	stringSetKeys := map[string]string{
		"name":     "name",
		"image":    "image",
		"startup":  "startup",
		"env-file": "env-file",
		"tls-cert": "tls-cert",
		"tls-key":  "tls-key",
	}
	for tuiKey, setKey := range stringSetKeys {
		if v := result.StringFields[tuiKey]; v != "" {
			flags.sets = append(flags.sets, setKey+"="+v)
		}
	}

	// Run the init pipeline
	var out *output.BoothOutput
	var resolved *selection.ResolvedSelection

	if flags.selectDSL == "" {
		out, resolved = compileEmpty(flags)
	} else {
		out, resolved = compileSelection(flags)
	}

	out.Command = buildConfigCommand(targetPath, flags)
	out.AdjustCommand = buildConfigAdjustCommand(flags)

	if flags.dryrun {
		printDryrun(out)
		return
	}

	// Check for conflicts — TUI always overwrites on confirm
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

// parseAdjustCommand parses a command string like "booth config --no-tui --select go/python"
// or the legacy "booth init adjust --select go/python --variant codeserver" into initFlags.
func parseAdjustCommand(cmd string) initFlags {
	// Split into args, skipping command prefix words
	parts := strings.Fields(cmd)
	var args []string
	skip := 0
	for _, p := range parts {
		// Skip prefix: "booth init adjust", "booth init new", or "booth config"
		if skip < 3 && (p == "booth" || p == "init" || p == "adjust" || p == "new" || p == "config") {
			skip++
			continue
		}
		args = append(args, p)
	}

	if len(args) == 0 {
		return initFlags{}
	}

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
		StringFields:      make(map[string]string),
		BoolFields:        make(map[string]bool),
	}

	// Map CLI flags to TUI string fields
	if flags.variant != "" {
		pre.StringFields["variant"] = flags.variant
	}
	if flags.port != "" {
		pre.StringFields["port"] = flags.port
	}
	if flags.version != "" {
		pre.StringFields["version"] = flags.version
	}

	// Parse --set flags to extract bool/string config values
	if len(flags.sets) > 0 {
		overrides, err := parseSetOverrides(flags.sets)
		if err == nil {
			for k, v := range overrides {
				switch val := v.(type) {
				case bool:
					pre.BoolFields[k] = val
				case string:
					pre.StringFields[k] = val
				}
			}
		}
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

Configure a CodingBooth environment. Opens an interactive TUI by default.
Use --no-tui for non-interactive CLI mode.

If the target path already contains a .booth/Boothfile, the existing
configuration is loaded as the baseline. CLI flags override the existing values.

Flags:
  --select <selection>     Template selection DSL (repeatable)
  --no-tui                 Non-interactive CLI mode (requires --select)
  --dryrun                 Preview what would be generated without writing files
  --variant <variant>      Set variant (base, notebook, codeserver, xfce, kde)
  --port <port>            Set port (e.g., 10000, NEXT, RANDOM)
  --templates-path <dir>   Use local templates directory
  --version <ver>          Use templates from a specific release version
  --overwrite              Overwrite existing files without prompting (--no-tui only)
  --start                  Start the booth after creation
  --debug                  Print debug output
  --cmd <command>          Set default start command (repeatable)
  --expose <port>          Expose extra port (repeatable)
  --env <KEY=VALUE>        Set environment variable (repeatable)
  --mount <host:container> Mount volume (repeatable)
  --set <key=value>        Set config.toml value (repeatable)

TUI Controls:
  ↑↓             Navigate templates
  Space          Select / deselect
  ←→             Switch tabs
  Tab            Focus search bar
  Ctrl+S         Save and generate
  Ctrl+Q/Ctrl+C  Quit (asks for confirmation)

Examples:
  codingbooth config                                  # TUI (empty)
  codingbooth config --select go+linter               # TUI pre-populated
  codingbooth config --no-tui --select go+linter      # CLI mode
  codingbooth config --dryrun --select go              # TUI, dryrun on confirm
  codingbooth config --no-tui --dryrun --select go     # CLI dryrun`)
}
