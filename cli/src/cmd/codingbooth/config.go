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
	"strconv"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
	"github.com/nawaman/codingbooth/src/pkg/appctx"
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

	// Check what was typed on the command line before doing anything with it.
	// These settings are only consumed at the far end of the pipeline, so without
	// this a mistyped --set in TUI mode surfaces after the whole booth has been
	// configured and saved — the one moment the answer is least welcome.
	if _, err := parseSetOverrides(flags.sets); err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing --set: %v\n", err)
		os.Exit(1)
	}

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
	// The existing .booth/ is the baseline and this invocation's flags override
	// it — the same contract the TUI path uses. Without reading the header back,
	// a reconfigure that did not restate --select would regenerate an empty
	// booth, dropping the whole recorded selection while the run-args (which are
	// recovered from config.toml) survived — a silent, lopsided wipe.
	//
	// readExistingBooth also pulls run-args and cache entries out of config.toml.
	flags = mergeFlags(readExistingBooth(targetPath), flags)
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

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
	if len(drifted) > 0 && !flags.overwrite && !flags.beside {
		printDriftRefusal(targetPath, drifted)
		os.Exit(1)
	}

	// --beside: keep the user's files, write the generated content as <name>.new.
	if len(drifted) > 0 && flags.beside && !flags.overwrite {
		if err := output.WriteOutputBeside(out, targetPath, drifted); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		printBesideResult(targetPath, drifted)
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
// and why it is stopping, rather than clobbering them — then names both ways out.
func printDriftRefusal(targetPath string, drifted []string) {
	boothDir := filepath.Join(targetPath, ".booth")
	fmt.Fprintf(os.Stderr, "Refusing to overwrite hand-written files in %s:\n\n", boothDir)
	for _, name := range drifted {
		fmt.Fprintf(os.Stderr, "  %s\n", name)
	}
	fmt.Fprintln(os.Stderr, "\nThese were not written by `booth config`, or were edited afterwards.")
	fmt.Fprintln(os.Stderr, "Reconfiguring regenerates them from scratch, so any hand-written")
	fmt.Fprintln(os.Stderr, "content in them would be lost. Re-run with:")
	fmt.Fprintln(os.Stderr, "\n  --beside     keep them, write the generated content as <name>.new to merge")
	fmt.Fprintln(os.Stderr, "  --overwrite  replace them (the replaced file is kept as <name>.bak)")
}

// handWrittenNotice is the heads-up shown when the config TUI opens on a booth that
// holds files `booth config` did not write. It is deliberately not a blocker: the
// user may well be here to look around, and nothing is decided until they save. It
// exists so that nobody configures an entire booth before discovering that the
// result cannot simply be written over what they have.
func handWrittenNotice(drifted []string) string {
	if len(drifted) == 0 {
		return ""
	}

	var b strings.Builder
	b.WriteString("This booth contains hand-written files:\n\n")
	for _, name := range drifted {
		b.WriteString("  .booth/" + name + "\n")
	}
	b.WriteString("\nThese were not written by booth config, or were edited afterwards. ")
	b.WriteString("Configuring regenerates them from your selection, so they cannot simply ")
	b.WriteString("be written over.\n\n")
	b.WriteString("Nothing is decided yet. When you save, you choose: keep yours and have the ")
	b.WriteString("generated content written beside them as .new files to merge, or replace ")
	b.WriteString("them (the originals are kept as .bak).\n\n")
	b.WriteString("Go on in and look around — nothing is touched until you save.")
	return b.String()
}

// joinWarnings combines the startup warnings that apply, dropping the ones that
// don't, so the dialog shows every relevant one rather than only the first.
func joinWarnings(warnings ...string) string {
	var present []string
	for _, w := range warnings {
		if w != "" {
			present = append(present, w)
		}
	}
	return strings.Join(present, "\n\n")
}

// printBesideResult tells the user what landed and what is left for them to do.
// The reconfigure is deliberately incomplete: the generated content is on disk, but
// only they can decide how it combines with what they wrote.
func printBesideResult(targetPath string, drifted []string) {
	boothDir := filepath.Join(targetPath, ".booth")
	fmt.Printf("Kept your hand-written files in %s and wrote the generated content beside them:\n\n", boothDir)
	for _, name := range drifted {
		fmt.Printf("  %s.new\n", name)
	}
	fmt.Println("\nNothing of yours was changed. Merge each .new file into its original to")
	fmt.Println("finish, then delete it. To see what would change:")
	fmt.Println()
	for _, name := range drifted {
		fmt.Printf("  diff %s %s.new\n", filepath.Join(boothDir, name), filepath.Join(boothDir, name))
	}
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

	// Files holding hand-written content. Saving regenerates them from scratch, so
	// the TUI makes the user choose before it will touch them.
	drifted := output.Drifted(targetPath)

	// Say so up front, before any time is invested. Learning only at save time that
	// your Boothfile can't simply be written out means having configured the whole
	// booth without knowing the result was in question.
	warning := joinWarnings(checkBoothWritable(targetPath), handWrittenNotice(drifted))

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

	// The merged baseline — not the bare CLI flags — is what this run writes out.
	//
	// Saving regenerates config.toml from scratch, so anything not carried into
	// `flags` here is deleted from the booth. The TUI only renders a subset of the
	// settings a booth can hold, so re-deriving the whole file from its result drops
	// every other one: --cmd, cache entries, and any --set key without a field
	// (timezone, persist-home, idle-time, ...) vanished on a save that changed
	// nothing.
	//
	// The TUI speaks for exactly the keys it renders. Those are stripped from the
	// baseline and re-derived from the result below — so unchecking a box still
	// removes the key — and everything else is carried through untouched.
	flags = mergedFlags
	flags.sets = dropTUIOwnedSets(mergedFlags.sets)

	// Apply TUI results back to flags. These are assigned unconditionally rather
	// than only-when-non-empty: the TUI was pre-populated from this same baseline,
	// so an empty value means the user cleared the field, not that the TUI had
	// nothing to say. Skipping the assignment would make a cleared field
	// un-clearable — the baseline would simply reappear.
	flags.selectDSL = result.SelectDSL
	flags.selectDSLs = nil
	if result.SelectDSL != "" {
		flags.selectDSLs = []string{result.SelectDSL}
	}

	// Apply string fields
	flags.variant = result.StringFields["variant"]
	flags.port = result.StringFields["port"]
	flags.version = result.StringFields["version"]

	// Apply list fields
	flags.exposes = result.ListFields["expose"]
	flags.envs = result.ListFields["env"]
	flags.mounts = result.ListFields["mount"]

	// The TUI's Debug box steers this run, like --debug does; it is not a booth
	// setting and has no config.toml key. It used to be written out as one, which
	// produced a `debug = true` line nothing has ever read.
	if result.BoolFields["debug"] {
		flags.debug = true
	}

	// Apply bool fields as --set overrides
	for _, key := range tuiBoolSetKeys {
		if result.BoolFields[key] {
			flags.sets = append(flags.sets, key)
		}
	}

	// Apply string fields as --set overrides. "sudo" rides along here as a
	// tri-state cycle field: "" (default/omit), "true", "false".
	for _, key := range tuiStringSetKeys {
		if v := result.StringFields[key]; v != "" {
			flags.sets = append(flags.sets, key+"="+v)
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

	if flags.debug {
		printDebug(resolved, out)
	}

	if flags.dryrun {
		printDryrun(out)
		return
	}

	if result.SaveBeside {
		// The user kept their hand-written files: write what we generated alongside
		// as <name>.new and leave theirs untouched, to merge by hand.
		if err := output.WriteOutputBeside(out, targetPath, drifted); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		printBesideResult(targetPath, drifted)
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

// tuiBoolSetKeys and tuiStringSetKeys are the config.toml keys the config TUI
// renders as fields, and so the keys its result speaks for. A save strips exactly
// these from the baseline and re-derives them from the TUI result; every other key
// the booth holds is carried through untouched, because the TUI never showed it and
// therefore has no opinion about it.
//
// Keep these in step with allConfigFields in pkg/boothinit/tui/configfields.go. A key
// listed here but not rendered can never be set again once cleared; a key rendered
// but not listed cannot be turned off, since the baseline's copy would survive the
// strip and be written back out.
var (
	tuiBoolSetKeys = []string{
		"dind",
		"keep-alive",
		"daemon",
		"writable-booth",
		"egress",
		"silence-build",
		"pull",
		"strict",
		"verbose",
		"dryrun",
	}

	// "sudo" is a tri-state cycle field ("" / "true" / "false"), so it is carried as
	// a string rather than a bool — see triStateSetKeys.
	tuiStringSetKeys = []string{
		"name",
		"image",
		"startup",
		"env-file",
		"sudo",
	}

	// triStateSetKeys are rendered as cycle fields, which the TUI reads from and
	// writes to StringFields. A --set value for one of these arrives as a Go bool
	// and has to be spelled back out as a string, or the cycle field comes up empty
	// — and empty means "default", which for sudo is *enabled*. An explicit
	// `--set sudo=false` would silently turn back into passwordless sudo.
	triStateSetKeys = map[string]bool{"sudo": true}
)

// dropTUIOwnedSets removes the --set entries the TUI is authoritative for, leaving
// the ones it does not render. The result is the part of the baseline that a save
// must preserve verbatim.
func dropTUIOwnedSets(sets []string) []string {
	owned := make(map[string]bool, len(tuiBoolSetKeys)+len(tuiStringSetKeys))
	for _, key := range tuiBoolSetKeys {
		owned[key] = true
	}
	for _, key := range tuiStringSetKeys {
		owned[key] = true
	}

	var kept []string
	for _, set := range sets {
		key := set
		if idx := strings.Index(set, "="); idx >= 0 {
			key = set[:idx]
		}
		if owned[key] {
			continue
		}
		kept = append(kept, set)
	}
	return kept
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

	// Settings recorded in the header are history, not intent. A key this booth
	// records may no longer be one booth reads — `--set debug` was written by the
	// config TUI for as long as it treated debug as a config value — and refusing
	// the whole run over it would leave an existing booth impossible to
	// reconfigure. A key typed on the command line right now is different: that is
	// someone's intent, and a typo there is still refused outright.
	flags.sets = dropUnknownSets(flags.sets, boothfilePath)

	return flags
}

// dropUnknownSets removes --set entries whose key booth no longer reads, saying
// so once per key. Applied only to settings recovered from an existing booth.
func dropUnknownSets(sets []string, source string) []string {
	if len(sets) == 0 {
		return sets
	}

	schema := appctx.ConfigKeys()
	kept := make([]string, 0, len(sets))
	for _, set := range sets {
		key, _, _ := strings.Cut(set, "=")

		// Dropped on two counts: the key is not one booth knows at all, or it is
		// known but never read back from a file (public, tls-cert, tls-key). The
		// config TUI offered those three until it was found they take no effect,
		// so booths configured before that still record them. Keeping them would
		// re-emit a line booth ignores, on every reconfigure, forever.
		spec, known := schema[key]
		if known && spec.Read {
			kept = append(kept, set)
			continue
		}
		fmt.Fprintf(os.Stderr,
			"Note: ignoring %q recorded in %s — booth does not read that from config.toml.\n",
			key, source)
	}
	return kept
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
//
// `existing` is parsed from a header that reads "booth config --no-tui
// --overwrite ...", so it carries flags describing the run that *wrote* the
// file. Those say nothing about what this run should do — inheriting them would
// make every subsequent run an overwriting one — so the flags that steer this
// invocation are taken from the CLI alone.
func mergeFlags(existing, cli initFlags) initFlags {
	merged := existing

	merged.noTUI = cli.noTUI
	merged.overwrite = cli.overwrite
	merged.beside = cli.beside
	merged.dryrun = cli.dryrun
	merged.start = cli.start
	merged.full = cli.full
	merged.detail = cli.detail
	merged.debug = cli.debug

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
					// A tri-state field reads its value from StringFields, so a
					// bool has to be spelled out to reach it at all.
					if triStateSetKeys[k] {
						pre.StringFields[k] = strconv.FormatBool(val)
						continue
					}
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
//
// A default that follows another param ("${SSH_PORT}") reaches the Boothfile as the
// value it resolved to, so it cannot be recognised as a default by string comparison.
// Resolving it against the Boothfile's own args reconstructs what it resolved to *then*:
// a value that matches is derived, and must be left to re-derive from the new selection
// rather than be frozen as a pin. Without this, moving a service port would leave the
// published host port behind on the port the service used to listen on.
func overlayExistingArgs(paramValues map[string]string, itemKey string, t *tmpl.Template, existingArgs map[string]string) {
	for pname, p := range t.Params {
		key := itemKey + ":" + pname
		if _, set := paramValues[key]; set {
			continue
		}
		wasDefault := tmpl.ExpandRefs(p.Default, existingArgs)
		if v, ok := existingArgs[pname]; ok && v != wasDefault {
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
and then edited — it is not overwritten without explicit consent. You get two
choices, in the TUI on save or here as flags:

  keep it      the generated content is written beside yours as <name>.new, which
               you merge by hand (--beside, or Enter in the TUI). Nothing is lost.
  replace it   yours is replaced, and kept as <name>.bak (--overwrite, or type the
               confirmation word in the TUI).

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
  --beside                 Keep hand-written files; write the generated content
                           as <name>.new for you to merge (--no-tui only)
  --start                  Start the booth after creation
  --debug                  Print debug output
  --cmd <command>          Set default start command (repeatable)
  --expose <port>          Publish an extra port (repeatable). Forms: PORT,
                           HOST:CONTAINER, IP:HOST:CONTAINER, +OFFSET:CONTAINER
                           (host = booth port + OFFSET), or host-side env form
                           ${NAME} / ${NAME:-digits}[:CONTAINER]. The fallback may
                           itself be booth-relative: ${NAME:-+OFFSET}:CONTAINER
                           publishes on boothPort+OFFSET when NAME is unset. All
                           expanded at booth start. This ADDS a mapping; to move a
                           port a selected template already publishes, give its
                           expose extension the host port: +expose:19000,
                           +expose:+9000, or +expose:${APP_PORT:-19000}
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
  booth config --no-tui --dryrun --select go     # CLI dryrun

  booth config --select cloudbeaver+expose            # publish it on 8978
  booth config --select cloudbeaver+expose:19000      # ...on 19000 instead
  booth config --select rabbitmq+start+expose:+4567   # ...on booth port + 4567`)
}
