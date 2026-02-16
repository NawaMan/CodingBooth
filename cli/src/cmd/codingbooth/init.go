// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bufio"
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
	case "adjust":
		runInitNew(version, append(args[1:], "--overwrite"))
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
  new [path]               Create a new booth (default: current directory)
  adjust [path]            Re-generate booth (overwrites existing files)
  dryrun                   Preview what would be generated

Selection:
  Templates are selected with a DSL passed via --select.

  Format:  name[:param1,param2][+extension][~exclude]/name2[:params][+ext][~exc]

    /         separates templates
    :         sets parameters (positional, comma-separated)
    +         adds an extension to the preceding template
    ~         excludes an auto-selected extension

  The selection can also be read from a file (@file) or URL (@@url).

Flags:
  --templates-path <dir>   Use local templates directory (or set CB_TEMPLATES_PATH)
  --select <selection>     Template selection DSL (repeatable; required for new/dryrun)
  --variant <variant>      Set the variant (base, notebook, codeserver, xfce, kde)
  --port <port>            Set port in generated config.toml (e.g., 10000, NEXT, RANDOM)
  --cmd <command>          Set the default start command (repeatable; for new/dryrun)
  --version <ver>          Use templates from a specific release version
  --full                   Show all templates including secondary (for list)
  --debug                  Print debug output (for new/dryrun)
  --start                  Start the booth after creation (for new)
  --overwrite              Overwrite existing files without prompting (for new)

Examples:
  codingbooth init list
  codingbooth init search python
  codingbooth init new --select "go/python"
  codingbooth init new ./myproject --select "java:21+maven/postgresql"
  codingbooth init dryrun --select "go:1.23.0+linter+vscode-ext"
  codingbooth init new --select @selections.txt
  codingbooth init new --select "claude-code~credential"
  codingbooth init new --select go --select python --select claude-code
  codingbooth init new --select python --port 10080
  codingbooth init new --select python --cmd bash`)
}

type initFlags struct {
	selectDSLs    []string
	selectDSL     string // resolved: joined from selectDSLs after ReadSelectInput
	cmds          []string
	variant       string
	port          string
	templatesPath string
	version       string
	debug         bool
	start         bool
	full          bool
	overwrite     bool
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
			flags.selectDSLs = append(flags.selectDSLs, args[i+1])
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
		case "--overwrite":
			flags.overwrite = true
		case "--cmd":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --cmd requires a value")
				os.Exit(1)
			}
			flags.cmds = append(flags.cmds, shellSplit(args[i+1])...)
			i++
		case "--variant":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --variant requires a value")
				os.Exit(1)
			}
			flags.variant = args[i+1]
			i++
		case "--port":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --port requires a value")
				os.Exit(1)
			}
			flags.port = args[i+1]
			i++
		case "--version":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --version requires a value")
				os.Exit(1)
			}
			flags.version = args[i+1]
			i++
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
// The --version flag overrides the binary version for template downloads.
func resolveTemplatesPath(flags initFlags, version string) (string, func()) {
	if flags.templatesPath != "" {
		return flags.templatesPath, func() {}
	}

	if flags.version != "" {
		version = flags.version
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

// runInitNew handles: codingbooth init new [path] --select <dsl> [--templates-path <dir>] [--debug]
func runInitNew(version string, args []string) {
	targetPath := "."
	flagArgs := args
	if len(args) > 0 && !strings.HasPrefix(args[0], "--") {
		targetPath = args[0]
		flagArgs = args[1:]
	}
	flags := parseInitFlags(flagArgs)

	if len(flags.selectDSLs) == 0 {
		fmt.Fprintln(os.Stderr, "Error: --select is required")
		os.Exit(1)
	}
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()
	flags.templatesPath = templatesPath

	out, resolved := compileSelection(flags)
	out.Command = buildInitCommand(targetPath, flags)
	out.AdjustCommand = buildAdjustCommand(flags)

	if flags.debug {
		printDebug(resolved, out)
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

// runInitDryrun handles: codingbooth init dryrun --select <dsl> [--templates-path <dir>] [--debug]
func runInitDryrun(version string, args []string) {
	flags := parseInitFlags(args)

	if len(flags.selectDSLs) == 0 {
		fmt.Fprintln(os.Stderr, "Error: --select is required")
		os.Exit(1)
	}
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()
	flags.templatesPath = templatesPath

	out, resolved := compileSelection(flags)
	out.Command = buildInitCommand("", flags)
	out.AdjustCommand = buildAdjustCommand(flags)

	if flags.debug {
		printDebug(resolved, out)
		return
	}

	printDryrun(out)
}

// compileSelection runs the full pipeline: read input → parse → resolve → compile.
func compileSelection(flags initFlags) (*output.BoothOutput, *selection.ResolvedSelection) {
	// Read input (handles -, @file, @@url, plain DSL)
	// Each --select value is resolved individually, then joined with "/".
	var parts []string
	for _, dsl := range flags.selectDSLs {
		if dsl == "-" {
			data, err := io.ReadAll(os.Stdin)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error reading stdin: %v\n", err)
				os.Exit(1)
			}
			parts = append(parts, string(data))
		} else {
			resolved, err := selection.ReadSelectInput(dsl)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error reading selection: %v\n", err)
				os.Exit(1)
			}
			parts = append(parts, resolved)
		}
	}
	rawInput := strings.Join(parts, "/")

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

	// Apply CLI overrides (take precedence over template values)
	if flags.variant != "" {
		out.Config.Variant = flags.variant
	}
	if flags.port != "" {
		out.Config.Port = flags.port
	}
	if len(flags.cmds) > 0 {
		out.Config.Cmds = flags.cmds
	}

	return out, resolved
}

// printDryrun prints what would be generated without writing files.
func printDryrun(out *output.BoothOutput) {
	if out.Config != nil {
		fmt.Println("=== config.toml ===")
		fmt.Print(output.SerializeConfigToml(out.Config, out.Command, out.AdjustCommand))
		fmt.Println()
	}

	if out.Boothfile != nil {
		fmt.Println("=== Boothfile ===")
		fmt.Print(output.SerializeBoothfile(out.Boothfile, out.Command, out.AdjustCommand))
		fmt.Println()
	}

	if out.Startup != nil {
		fmt.Println("=== startup.sh ===")
		fmt.Print(output.SerializeStartup(out.Startup, out.Command, out.AdjustCommand))
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

// buildInitCommand reconstructs the booth init command string for the generated file headers.
// targetPath may be empty for dryrun.
func buildInitCommand(targetPath string, flags initFlags) string {
	var parts []string
	parts = append(parts, "booth init")
	if targetPath != "" && targetPath != "." {
		parts = append(parts, "new "+targetPath)
	} else {
		parts = append(parts, "new")
	}
	parts = append(parts, "--select "+flags.selectDSL)
	if flags.variant != "" {
		parts = append(parts, "--variant "+flags.variant)
	}
	if flags.port != "" {
		parts = append(parts, "--port "+flags.port)
	}
	for _, cmd := range flags.cmds {
		parts = append(parts, "--cmd "+cmd)
	}
	if flags.version != "" {
		parts = append(parts, "--version "+flags.version)
	}
	return strings.Join(parts, " ")
}

// buildAdjustCommand produces the "booth init adjust ..." command string for the
// generated file headers. It always puts --select last so users can easily edit it.
func buildAdjustCommand(flags initFlags) string {
	var parts []string
	parts = append(parts, "booth init adjust")
	if flags.version != "" {
		parts = append(parts, "--version "+flags.version)
	}
	if flags.variant != "" {
		parts = append(parts, "--variant "+flags.variant)
	}
	if flags.port != "" {
		parts = append(parts, "--port "+flags.port)
	}
	for _, cmd := range flags.cmds {
		parts = append(parts, "--cmd "+cmd)
	}
	parts = append(parts, "--select "+flags.selectDSL)
	return strings.Join(parts, " ")
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

// shellSplit splits a string into words, respecting single quotes, double quotes,
// and backslash escapes. Unquoted whitespace separates words.
//
//	shellSplit(`bash -c 'echo hello world'`)  → ["bash", "-c", "echo hello world"]
//	shellSplit(`echo "hello world"`)          → ["echo", "hello world"]
//	shellSplit(`python -c "print(\"hi\")"`)   → ["python", "-c", "print(\"hi\")"]
//	shellSplit(`bash`)                        → ["bash"]
func shellSplit(s string) []string {
	var words []string
	var current strings.Builder
	var quote rune // 0 = unquoted, '\'' or '"' = inside that quote
	escaped := false

	for _, r := range s {
		if escaped {
			current.WriteRune(r)
			escaped = false
			continue
		}
		if r == '\\' && quote != '\'' {
			// Backslash escapes next char (except inside single quotes, where everything is literal)
			escaped = true
			continue
		}
		switch {
		case quote != 0:
			if r == quote {
				quote = 0
			} else {
				current.WriteRune(r)
			}
		case r == '\'' || r == '"':
			quote = r
		case r == ' ' || r == '\t':
			if current.Len() > 0 {
				words = append(words, current.String())
				current.Reset()
			}
		default:
			current.WriteRune(r)
		}
	}
	if current.Len() > 0 {
		words = append(words, current.String())
	}
	return words
}
