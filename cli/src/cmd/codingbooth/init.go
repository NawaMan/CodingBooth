// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/cache"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/compiler"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// runInit handles the "init" command and its subcommands.
func runInit(version string) {
	args := os.Args[2:] // skip "codingbooth" and "init"

	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		printInitHelp()
		if len(args) == 0 {
			os.Exit(1)
		}
		return
	}

	subCmd := args[0]
	switch subCmd {
	case "list":
		runInitList(version, args[1:])
	case "search":
		runInitSearch(version, args[1:])
	case "new":
		runInitNew(version, args[1:])
	case "dryrun":
		runInitDryrun(version, args[1:])
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown init subcommand: %s\n\n", subCmd)
		printInitHelp()
		os.Exit(1)
	}
}

func printInitHelp() {
	fmt.Println(`Usage: codingbooth init <command> [flags]

Commands:
  list                     List available templates
  search <term>            Search templates by name or tag
  new <path>               Create a new booth at the given path
  dryrun                   Preview what would be generated

Selection:
  Templates are selected with a DSL passed via --select.

  Format:  name[:param1,param2][+extension]/name2[:params][+ext]

    /         separates templates
    :         sets parameters (positional, comma-separated)
    +         adds an extension to the preceding template

  The selection can also be read from a file (@file) or URL (@@url).

Flags:
  --templates-path <dir>   Use local templates directory (or set CB_TEMPLATES_PATH)
  --select <dsl>           Template selection DSL (required for new/dryrun)
  --full                   Show all templates including secondary (for list)
  --debug                  Print debug output (for new/dryrun)
  --start                  Start the booth after creation (for new)

Examples:
  codingbooth init list
  codingbooth init search python
  codingbooth init new ./myproject --select "go/python"
  codingbooth init new ./myproject --select "java:21+maven/postgresql"
  codingbooth init dryrun --select "go:1.23.0+linter+vscode-ext"
  codingbooth init new ./myproject --select @selections.txt`)
}

type initFlags struct {
	selectDSL     string
	templatesPath string
	debug         bool
	start         bool
	full          bool
}

func parseInitFlags(args []string) initFlags {
	var flags initFlags
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--select":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --select requires a value")
				os.Exit(1)
			}
			flags.selectDSL = args[i+1]
			i++
		case "--templates-path":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --templates-path requires a path")
				os.Exit(1)
			}
			flags.templatesPath = args[i+1]
			i++
		case "--debug":
			flags.debug = true
		case "--start":
			flags.start = true
		case "--full":
			flags.full = true
		default:
			fmt.Fprintf(os.Stderr, "Error: unknown flag: %s\n", args[i])
			os.Exit(1)
		}
	}
	// Fall back to env var if --templates-path not provided
	if flags.templatesPath == "" {
		flags.templatesPath = os.Getenv("CB_TEMPLATES_PATH")
	}
	return flags
}

// resolveTemplatesPath returns the templates directory path and a cleanup function.
// If --templates-path or CB_TEMPLATES_PATH is set, it uses that directly.
// Otherwise, it downloads and extracts templates from the GitHub release cache.
func resolveTemplatesPath(flags initFlags, version string) (string, func()) {
	if flags.templatesPath != "" {
		return flags.templatesPath, func() {}
	}

	dir, cleanup, err := cache.ResolveTemplatesDir(version)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving templates: %v\n", err)
		fmt.Fprintln(os.Stderr, "Hint: use --templates-path or set CB_TEMPLATES_PATH for local templates")
		os.Exit(1)
	}
	return dir, cleanup
}

// runInitList handles: codingbooth init list [--templates-path <dir>] [--full]
func runInitList(version string, args []string) {
	flags := parseInitFlags(args)
	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()

	registry, err := tmpl.LoadRegistry(templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	if !flags.full {
		registry = registry.FilterPrimary()
	}

	tmpl.FormatRegistry(os.Stdout, registry)

	if !flags.full {
		fmt.Println("\nUse --full to see all available templates.")
	}
	fmt.Println("Use 'init search <term>' to find templates by name or tag.")
}

// runInitSearch handles: codingbooth init search <term> [--templates-path <dir>] [--full]
func runInitSearch(version string, args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Error: 'init search' requires a search term")
		fmt.Fprintln(os.Stderr, "Usage: codingbooth init search <term> --templates-path <dir>")
		os.Exit(1)
	}

	searchTerm := args[0]
	flags := parseInitFlags(args[1:])
	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()

	registry, err := tmpl.LoadRegistry(templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	filtered := registry.Search(searchTerm)

	if len(filtered.Categories) == 0 {
		fmt.Println("No templates found matching:", searchTerm)
		return
	}

	tmpl.FormatRegistry(os.Stdout, filtered)
}

// runInitNew handles: codingbooth init new <path> --select <dsl> [--templates-path <dir>] [--debug]
func runInitNew(version string, args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Error: 'init new' requires a target path")
		fmt.Fprintln(os.Stderr, "Usage: codingbooth init new <path> --select <dsl> --templates-path <dir>")
		os.Exit(1)
	}

	targetPath := args[0]
	flags := parseInitFlags(args[1:])

	if flags.selectDSL == "" {
		fmt.Fprintln(os.Stderr, "Error: --select is required")
		os.Exit(1)
	}

	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()
	flags.templatesPath = templatesPath

	out, resolved := compileSelection(flags)

	if flags.debug {
		printDebug(resolved, out)
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

	fmt.Printf("\nTo start:  cd %s && %s\n", targetPath, filepath.Base(os.Args[0]))
}

// runInitDryrun handles: codingbooth init dryrun --select <dsl> [--templates-path <dir>] [--debug]
func runInitDryrun(version string, args []string) {
	flags := parseInitFlags(args)

	if flags.selectDSL == "" {
		fmt.Fprintln(os.Stderr, "Error: --select is required")
		os.Exit(1)
	}

	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()
	flags.templatesPath = templatesPath

	out, resolved := compileSelection(flags)

	if flags.debug {
		printDebug(resolved, out)
		return
	}

	printDryrun(out)
}

// compileSelection runs the full pipeline: read input → parse → resolve → compile.
func compileSelection(flags initFlags) (*output.BoothOutput, *selection.ResolvedSelection) {
	// Read input (handles -, @file, @@url, plain DSL)
	selectDSL := flags.selectDSL
	if selectDSL == "-" {
		data, err := io.ReadAll(os.Stdin)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading stdin: %v\n", err)
			os.Exit(1)
		}
		selectDSL = string(data)
	}
	rawInput, err := selection.ReadSelectInput(selectDSL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading selection: %v\n", err)
		os.Exit(1)
	}

	// Load templates
	registry, err := tmpl.LoadRegistry(flags.templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	// Parse DSL
	parsed, err := selection.ParseSelectDSL(rawInput)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing selection: %v\n", err)
		os.Exit(1)
	}

	// Resolve against registry
	resolved, err := selection.Resolve(parsed, registry)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving selection: %v\n", err)
		os.Exit(1)
	}

	// Compile to output
	out, err := compiler.Compile(resolved)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error compiling: %v\n", err)
		os.Exit(1)
	}

	return out, resolved
}

// printDryrun prints what would be generated without writing files.
func printDryrun(out *output.BoothOutput) {
	if out.Config != nil {
		fmt.Println("=== config.toml ===")
		fmt.Print(output.SerializeConfigToml(out.Config))
		fmt.Println()
	}

	if out.Boothfile != nil {
		fmt.Println("=== Boothfile ===")
		fmt.Print(output.SerializeBoothfile(out.Boothfile))
		fmt.Println()
	}

	if out.Startup != nil {
		fmt.Println("=== startup.sh ===")
		fmt.Print(output.SerializeStartup(out.Startup))
		fmt.Println()
	}

	if len(out.Setups) > 0 {
		fmt.Println("=== setups/ ===")
		for _, f := range out.Setups {
			fmt.Printf("  %s (from %s)\n", f.RelPath, f.SourcePath)
		}
		fmt.Println()
	}

	if len(out.Home) > 0 {
		fmt.Println("=== home/ ===")
		for _, f := range out.Home {
			fmt.Printf("  %s (from %s)\n", f.RelPath, f.SourcePath)
		}
		fmt.Println()
	}

	if len(out.HomeSeed) > 0 {
		fmt.Println("=== home-seed/ ===")
		for _, f := range out.HomeSeed {
			fmt.Printf("  %s (from %s)\n", f.RelPath, f.SourcePath)
		}
		fmt.Println()
	}
}

// printDebug outputs the resolved selection and compiled output as JSON.
func printDebug(resolved *selection.ResolvedSelection, out *output.BoothOutput) {
	fmt.Println("=== Selection ===")
	for i, st := range resolved.Templates {
		fmt.Printf("[%d] %s (mode=%d)\n", i, st.Template.Name, st.SelectMode)
		if len(st.ParamValues) > 0 {
			fmt.Printf("    params: ")
			data, _ := json.Marshal(st.ParamValues)
			fmt.Println(string(data))
		}
		for _, ext := range st.Extensions {
			fmt.Printf("    + %s (mode=%d)\n", ext.Extension.Name, ext.SelectMode)
		}
	}
	fmt.Println()

	fmt.Println("=== Compiled Output ===")
	data, _ := json.MarshalIndent(out, "", "  ")
	fmt.Println(string(data))
	fmt.Println()

	printDryrun(out)
}

// printSummary prints a human-readable summary of the resolved selection.
func printSummary(resolved *selection.ResolvedSelection) {
	for _, st := range resolved.Templates {
		line := st.Template.DisplayName
		if len(st.ParamValues) > 0 {
			var params []string
			for k, v := range st.ParamValues {
				params = append(params, k+"="+v)
			}
			line += " (" + strings.Join(params, ", ") + ")"
		}
		fmt.Printf("  - %s\n", line)
		for _, ext := range st.Extensions {
			mode := ""
			if ext.SelectMode == selection.AutoSelected {
				mode = " (auto)"
			}
			fmt.Printf("    + %s%s\n", ext.Extension.DisplayName, mode)
		}
	}
	fmt.Println()
}
