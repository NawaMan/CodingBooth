// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/booth"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/cache"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/compiler"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// hostEnvPortRE matches a host port prefix that booth expands at start from the
// host environment: ${NAME}, ${NAME:-digits}, or ${NAME:-+OFFSET}. Anchored at the
// start so it can be peeled off before a ":CONTAINER" suffix. Only the host side of
// a mapping may use this form; the container port stays a number. A "+OFFSET"
// fallback is booth-relative: it expands to "+OFFSET" and ResolveRelativePorts then
// rewrites it to boothPort+OFFSET, so the default follows the booth port.
var hostEnvPortRE = regexp.MustCompile(`^\$\{[A-Za-z_][A-Za-z0-9_]*(:-\+?[0-9]+)?\}`)

type initFlags struct {
	selectDSLs    []string
	selectDSL     string // resolved: joined from selectDSLs after ReadSelectInput
	cmds          []string
	exposes       []string // --expose port mappings
	envs          []string // --env environment variables
	mounts        []string // --mount volume mounts
	sets          []string // raw --set key=value strings
	cacheFiles    []string // cache-files read back from existing config.toml
	cacheDirs     []string // cache-dirs read back from existing config.toml
	sharedFiles   []string // shared-files read back from existing config.toml
	sharedDirs    []string // shared-dirs read back from existing config.toml
	variant       string
	port          string
	templatesPath string
	version       string
	debug         bool
	start         bool
	full          bool
	detail        bool
	overwrite     bool
	beside        bool // keep hand-written files; write generated content as <name>.new
	noTUI         bool
	dryrun        bool
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
		case "--detail":
			flags.detail = true
		case "--overwrite":
			flags.overwrite = true
		case "--beside":
			flags.beside = true
		case "--no-tui":
			flags.noTUI = true
		case "--dryrun":
			flags.dryrun = true
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
		case "--expose":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --expose requires a value")
				os.Exit(1)
			}
			if err := validateExpose(args[i+1]); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			flags.exposes = append(flags.exposes, args[i+1])
			i++
		case "--env":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --env requires a value")
				os.Exit(1)
			}
			if err := validateEnv(args[i+1]); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			flags.envs = append(flags.envs, args[i+1])
			i++
		case "--mount":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --mount requires a value")
				os.Exit(1)
			}
			if err := validateMount(args[i+1]); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			flags.mounts = append(flags.mounts, args[i+1])
			i++
		case "--set":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --set requires a value")
				os.Exit(1)
			}
			flags.sets = append(flags.sets, args[i+1])
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

// runInitNew handles: codingbooth config --no-tui [path] --select <dsl> [--templates-path <dir>] [--debug]
func runInitNew(version string, args []string) {
	targetPath := "."
	flagArgs := args
	if len(args) > 0 && !strings.HasPrefix(args[0], "--") {
		targetPath = args[0]
		flagArgs = args[1:]
	}
	flags := parseInitFlags(flagArgs)
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

	var out *output.BoothOutput
	var resolved *selection.ResolvedSelection

	if len(flags.selectDSLs) == 0 {
		out, resolved = compileEmpty(flags)
	} else {
		templatesPath, cleanup := resolveTemplatesPath(flags, version)
		defer cleanup()
		flags.templatesPath = templatesPath
		out, resolved = compileSelection(flags, targetPath, readExistingArgs(targetPath))
	}

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

// runInitDryrun handles: codingbooth config --no-tui --dryrun --select <dsl> [--templates-path <dir>] [--debug]
func runInitDryrun(version string, args []string) {
	// Dryrun has no project path argument; use cwd so local recipes/templates still resolve.
	targetPath := "."
	flags := parseInitFlags(args)
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

	var out *output.BoothOutput
	var resolved *selection.ResolvedSelection

	if len(flags.selectDSLs) == 0 {
		out, resolved = compileEmpty(flags)
	} else {
		templatesPath, cleanup := resolveTemplatesPath(flags, version)
		defer cleanup()
		flags.templatesPath = templatesPath
		out, resolved = compileSelection(flags, targetPath, nil)
	}

	out.Command = buildInitCommand("", flags)
	out.AdjustCommand = buildAdjustCommand(flags)

	if flags.debug {
		printDebug(resolved, out)
		return
	}

	printDryrun(out)
}

// compileEmpty produces an empty BoothOutput with only CLI overrides applied.
// Used when no --select is given (empty booth).
func compileEmpty(flags initFlags) (*output.BoothOutput, *selection.ResolvedSelection) {
	out := &output.BoothOutput{
		Config:    &output.ConfigToml{},
		Boothfile: &output.BoothfileContent{Content: ""},
	}

	// Apply CLI overrides
	if flags.variant != "" {
		out.Config.Variant = flags.variant
	}
	if flags.port != "" {
		out.Config.Port = flags.port
	}
	if len(flags.cmds) > 0 {
		out.Config.Cmds = flags.cmds
	}
	applyExposeFlags(out.Config, flags.exposes)
	applyEnvFlags(out.Config, flags.envs)
	applyMountFlags(out.Config, flags.mounts)
	normalizePublishedPorts(out.Config)

	// Apply --set overrides
	if len(flags.sets) > 0 {
		overrides, err := parseSetOverrides(flags.sets)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing --set: %v\n", err)
			os.Exit(1)
		}
		applySetOverrides(out.Config, overrides)
	}
	out.Config.CacheFiles = append(out.Config.CacheFiles, flags.cacheFiles...)
	out.Config.CacheDirs = append(out.Config.CacheDirs, flags.cacheDirs...)
	out.Config.SharedFiles = append(out.Config.SharedFiles, flags.sharedFiles...)
	out.Config.SharedDirs = append(out.Config.SharedDirs, flags.sharedDirs...)
	mergeConfigCache(out)
	mergeConfigShared(out)

	return out, &selection.ResolvedSelection{}
}

// readExistingArgs parses `arg NAME=VALUE` lines out of an existing Boothfile at
// targetPath, returning a param-name → value map. On reconfiguration these are
// fed to the resolver as overrides so previously-pinned param values (e.g.
// PLAYWRIGHT_VERSION) survive even when the reconstructed selection DSL does not
// carry them. Returns nil when there is no existing Boothfile.
func readExistingArgs(targetPath string) map[string]string {
	boothfilePath := filepath.Join(targetPath, ".booth", "Boothfile")
	f, err := os.Open(boothfilePath)
	if err != nil {
		return nil
	}
	defer f.Close()

	args := make(map[string]string)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		rest, ok := strings.CutPrefix(line, "arg ")
		if !ok {
			continue
		}
		name, value, ok := strings.Cut(rest, "=")
		if !ok {
			continue
		}
		name = strings.TrimSpace(name)
		if name != "" {
			args[name] = strings.TrimSpace(value)
		}
	}
	if len(args) == 0 {
		return nil
	}
	return args
}

// compileSelection runs the full pipeline: read input → parse → resolve → compile.
// projectRoot is the config target (for .booth/templates and .booth/recipes).
// overrides preserves existing param values across reconfiguration (may be nil).
func compileSelection(flags initFlags, projectRoot string, overrides map[string]string) (*output.BoothOutput, *selection.ResolvedSelection) {
	// Read input (handles -, @recipe, @@url, plain DSL)
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
			resolved, err := selection.ReadSelectInputWithProject(dsl, projectRoot)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error reading selection: %v\n", err)
				os.Exit(1)
			}
			parts = append(parts, resolved)
		}
	}
	rawInput := strings.Join(parts, "/")

	// Load stock templates, merge project-local .booth/templates/ (local wins + warn)
	registry, err := tmpl.LoadMergedRegistry(flags.templatesPath, projectRoot, os.Stderr)
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

	// Resolve against registry, preserving existing param pins on reconfiguration
	resolved, err := selection.ResolveWithOverrides(parsed, registry, overrides)
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
	applyExposeFlags(out.Config, flags.exposes)
	applyEnvFlags(out.Config, flags.envs)
	applyMountFlags(out.Config, flags.mounts)
	normalizePublishedPorts(out.Config)

	// Apply --set overrides (highest precedence)
	if len(flags.sets) > 0 {
		overrides, err := parseSetOverrides(flags.sets)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing --set: %v\n", err)
			os.Exit(1)
		}
		applySetOverrides(out.Config, overrides)
	}
	out.Config.CacheFiles = append(out.Config.CacheFiles, flags.cacheFiles...)
	out.Config.CacheDirs = append(out.Config.CacheDirs, flags.cacheDirs...)
	out.Config.SharedFiles = append(out.Config.SharedFiles, flags.sharedFiles...)
	out.Config.SharedDirs = append(out.Config.SharedDirs, flags.sharedDirs...)
	mergeConfigCache(out)
	mergeConfigShared(out)

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

	for _, f := range out.Startups {
		fmt.Printf("=== startups/%s ===\n", f.RelPath)
		fmt.Print(output.SerializeStartupFile(f.Content, out.Command, out.AdjustCommand))
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

	if len(out.Cache) > 0 || len(out.CacheDirs) > 0 {
		fmt.Println("=== cache/ ===")
		for _, f := range out.Cache {
			fmt.Printf("  %s\n", f.RelPath)
		}
		for _, d := range out.CacheDirs {
			fmt.Printf("  %s/ (.mount-this)\n", d.RelPath)
		}
		fmt.Println()
	}

	if len(out.Shared) > 0 || len(out.SharedDirs) > 0 {
		fmt.Println("=== shared/ ===")
		for _, f := range out.Shared {
			fmt.Printf("  %s\n", f.RelPath)
		}
		for _, d := range out.SharedDirs {
			fmt.Printf("  %s/ (.mount-this)\n", d.RelPath)
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

// buildInitCommand reconstructs the booth config command string for the generated file headers.
// targetPath may be empty for dryrun.
func buildInitCommand(targetPath string, flags initFlags) string {
	var parts []string
	parts = append(parts, "booth config --no-tui")
	if targetPath != "" && targetPath != "." {
		parts = append(parts, targetPath)
	}
	if flags.selectDSL != "" {
		parts = append(parts, selectArg(flags.selectDSL))
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
	for _, e := range flags.exposes {
		parts = append(parts, "--expose "+e)
	}
	for _, e := range flags.envs {
		parts = append(parts, "--env "+e)
	}
	for _, m := range flags.mounts {
		parts = append(parts, "--mount "+m)
	}
	for _, s := range flags.sets {
		parts = append(parts, "--set "+s)
	}
	if flags.version != "" {
		parts = append(parts, "--version "+flags.version)
	}
	return strings.Join(parts, " ")
}

// buildAdjustCommand produces the "booth config --no-tui --overwrite ..." command string for the
// generated file headers. It always puts --select last so users can easily edit it.
func buildAdjustCommand(flags initFlags) string {
	var parts []string
	parts = append(parts, "booth config --no-tui --overwrite")
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
	for _, e := range flags.exposes {
		parts = append(parts, "--expose "+e)
	}
	for _, e := range flags.envs {
		parts = append(parts, "--env "+e)
	}
	for _, m := range flags.mounts {
		parts = append(parts, "--mount "+m)
	}
	for _, s := range flags.sets {
		parts = append(parts, "--set "+s)
	}
	if flags.selectDSL != "" {
		parts = append(parts, selectArg(flags.selectDSL))
	}
	return strings.Join(parts, " ")
}

// buildConfigCommand reconstructs the "booth config --no-tui ..." command for generated file headers.
func buildConfigCommand(targetPath string, flags initFlags) string {
	var parts []string
	parts = append(parts, "booth config")
	if targetPath != "" && targetPath != "." {
		parts = append(parts, targetPath)
	}
	parts = append(parts, "--no-tui")
	if flags.selectDSL != "" {
		parts = append(parts, selectArg(flags.selectDSL))
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
	for _, e := range flags.exposes {
		parts = append(parts, "--expose "+e)
	}
	for _, e := range flags.envs {
		parts = append(parts, "--env "+e)
	}
	for _, m := range flags.mounts {
		parts = append(parts, "--mount "+m)
	}
	for _, s := range flags.sets {
		parts = append(parts, "--set "+s)
	}
	if flags.version != "" {
		parts = append(parts, "--version "+flags.version)
	}
	return strings.Join(parts, " ")
}

// buildConfigAdjustCommand produces the "booth config --no-tui --overwrite ..." command
// for the generated file headers. Puts --select last for easy editing.
func buildConfigAdjustCommand(flags initFlags) string {
	var parts []string
	parts = append(parts, "booth config --no-tui --overwrite")
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
	for _, e := range flags.exposes {
		parts = append(parts, "--expose "+e)
	}
	for _, e := range flags.envs {
		parts = append(parts, "--env "+e)
	}
	for _, m := range flags.mounts {
		parts = append(parts, "--mount "+m)
	}
	for _, s := range flags.sets {
		parts = append(parts, "--set "+s)
	}
	if flags.selectDSL != "" {
		parts = append(parts, selectArg(flags.selectDSL))
	}
	return strings.Join(parts, " ")
}

// validateExpose checks that an --expose value is a valid port or port mapping.
// Supported formats:
//   - PORT                      (e.g., 8080)
//   - HOST:CONTAINER            (e.g., 18080:8080)
//   - IP:HOST:CONTAINER         (e.g., 127.0.0.1:18080:8080)
//   - +OFFSET:CONTAINER         (e.g., +8080:8080 — host port = booth port + offset)
//   - +OFFSET                   (e.g., +8080 — shorthand for +8080:8080)
//   - ${NAME}[:CONTAINER]       (host expanded at booth start from the host env)
//   - ${NAME:-digits}[:CONTAINER]
//   - ${NAME:-+OFFSET}:CONTAINER (fallback is booth-relative: boothPort + OFFSET)
//   - IP:${NAME:-digits}:CONTAINER
//
// Only the *host* side may use ${NAME} / ${NAME:-digits} / ${NAME:-+OFFSET}. The
// expression is kept literal in run-args and expanded by shellexpand before docker
// is invoked; a "+OFFSET" fallback is then resolved by ResolveRelativePorts. A
// booth-relative fallback needs an explicit container port — the bare HOST:HOST
// shorthand cannot carry an offset on the container side.
func validateExpose(expose string) error {
	// Handle +OFFSET and +OFFSET:CONTAINER formats
	if strings.HasPrefix(expose, "+") {
		offsetPart := expose[1:]
		parts := strings.Split(offsetPart, ":")
		switch len(parts) {
		case 1:
			// +OFFSET (e.g., +8080)
			if _, err := strconv.Atoi(parts[0]); err != nil {
				return fmt.Errorf("invalid --expose value %q: offset after '+' must be a number", expose)
			}
		case 2:
			// +OFFSET:CONTAINER (e.g., +8080:8080)
			for _, p := range parts {
				if _, err := strconv.Atoi(p); err != nil {
					return fmt.Errorf("invalid --expose value %q: ports must be numbers", expose)
				}
			}
		default:
			return fmt.Errorf("invalid --expose value %q: +OFFSET format supports +OFFSET or +OFFSET:CONTAINER", expose)
		}
		return nil
	}

	// Host-side env form must be recognized before a naive ":" split: ${NAME:-12345}
	// contains a colon that is part of the default, not a host/container separator.
	if envAt := strings.Index(expose, "${"); envAt >= 0 {
		return validateExposeEnvHost(expose, envAt)
	}

	parts := strings.Split(expose, ":")
	switch len(parts) {
	case 1:
		if !isNumericPort(parts[0]) {
			return fmt.Errorf("invalid --expose value %q: port must be a number", expose)
		}
	case 2:
		for _, p := range parts {
			if !isNumericPort(p) {
				return fmt.Errorf("invalid --expose value %q: ports must be numbers", expose)
			}
		}
	case 3:
		// ip:hostPort:containerPort
		for _, p := range parts[1:] {
			if !isNumericPort(p) {
				return fmt.Errorf("invalid --expose value %q: ports must be numbers", expose)
			}
		}
	default:
		return fmt.Errorf("invalid --expose value %q", expose)
	}
	return nil
}

// validateExposeEnvHost validates --expose values whose host side is ${NAME} or
// ${NAME:-digits}. envAt is the index of the "${" in expose.
func validateExposeEnvHost(expose string, envAt int) error {
	if envAt > 0 {
		prefix := expose[:envAt]
		if !strings.HasSuffix(prefix, ":") {
			return fmt.Errorf("invalid --expose value %q: host env reference must be the host port", expose)
		}
		before := strings.TrimSuffix(prefix, ":")
		if before == "" {
			return fmt.Errorf("invalid --expose value %q: empty IP before host env reference", expose)
		}
		// Numeric before "${…}" means HOST:${ENV} — env on the container side is not allowed.
		if isNumericPort(before) {
			return fmt.Errorf("invalid --expose value %q: only the host side may use ${NAME:-…}; container port must be a number", expose)
		}
	}

	rest := expose[envAt:]
	host := hostEnvPortRE.FindString(rest)
	if host == "" {
		return fmt.Errorf("invalid --expose value %q: host port env form must be ${NAME} or ${NAME:-digits}", expose)
	}
	after := rest[len(host):]
	if after == "" {
		// Bare ${NAME} / ${NAME:-digits}. With an IP prefix, docker still needs :CONTAINER.
		if envAt > 0 {
			return fmt.Errorf("invalid --expose value %q: IP:HOST form requires :CONTAINER", expose)
		}
		// A booth-relative fallback (${NAME:-+OFFSET}) cannot fill a bare HOST:HOST
		// shorthand: the container side would inherit the "+OFFSET" and stop being a
		// number. Require an explicit container port.
		if strings.Contains(host, ":-+") {
			return fmt.Errorf("invalid --expose value %q: a ${NAME:-+OFFSET} host port needs an explicit :CONTAINER", expose)
		}
		return nil
	}
	if !strings.HasPrefix(after, ":") {
		return fmt.Errorf("invalid --expose value %q: unexpected text after host env reference", expose)
	}
	container := after[1:]
	if !isNumericPort(container) {
		return fmt.Errorf("invalid --expose value %q: container port must be a number (only the host side may use ${NAME:-…})", expose)
	}
	return nil
}

func isNumericPort(s string) bool {
	_, err := strconv.Atoi(s)
	return err == nil
}

// isExposeHostOnly reports whether s is a host-only form (no container mapping):
// a bare number, or a full ${NAME} / ${NAME:-digits} expression (nothing after it).
func isExposeHostOnly(s string) bool {
	if isNumericPort(s) {
		return true
	}
	m := hostEnvPortRE.FindString(s)
	return m != "" && m == s
}

// applyExposeFlags appends --publish port mappings to RunArgs for each --expose value.
// Uses long-form --publish to distinguish user-set values from template-contributed -p flags.
// The +OFFSET format is stored literally and resolved at runtime by ResolveRelativePorts.
// Host-side ${NAME} / ${NAME:-digits} is also stored literally and expanded at booth start.
func applyExposeFlags(cfg *output.ConfigToml, exposes []string) {
	for _, expose := range exposes {
		mapping := expose
		if strings.HasPrefix(expose, "+") {
			// +OFFSET → +OFFSET:OFFSET (e.g., +8080 → +8080:8080)
			// +OFFSET:CONTAINER → kept as-is
			offsetPart := expose[1:]
			if !strings.Contains(offsetPart, ":") {
				mapping = expose + ":" + offsetPart
			}
		} else if isExposeHostOnly(expose) {
			// Plain port or bare ${NAME:-digits} → HOST:HOST
			// (e.g., 8080 → 8080:8080, ${APP_PORT:-3000} → ${APP_PORT:-3000}:${APP_PORT:-3000})
			mapping = expose + ":" + expose
		}
		// else HOST:CONTAINER, IP:HOST:CONTAINER, or ${NAME:-n}:CONTAINER kept as-is
		cfg.RunArgs = append(cfg.RunArgs, "--publish", mapping)
	}
}

// normalizePublishedPorts removes a port mapping that run-args publishes twice, and warns
// about a --expose that adds a second mapping where the user probably meant to move one.
//
// Two spellings of one mapping reach run-args easily: a template's short-form "-p" plus
// the user's long-form "--publish" ("cloudbeaver+expose --expose 8978:8978"), or two
// templates whose params resolve to the same mapping ("nginx+expose/apache+expose", both
// 8080:80 — the compiler's own dedup runs before params are expanded, so it sees
// "${NGINX_PORT}:80" and "${APACHE_PORT}:80" as distinct). Docker refuses to bind one host
// port twice, so a duplicate is not untidiness: the booth does not start.
//
// The long form wins when both spell the same mapping, because it is the user-owned one:
// `booth config` reads long-form flags back into --expose when re-configuring, so keeping
// it preserves the request, while the template's short form is re-added by the selection.
func normalizePublishedPorts(cfg *output.ConfigToml) {
	publishedLong := make(map[string]bool)
	for i := 0; i+1 < len(cfg.RunArgs); i++ {
		if cfg.RunArgs[i] == "--publish" {
			publishedLong[cfg.RunArgs[i+1]] = true
		}
	}

	kept := make([]string, 0, len(cfg.RunArgs))
	seen := make(map[string]bool)
	for i := 0; i < len(cfg.RunArgs); i++ {
		flag := cfg.RunArgs[i]
		if (flag == "-p" || flag == "--publish") && i+1 < len(cfg.RunArgs) {
			mapping := cfg.RunArgs[i+1]
			// Drop a repeat, and drop a short form the user also asked for by hand.
			if seen[mapping] || (flag == "-p" && publishedLong[mapping]) {
				i++
				continue
			}
			seen[mapping] = true
			kept = append(kept, flag, mapping)
			i++
			continue
		}
		kept = append(kept, flag)
	}
	cfg.RunArgs = kept

	warnExposeAddsSecondMapping(cfg)
}

// warnExposeAddsSecondMapping warns when a --expose flag publishes a container port that a
// selected template already publishes on a different host port. Docker allows it — one
// container port can be published on two host ports — but it is rarely what was meant: the
// template's mapping is still bound, so someone who reached for --expose *because* that
// host port was taken still cannot start the booth. Moving it is what an expose extension's
// host-port param is for.
func warnExposeAddsSecondMapping(cfg *output.ConfigToml) {
	type sourced struct {
		mapping string
		parsed  booth.PortMapping
	}
	var fromTemplates, fromUser []sourced

	for i := 0; i+1 < len(cfg.RunArgs); i++ {
		flag := cfg.RunArgs[i]
		if flag != "-p" && flag != "--publish" {
			continue
		}
		mapping := cfg.RunArgs[i+1]
		parsed, ok := booth.ParsePortMapping(mapping)
		if !ok {
			continue
		}
		if flag == "-p" {
			fromTemplates = append(fromTemplates, sourced{mapping, parsed})
		} else {
			fromUser = append(fromUser, sourced{mapping, parsed})
		}
	}

	for _, user := range fromUser {
		for _, tmplPort := range fromTemplates {
			sameContainer := user.parsed.Container == tmplPort.parsed.Container
			sameHost := user.parsed.Raw == tmplPort.parsed.Raw
			if !sameContainer || sameHost {
				continue
			}
			fmt.Fprintf(os.Stderr,
				"Note: a selected template already publishes container port %s as %q.\n"+
					"      --expose %s adds a second mapping; it does not move the first, which stays bound.\n"+
					"      To move it, give the expose extension the host port instead (e.g. +expose:%d).\n",
				user.parsed.Container, tmplPort.mapping, user.mapping, user.parsed.Host)
		}
	}
}

// validateEnv checks that an --env value is a valid KEY=VALUE or bare KEY.
func validateEnv(env string) error {
	if env == "" {
		return fmt.Errorf("invalid --env value: must not be empty")
	}
	key := env
	if idx := strings.Index(env, "="); idx >= 0 {
		key = env[:idx]
	}
	if key == "" {
		return fmt.Errorf("invalid --env value %q: key must not be empty", env)
	}
	for _, c := range key {
		if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') {
			return fmt.Errorf("invalid --env value %q: key contains invalid character %q", env, string(c))
		}
	}
	return nil
}

// applyEnvFlags appends --env environment variable entries to RunArgs.
// Uses long-form --env to distinguish user-set values from template-contributed -e flags.
func applyEnvFlags(cfg *output.ConfigToml, envs []string) {
	for _, env := range envs {
		cfg.RunArgs = append(cfg.RunArgs, "--env", env)
	}
}

// validateMount checks that a --mount value is a valid volume mapping.
func validateMount(mount string) error {
	if mount == "" {
		return fmt.Errorf("invalid --mount value: must not be empty")
	}
	if !strings.Contains(mount, ":") {
		return fmt.Errorf("invalid --mount value %q: must contain host:container", mount)
	}
	return nil
}

// applyMountFlags appends --volume mount entries to RunArgs.
// Uses long-form --volume to distinguish user-set values from template-contributed -v flags.
func applyMountFlags(cfg *output.ConfigToml, mounts []string) {
	for _, mount := range mounts {
		cfg.RunArgs = append(cfg.RunArgs, "--volume", mount)
	}
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

// parseSetOverrides parses --set values into a key-value map, typed to match
// what booth will decode the key as. Bare keys (no '=') are boolean true.
//
// The value's Go type here decides the TOML shape written to config.toml, so it
// has to match the field it lands in. Writing every value as a string — which is
// what this used to do — produced `idle-time = "30"` against an int field, and a
// config.toml booth refuses to load at all:
//
//	failed to read toml config: toml: line 6 (last key "idle-time"):
//	incompatible types: TOML value has type string; destination has type integer
//
// Keys are checked against the same schema, so a typo is refused up front rather
// than written out and silently ignored at every subsequent start.
func parseSetOverrides(sets []string) (map[string]interface{}, error) {
	schema := appctx.ConfigKeys()
	result := make(map[string]interface{})

	for _, s := range sets {
		key, rawValue, hasValue := strings.Cut(s, "=")

		spec, err := lookupSetKey(schema, key)
		if err != nil {
			return nil, err
		}

		if !hasValue {
			// A bare key means "turn it on", which only reads as an intent for a
			// boolean. For anything else the value is missing, not implied.
			if spec.Kind != appctx.KeyBool {
				return nil, fmt.Errorf("--set %s requires a value: %s is a %s", key, key, spec.Kind)
			}
			result[key] = true
			continue
		}

		value, err := coerceSetValue(spec, rawValue)
		if err != nil {
			return nil, err
		}

		// A list key accumulates across repeats rather than overwriting, so
		// `--set cache-files=a --set cache-files=b` keeps both.
		if spec.Kind == appctx.KeyList {
			existing, _ := result[key].([]string)
			result[key] = append(existing, value.([]string)...)
			continue
		}
		result[key] = value
	}

	return result, nil
}

// lookupSetKey resolves a --set key against the config schema, rejecting
// anything booth would not recognise.
func lookupSetKey(schema map[string]appctx.KeySpec, key string) (appctx.KeySpec, error) {
	if key == "" {
		return appctx.KeySpec{}, fmt.Errorf("empty key in --set")
	}
	if strings.ContainsAny(key, " \t\n\"'=[]{}") {
		return appctx.KeySpec{}, fmt.Errorf("invalid key %q in --set", key)
	}

	spec, known := schema[key]
	if !known {
		msg := fmt.Sprintf("unknown --set key %q: booth does not read that from config.toml", key)
		if suggestion := appctx.SuggestConfigKey(key); suggestion != "" {
			msg += fmt.Sprintf("\n       Did you mean %q?", suggestion)
		}
		msg += "\n       Run `booth --help` for the settings a booth can hold."
		return appctx.KeySpec{}, errors.New(msg)
	}

	// Known, but never read back from a file. Writing it yields a line that
	// looks effective and is ignored at every start, so say so instead of
	// letting the user find out from behaviour that never changes.
	if !spec.Read {
		fmt.Fprintf(os.Stderr,
			"Warning: %q is not read from config.toml — it only takes effect as a start-time flag (booth --%s).\n"+
				"         The key will be written, but booth will ignore it.\n", key, key)
	}

	return spec, nil
}

// coerceSetValue converts a raw --set value into the Go type matching the key's
// TOML shape, so the serializer emits `30` rather than `"30"`.
func coerceSetValue(spec appctx.KeySpec, raw string) (interface{}, error) {
	switch spec.Kind {
	case appctx.KeyBool:
		switch strings.ToLower(raw) {
		case "true", "":
			return true, nil
		case "false":
			return false, nil
		default:
			return nil, fmt.Errorf("--set %s=%s: %s is a boolean, expected true or false", spec.Key, raw, spec.Key)
		}

	case appctx.KeyInt:
		n, err := strconv.Atoi(raw)
		if err != nil {
			return nil, fmt.Errorf("--set %s=%s: %s is an integer", spec.Key, raw, spec.Key)
		}
		return n, nil

	case appctx.KeyList:
		return []string{raw}, nil

	default:
		return raw, nil
	}
}

// applySetOverrides applies --set values to the ConfigToml.
// Known fields are merged into the struct directly.
// Unknown keys go into the Overrides map.
func applySetOverrides(cfg *output.ConfigToml, overrides map[string]interface{}) {
	if cfg.Overrides == nil {
		cfg.Overrides = make(map[string]interface{})
	}
	for key, value := range overrides {
		switch key {
		case "variant":
			if s, ok := value.(string); ok {
				cfg.Variant = s
			}
		case "port":
			if s, ok := value.(string); ok {
				cfg.Port = s
			}
		case "timezone":
			if s, ok := value.(string); ok {
				cfg.Timezone = s
			}
		case "dind":
			if b, ok := value.(bool); ok {
				cfg.Dind = b
			}
		case "cache-files":
			cfg.CacheFiles = append(cfg.CacheFiles, asStringList(value)...)
		case "cache-dirs":
			cfg.CacheDirs = append(cfg.CacheDirs, asStringList(value)...)
		case "shared-files":
			cfg.SharedFiles = append(cfg.SharedFiles, asStringList(value)...)
		case "shared-dirs":
			cfg.SharedDirs = append(cfg.SharedDirs, asStringList(value)...)
		default:
			cfg.Overrides[key] = value
		}
	}
}

// asStringList normalises a --set value that feeds a list key. Repeats arrive
// already accumulated as []string; a bare string is what the callers that build
// override maps by hand (the tests, and buildPreSelection) still pass.
func asStringList(value interface{}) []string {
	switch v := value.(type) {
	case []string:
		return v
	case string:
		return []string{v}
	default:
		return nil
	}
}

// mergeConfigCache merges cache-files and cache-dirs from ConfigToml into
// BoothOutput.Cache and BoothOutput.CacheDirs, deduplicating against existing entries.
func mergeConfigCache(out *output.BoothOutput) {
	if out.Config == nil {
		return
	}

	// A cache entry reaches out.Config from two directions on a reconfigure: it
	// was read back out of the existing config.toml into flags, and it is also
	// in the "Configured by" header as a `--set cache-files=...`, which
	// applySetOverrides appends. Both are correct on their own; together they
	// write the entry twice, and the file grows another copy on every save.
	out.Config.CacheFiles = dedupeStrings(out.Config.CacheFiles)
	out.Config.CacheDirs = dedupeStrings(out.Config.CacheDirs)

	seen := make(map[string]bool, len(out.Cache))
	for _, f := range out.Cache {
		seen[f.RelPath] = true
	}
	for _, cf := range out.Config.CacheFiles {
		if !seen[cf] {
			seen[cf] = true
			out.Cache = append(out.Cache, output.FileContent{RelPath: cf})
		}
	}
	seenDirs := make(map[string]bool, len(out.CacheDirs))
	for _, d := range out.CacheDirs {
		seenDirs[d.RelPath] = true
	}
	for _, cd := range out.Config.CacheDirs {
		if !seenDirs[cd] {
			seenDirs[cd] = true
			out.CacheDirs = append(out.CacheDirs, output.FileContent{RelPath: cd})
		}
	}
}

// mergeConfigShared merges shared-files and shared-dirs from ConfigToml into
// BoothOutput.Shared and BoothOutput.SharedDirs (same double-source dedupe as cache).
func mergeConfigShared(out *output.BoothOutput) {
	if out.Config == nil {
		return
	}

	out.Config.SharedFiles = dedupeStrings(out.Config.SharedFiles)
	out.Config.SharedDirs = dedupeStrings(out.Config.SharedDirs)

	seen := make(map[string]bool, len(out.Shared))
	for _, f := range out.Shared {
		seen[f.RelPath] = true
	}
	for _, sf := range out.Config.SharedFiles {
		if !seen[sf] {
			seen[sf] = true
			out.Shared = append(out.Shared, output.FileContent{RelPath: sf})
		}
	}
	seenDirs := make(map[string]bool, len(out.SharedDirs))
	for _, d := range out.SharedDirs {
		seenDirs[d.RelPath] = true
	}
	for _, sd := range out.Config.SharedDirs {
		if !seenDirs[sd] {
			seenDirs[sd] = true
			out.SharedDirs = append(out.SharedDirs, output.FileContent{RelPath: sd})
		}
	}
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

// dedupeStrings returns the input with later duplicates removed, keeping the
// first occurrence so the original order survives.
func dedupeStrings(values []string) []string {
	if len(values) < 2 {
		return values
	}
	seen := make(map[string]bool, len(values))
	out := values[:0:0]
	for _, v := range values {
		if seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
	}
	return out
}
