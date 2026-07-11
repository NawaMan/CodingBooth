// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
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

// aptSnapshotID returns the Ubuntu archive snapshot id used to freeze `install apt`
// installs. `booth config` stamps the configuration date (UTC, day granularity) so
// that apt resolves against a frozen archive on every rebuild. CB_APT_SNAPSHOT
// overrides the computed value (used by tests and for pinning a specific snapshot).
func aptSnapshotID() string {
	if v := os.Getenv("CB_APT_SNAPSHOT"); v != "" {
		return v
	}
	return time.Now().UTC().Format("20060102") + "T000000Z"
}

// applyAptSnapshot freezes apt installs to the configuration date by prepending an
// `env APT_SNAPSHOT=<id>` directive to the generated Boothfile. apt--install.sh reads
// APT_SNAPSHOT and passes --snapshot to apt only when it is set; a hand-written
// Boothfile (not produced by `booth config`) has no such line, so apt resolves against
// the live archive. No-op when there is no Boothfile content to freeze, or when an
// APT_SNAPSHOT directive is already present.
func applyAptSnapshot(out *output.BoothOutput) {
	if out == nil || out.Boothfile == nil || out.Boothfile.Content == "" {
		return
	}
	if strings.Contains(out.Boothfile.Content, "APT_SNAPSHOT") {
		return
	}
	out.Boothfile.Content = "env APT_SNAPSHOT=" + aptSnapshotID() + "\n\n" + out.Boothfile.Content
}

// runConfigCLI handles non-interactive mode (--no-tui).
func runConfigCLI(version string, targetPath string, flags initFlags) {
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

	// Read back cache-files/cache-dirs from existing config.toml
	extractUserRunArgs(targetPath, &flags)

	var out *output.BoothOutput
	var resolved *selection.ResolvedSelection

	if len(flags.selectDSLs) == 0 {
		out, resolved = compileEmpty(flags)
	} else {
		templatesPath, cleanup := resolveTemplatesPath(flags, version)
		defer cleanup()
		flags.templatesPath = templatesPath
		out, resolved = compileSelection(flags, readExistingArgs(targetPath))
	}

	out.Command = buildConfigCommand(targetPath, flags)
	out.AdjustCommand = buildConfigAdjustCommand(flags)
	applyAptSnapshot(out)

	if flags.debug {
		printDebug(resolved, out)
	}

	if flags.dryrun {
		printDryrun(out)
		return
	}

	// Refuse to destroy hand-written content without explicit consent. This is a
	// stronger gate than the conflict prompt below, which only asks "does a file
	// exist?" — regenerating a file we wrote ourselves loses nothing.
	drifted := output.Drifted(targetPath)
	if len(drifted) > 0 && !flags.overwrite {
		printDriftRefusal(targetPath, drifted)
		os.Exit(1)
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

	if err := backupDrifted(targetPath, drifted); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
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

// printDriftRefusal explains which files hold content `booth config` did not write
// and why it is stopping, rather than clobbering them.
func printDriftRefusal(targetPath string, drifted []string) {
	boothDir := filepath.Join(targetPath, ".booth")
	fmt.Fprintf(os.Stderr, "Refusing to overwrite hand-written files in %s:\n\n", boothDir)
	for _, name := range drifted {
		fmt.Fprintf(os.Stderr, "  %s\n", name)
	}
	fmt.Fprintln(os.Stderr, "\nThese were not written by `booth config`, or were edited afterwards.")
	fmt.Fprintln(os.Stderr, "Reconfiguring regenerates them from scratch, so any hand-written")
	fmt.Fprintln(os.Stderr, "content in them would be lost.")
	fmt.Fprintln(os.Stderr, "\nRe-run with --overwrite to replace them (a .bak copy is kept).")
}

// backupDrifted saves a .bak of each hand-written file about to be replaced.
func backupDrifted(targetPath string, drifted []string) error {
	if len(drifted) == 0 {
		return nil
	}
	if err := output.BackupDrifted(targetPath, drifted); err != nil {
		return err
	}
	for _, name := range drifted {
		fmt.Fprintf(os.Stderr, "Backed up hand-written %s → %s.bak\n", name, name)
	}
	return nil
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

	// Build pre-selection from merged flags, overlaying preserved pins so the
	// TUI shows the real param values from the existing Boothfile.
	pre := buildPreSelection(registry, mergedFlags, readExistingArgs(targetPath))

	// Pre-populate booth version from target's lock file (falls back to binary version)
	pre.StringFields["booth-version"] = readLockFileVersion(targetPath, version)

	// Check if .booth directory is writable
	warning := checkBoothWritable(targetPath)

	// Files holding hand-written content. Saving regenerates them from scratch, so
	// the TUI demands a typed confirmation before it will destroy them.
	drifted := output.Drifted(targetPath)

	// Run TUI
	result, err := tui.RunConfig(registry, pre, warning, drifted)
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
		"egress":         "egress",
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

	// Apply list fields
	if v := result.ListFields["expose"]; len(v) > 0 {
		flags.exposes = v
	}
	if v := result.ListFields["env"]; len(v) > 0 {
		flags.envs = v
	}
	if v := result.ListFields["mount"]; len(v) > 0 {
		flags.mounts = v
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
		out, resolved = compileSelection(flags, readExistingArgs(targetPath))
	}

	out.Command = buildConfigCommand(targetPath, flags)
	out.AdjustCommand = buildConfigAdjustCommand(flags)
	applyAptSnapshot(out)

	if flags.dryrun {
		printDryrun(out)
		return
	}

	// The user typed the confirmation word to get here, so back up what we are
	// about to destroy, then overwrite.
	if err := backupDrifted(targetPath, drifted); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if err := output.WriteOutput(out, targetPath); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("\nInitialized .booth/ in %s\n", targetPath)
	printSummary(resolved)

	// Handle booth version update if changed
	oldLockVersion := readLockFileVersion(targetPath, "")
	if newVersion := result.StringFields["booth-version"]; newVersion != "" && newVersion != oldLockVersion {
		if err := updateBoothLockVersion(targetPath, newVersion); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to update booth version: %v\n", err)
		} else {
			fmt.Printf("\nBooth version updated to %s (will take effect on next run).\n", newVersion)
		}
	}

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
// and parses it into initFlags. Also reads config.toml to extract user-set run-args
// (long-form flags like --env, --publish, --volume) back into flags.
// Returns empty flags if no existing booth is found.
func readExistingBooth(targetPath string) initFlags {
	boothfilePath := filepath.Join(targetPath, ".booth", "Boothfile")
	f, err := os.Open(boothfilePath)
	if err != nil {
		return initFlags{}
	}
	defer f.Close()

	var flags initFlags

	scanner := bufio.NewScanner(f)
	linesRead := 0
	for scanner.Scan() && linesRead < 10 {
		line := scanner.Text()
		linesRead++

		if strings.HasPrefix(line, "# Configured by: ") {
			cmd := strings.TrimPrefix(line, "# Configured by: ")
			flags = parseAdjustCommand(cmd)
			break
		}
		if strings.HasPrefix(line, "# Configured by:") {
			cmd := strings.TrimPrefix(line, "# Configured by:")
			cmd = strings.TrimSpace(cmd)
			flags = parseAdjustCommand(cmd)
			break
		}
		// Legacy format: "# Adjust with :"
		if strings.HasPrefix(line, "# Adjust with : ") {
			cmd := strings.TrimPrefix(line, "# Adjust with : ")
			flags = parseAdjustCommand(cmd)
			break
		}
		if strings.HasPrefix(line, "# Adjust with :") {
			cmd := strings.TrimPrefix(line, "# Adjust with :")
			cmd = strings.TrimSpace(cmd)
			flags = parseAdjustCommand(cmd)
			break
		}
	}

	// Also read config.toml to extract user-set values from long-form run-args.
	// Long-form flags (--env, --publish, --volume) are user-set values;
	// short-form flags (-e, -p, -v) are template-contributed and left alone.
	extractUserRunArgs(targetPath, &flags)

	return flags
}

// extractUserRunArgs reads config.toml and extracts user-set run-args
// (long-form --env, --publish, --volume) and cache-files/cache-dirs back into initFlags.
func extractUserRunArgs(targetPath string, flags *initFlags) {
	configPath := filepath.Join(targetPath, ".booth", "config.toml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return
	}

	var cfg struct {
		RunArgs    []string `toml:"run-args"`
		CacheFiles []string `toml:"cache-files"`
		CacheDirs  []string `toml:"cache-dirs"`
	}
	if _, err := toml.Decode(string(data), &cfg); err != nil {
		return
	}

	// Preserve cache-files and cache-dirs from existing config.toml
	flags.cacheFiles = append(flags.cacheFiles, cfg.CacheFiles...)
	flags.cacheDirs = append(flags.cacheDirs, cfg.CacheDirs...)

	// Decompose long-form paired flags back into typed fields
	for i := 0; i < len(cfg.RunArgs); i++ {
		flag := cfg.RunArgs[i]
		if i+1 >= len(cfg.RunArgs) {
			break
		}
		value := cfg.RunArgs[i+1]
		switch flag {
		case "--env":
			if !sliceContains(flags.envs, value) {
				flags.envs = append(flags.envs, value)
			}
			i++
		case "--publish":
			// Reverse the expose expansion: PORT:PORT → PORT, +OFFSET:CONTAINER → +OFFSET
			expose := reverseExposeMapping(value)
			if !sliceContains(flags.exposes, expose) {
				flags.exposes = append(flags.exposes, expose)
			}
			i++
		case "--volume":
			if !sliceContains(flags.mounts, value) {
				flags.mounts = append(flags.mounts, value)
			}
			i++
		}
	}
}

// reverseExposeMapping converts a run-args port mapping back to the --expose form.
// "8080:8080" → "8080", "+8080:8080" → "+8080", otherwise kept as-is.
func reverseExposeMapping(mapping string) string {
	parts := strings.SplitN(mapping, ":", 2)
	if len(parts) == 2 && parts[0] == parts[1] {
		return parts[0]
	}
	if len(parts) == 2 && strings.HasPrefix(parts[0], "+") {
		offset := parts[0][1:]
		if offset == parts[1] {
			return parts[0]
		}
	}
	return mapping
}

func sliceContains(s []string, v string) bool {
	for _, item := range s {
		if item == v {
			return true
		}
	}
	return false
}

// parseAdjustCommand parses a command string like "booth config --no-tui --select go/python"
// or the legacy "booth config adjust --select go/python --variant codeserver" into initFlags.
func parseAdjustCommand(cmd string) initFlags {
	// Split into args, skipping command prefix words
	parts := strings.Fields(cmd)
	var args []string
	skip := 0
	for _, p := range parts {
		// Skip prefix: "booth config" or legacy "booth init [adjust|new]"
		if skip < 3 && (p == "booth" || p == "config" || p == "init" || p == "adjust" || p == "new") {
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

// buildPreSelection converts CLI flags into a TUI pre-selection. existingArgs
// (param name → value from an existing Boothfile's `arg` lines, may be nil) is
// overlaid onto the param fields so the TUI displays real pinned values rather
// than template defaults for anything the selection DSL didn't carry.
func buildPreSelection(registry *tmpl.TemplateRegistry, flags initFlags, existingArgs map[string]string) *tui.PreSelection {
	pre := &tui.PreSelection{
		SelectedTemplates: make(map[string]bool),
		SelectedExts:      make(map[string]map[string]bool),
		StringFields:      make(map[string]string),
		BoolFields:        make(map[string]bool),
		ListFields:        make(map[string][]string),
		ParamValues:       make(map[string]string),
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

	// Map CLI flags to TUI list fields
	if len(flags.exposes) > 0 {
		pre.ListFields["expose"] = flags.exposes
	}
	if len(flags.envs) > 0 {
		pre.ListFields["env"] = flags.envs
	}
	if len(flags.mounts) > 0 {
		pre.ListFields["mount"] = flags.mounts
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
		t, ok := registry.ByName[item.Name]
		if !ok {
			continue
		}
		pre.SelectedTemplates[item.Name] = true

		// Map positional params to named params for the template
		if len(item.Params) > 0 {
			mapPositionalParams(pre.ParamValues, item.Name, t, item.Params)
		}

		if len(item.Extensions) > 0 {
			if pre.SelectedExts[item.Name] == nil {
				pre.SelectedExts[item.Name] = make(map[string]bool)
			}
			for _, ext := range item.Extensions {
				pre.SelectedExts[item.Name][ext.Name] = true
				// Map positional params for extensions
				if len(ext.Params) > 0 {
					for _, tExt := range t.Extensions {
						if tExt.Name == ext.Name {
							extKey := item.Name + "/" + ext.Name
							mapPositionalParams(pre.ParamValues, extKey, tExt, ext.Params)
							break
						}
					}
				}
			}
		}

		// Auto-select extensions for pre-selected templates, respecting ~ excludes
		excludeSet := make(map[string]bool, len(item.Excludes))
		for _, ex := range item.Excludes {
			excludeSet[ex] = true
		}
		for _, ext := range t.Extensions {
			if ext.AutoSelect != nil && *ext.AutoSelect && !excludeSet[ext.Name] {
				if pre.SelectedExts[item.Name] == nil {
					pre.SelectedExts[item.Name] = make(map[string]bool)
				}
				pre.SelectedExts[item.Name][ext.Name] = true
			}
		}
	}

	// Overlay preserved pins from the existing Boothfile so pinned params display
	// their real value instead of the template default. Runs after selections are
	// known (including auto-selected extensions); only fills fields the DSL left
	// unset, so an explicit selection value still wins.
	for name := range pre.SelectedTemplates {
		t, ok := registry.ByName[name]
		if !ok {
			continue
		}
		overlayExistingArgs(pre.ParamValues, name, t, existingArgs)
		for extName := range pre.SelectedExts[name] {
			for _, ext := range t.Extensions {
				if ext.Name == extName {
					overlayExistingArgs(pre.ParamValues, name+"/"+extName, ext, existingArgs)
					break
				}
			}
		}
	}

	return pre
}

// overlayExistingArgs fills param fields (keyed "itemKey:PARAM") from existing
// Boothfile `arg` values, but only for non-default values not already set by the
// selection DSL — so the TUI shows a real pin (e.g. PLAYWRIGHT_VERSION=1.58.2)
// while explicit selection values and defaults are left untouched.
func overlayExistingArgs(paramValues map[string]string, itemKey string, t *tmpl.Template, existingArgs map[string]string) {
	for pname, p := range t.Params {
		key := itemKey + ":" + pname
		if _, set := paramValues[key]; set {
			continue
		}
		if v, ok := existingArgs[pname]; ok && v != p.Default {
			paramValues[key] = v
		}
	}
}

// mapPositionalParams maps positional param values to named param keys in the paramValues map.
// A trailing variadic param absorbs all remaining positional values (canonicalized:
// deduped + sorted), matching how the resolver assembles them — so re-opening a
// booth in the TUI shows the full, canonical package list rather than only the
// first value.
func mapPositionalParams(paramValues map[string]string, itemKey string, t *tmpl.Template, positional []string) {
	paramNames := t.ParamOrder
	if len(paramNames) == 0 {
		paramNames = make([]string, 0, len(t.Params))
		for name := range t.Params {
			paramNames = append(paramNames, name)
		}
		sort.Strings(paramNames)
	}
	lastIsVariadic := len(paramNames) > 0 && t.Params[paramNames[len(paramNames)-1]].Variadic
	for i, name := range paramNames {
		isLast := i == len(paramNames)-1
		if isLast && lastIsVariadic {
			if i < len(positional) {
				paramValues[itemKey+":"+name] = selection.CanonicalizeVariadic(positional[i:])
			}
		} else if i < len(positional) && positional[i] != "" {
			paramValues[itemKey+":"+name] = positional[i]
		}
	}
}

// readLockFileVersion reads the version from the target's .booth/tools/codingbooth.lock.
// Returns fallback if the lock file doesn't exist or can't be parsed.
func readLockFileVersion(targetPath string, fallback string) string {
	lockPath := filepath.Join(targetPath, ".booth", "tools", "codingbooth.lock")
	data, err := os.ReadFile(lockPath)
	if err != nil {
		return fallback
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "version=") {
			return strings.TrimPrefix(line, "version=")
		}
	}
	return fallback
}

// updateBoothLockVersion updates the version in .booth/tools/codingbooth.lock.
// The lock file format is key=value lines: version, downloaded_at, cache.
// If the lock file doesn't exist, it creates one with the new version.
func updateBoothLockVersion(targetPath string, newVersion string) error {
	lockDir := filepath.Join(targetPath, ".booth", "tools")
	lockPath := filepath.Join(lockDir, "codingbooth.lock")

	data, err := os.ReadFile(lockPath)
	if err != nil {
		// Lock file doesn't exist — create it
		if err := os.MkdirAll(lockDir, 0755); err != nil {
			return fmt.Errorf("cannot create tools directory: %w", err)
		}
		content := fmt.Sprintf("version=%s\ncache=shared\n", newVersion)
		return os.WriteFile(lockPath, []byte(content), 0644)
	}

	lines := strings.Split(string(data), "\n")
	found := false
	for i, line := range lines {
		if strings.HasPrefix(line, "version=") {
			lines[i] = "version=" + newVersion
			found = true
			break
		}
	}
	if !found {
		return fmt.Errorf("no version= line found in lock file")
	}

	return os.WriteFile(lockPath, []byte(strings.Join(lines, "\n")), 0644)
}

// checkBoothWritable checks whether the .booth directory (or its parent) is writable.
// Returns a warning message if not writable, or "" if writable.
func checkBoothWritable(targetPath string) string {
	boothDir := filepath.Join(targetPath, ".booth")

	// If .booth exists, check if it's writable
	info, err := os.Stat(boothDir)
	if err == nil {
		if !info.IsDir() {
			return fmt.Sprintf("%s exists but is not a directory. Configuration cannot be saved.", boothDir)
		}
		// Try writing a temp file to check writability
		f, err := os.CreateTemp(boothDir, ".write-test-*")
		if err != nil {
			absPath, _ := filepath.Abs(boothDir)
			return fmt.Sprintf("The .booth/ directory is not writable:\n  %s\n\nBy default, .booth/ is mounted read-only inside the container. Changes will not be saved.\n\nTo make it writable, restart with --writable-booth or set writable-booth = true in config.toml.", absPath)
		}
		f.Close()
		os.Remove(f.Name())
		return ""
	}

	// .booth doesn't exist — check if parent is writable (we'll need to create .booth)
	absTarget, _ := filepath.Abs(targetPath)
	parentInfo, err := os.Stat(absTarget)
	if err != nil {
		return fmt.Sprintf("Target directory does not exist:\n  %s\n\nConfiguration cannot be saved.", absTarget)
	}
	if !parentInfo.IsDir() {
		return fmt.Sprintf("Target path is not a directory:\n  %s\n\nConfiguration cannot be saved.", absTarget)
	}

	// Try creating and removing .booth to test writability
	err = os.Mkdir(boothDir, 0755)
	if err != nil {
		return fmt.Sprintf("Cannot create .booth/ directory in:\n  %s\n\nThe directory may be read-only. Changes will not be saved.\n\nIf running inside a booth, restart with --writable-booth or set writable-booth = true in config.toml.", absTarget)
	}
	os.Remove(boothDir)
	return ""
}

func printConfigHelp() {
	fmt.Println(`Usage: booth config [path] [flags]

Configure a CodingBooth environment. Opens an interactive TUI by default.
Use --no-tui for non-interactive CLI mode.

If the target path already contains a .booth/Boothfile, the existing
configuration is loaded as the baseline. CLI flags override the existing values.

Configuring regenerates .booth/Boothfile and .booth/config.toml from scratch. If
either holds hand-written content — never generated by booth config, or generated
and then edited — it is not overwritten without explicit consent: pass --overwrite
here, or type the confirmation word in the TUI. The replaced file is kept as
<name>.bak.

Flags:
  --select <selection>     Template selection DSL (repeatable)
  --no-tui                 Non-interactive CLI mode (requires --select)
  --dryrun                 Preview what would be generated without writing files
  --variant <variant>      Set variant (base, notebook, codeserver, xfce, kde)
  --port <port>            Set port (e.g., 10000, NEXT, RANDOM)
  --templates-path <dir>   Use local templates directory
  --version <ver>          Use templates from a specific release version
  --overwrite              Overwrite existing files without prompting, including
                           hand-written ones (--no-tui only)
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
  booth config                                  # TUI (empty)
  booth config --select go+linter               # TUI pre-populated
  booth config --no-tui --select go+linter      # CLI mode
  booth config --dryrun --select go              # TUI, dryrun on confirm
  booth config --no-tui --dryrun --select go     # CLI dryrun`)
}
