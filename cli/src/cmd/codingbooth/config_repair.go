// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
)

// `booth config repair [path]` makes a booth whose files were edited outside
// booth config count as generated again — the CLI form of the TUI's "edits made
// outside booth config" question, answered OK. It attempts and never forces:
//
//   - The edits read back with nothing to lift (the files are exactly what booth
//     config writes, only .booth/.generated disagrees): the fingerprint is
//     re-stamped. No file content changes.
//   - The edits read back as flags (an added env var, a changed port, …): the
//     guarded files (Boothfile, config.toml, owner-permission.yaml) are rewritten
//     with those flags recorded in the header, which reproduces the same
//     directives and settings. Nothing else in .booth/ is touched — setups,
//     startups and seeds are not re-copied.
//   - Anything else — edits that cannot be read back, comments a rewrite would
//     drop, a Boothfile booth config never wrote — is refused, nothing written,
//     with the reasons. Those are the cases that need --beside or --overwrite.
//
// `booth config validate [path]` is the same reading with nothing written: it
// exits 0 when .booth/ holds what booth config writes, and 1 when it does not,
// saying whether repair would fix it.

// repairMode says what repairBooth does with what it finds.
type repairMode int

const (
	repairWrite repairMode = iota // repair (or, with --dryrun, say what it would do)
	repairCheck                   // validate: report only; not generated is an error
)

// The flags each command takes. Anything a reconfigure takes beyond these would
// make it a reconfigure, which neither is.
var (
	repairFlags   = map[string]bool{"--dryrun": true, "--templates-path": true, "--into": true}
	validateFlags = map[string]bool{"--templates-path": true}
)

// errNotRepaired prefixes a refusal; nothing was written when it is returned.
var errNotRepaired = errors.New("Not repaired — nothing was written.")

// errNotValid prefixes a validate finding that repair cannot fix either.
var errNotValid = errors.New("Not valid, and booth config repair cannot fix it.")

// errInvalid is returned by a validate whose report is already written to w.
var errInvalid = errors.New("not valid")

func runConfigRepair(version string, args []string) {
	runRepairCommand(version, args, repairWrite)
}

func runConfigValidate(version string, args []string) {
	runRepairCommand(version, args, repairCheck)
}

func runRepairCommand(version string, args []string, mode repairMode) {
	name, allowed, what := "repair", repairFlags, "makes the existing files generated again"
	if mode == repairCheck {
		name, allowed, what = "validate", validateFlags, "checks the existing files"
	}

	targetPath := "."
	flagArgs := args
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		targetPath = args[0]
		flagArgs = args[1:]
	}
	into := ""
	var initArgs []string
	for i := 0; i < len(flagArgs); i++ {
		arg := flagArgs[i]
		if arg == "--into" && allowed[arg] {
			if i+1 >= len(flagArgs) || strings.HasPrefix(flagArgs[i+1], "-") {
				fmt.Fprintln(os.Stderr, "Error: --into needs a template name: booth config repair --into <name>")
				os.Exit(1)
			}
			i++
			into = flagArgs[i]
			continue
		}
		initArgs = append(initArgs, arg)
		switch {
		case arg == "--help" || arg == "-h":
			printConfigHelp()
			return
		case !allowed[arg]:
			fmt.Fprintf(os.Stderr, "Error: booth config %s does not take %s — it only %s.\n"+
				"To change the booth, run booth config (or booth config --no-tui with the flags).\n", name, arg, what)
			os.Exit(1)
		case arg == "--templates-path":
			if i+1 < len(flagArgs) {
				i++
				initArgs = append(initArgs, flagArgs[i])
			}
		}
	}

	err := repairBooth(os.Stdout, version, targetPath, parseInitFlags(initArgs), mode, into)
	if errors.Is(err, errInvalid) {
		os.Exit(1)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
}

// repairBooth repairs the booth at targetPath (see the file comment), reporting to
// w. A refusal is an error whose text is the whole message. In repairCheck mode
// nothing is written: a booth repair could fix is reported to w and returns
// errInvalid; one it could not returns the refusal, prefixed errNotValid.
//
// into names the project template --into moves lines no flag writes into; "" for
// none.
func repairBooth(w io.Writer, version, targetPath string, cli initFlags, mode repairMode, into string) error {
	check := mode == repairCheck
	refused := errNotRepaired
	if check {
		refused = errNotValid
	}

	// A selection with nothing to build (e.g. only shell-history) writes config.toml
	// alone, with no Boothfile — still a booth booth config wrote.
	boothDir := filepath.Join(targetPath, ".booth")
	if !fileExists(filepath.Join(boothDir, "Boothfile")) && !fileExists(filepath.Join(boothDir, "config.toml")) {
		return fmt.Errorf("Error: no booth configured in %s (no .booth/Boothfile or .booth/config.toml)", targetPath)
	}

	edited := output.Drifted(targetPath)
	if len(edited) == 0 {
		if check {
			fmt.Fprintln(w, "Valid: .booth/ holds what booth config wrote.")
		} else {
			fmt.Fprintln(w, "Nothing to repair: .booth/ holds what booth config wrote.")
		}
		return nil
	}
	files := ".booth/" + strings.Join(edited, ", .booth/")

	baseline := readBoothBaseline(version, targetPath, cli)
	adopt := baseline.adopt
	switch {
	case !adopt.attempted:
		return fmt.Errorf("%v\n%s %s not written by booth config (no \"# Configured by:\" header), so there is nothing to read the edits back against.\n"+
			"To generate it: booth config --no-tui --select <selection> --beside (keeps yours, writes <name>.new).",
			refused, files, isOrAre(edited))
	case !adopt.adopted && into != "" && !check:
		return repairInto(w, version, targetPath, into, files, baseline, cli)
	case !adopt.adopted:
		// Would moving the lines no flag writes into a template do it?
		probe, probeReasons := planInto(version, targetPath, intoProbeName, baseline, cli)
		if len(probeReasons) == 0 {
			if check {
				fmt.Fprintf(w, "Not valid: %s %s edited outside booth config, with lines no booth config flag writes.\n", files, isOrAre(edited))
				fmt.Fprintf(w, "booth config repair --into %s moves them into .booth/templates/%s.toml and selects it:\n", intoProbeName, intoProbeName)
				for _, line := range probe.describe() {
					fmt.Fprintf(w, "  %s\n", line)
				}
				return errInvalid
			}
		}

		var b strings.Builder
		fmt.Fprintf(&b, "%v\n%s %s edited outside booth config, and the edits cannot be read back:\n", refused, files, isOrAre(edited))
		for _, reason := range adopt.reasons {
			fmt.Fprintf(&b, "  - %s\n", reason)
		}
		if len(probeReasons) == 0 {
			fmt.Fprintf(&b, "No booth config flag writes those lines, but a project template can: booth config repair --into <name>\n"+
				"moves them into .booth/templates/<name>.toml and selects it (--dryrun shows it first).")
			return errors.New(b.String())
		}
		if intoWouldHelp(probe, probeReasons) {
			b.WriteString("Moving the lines no flag writes into a template (repair --into) does not fix it either:\n")
			for _, reason := range probeReasons {
				fmt.Fprintf(&b, "  - %s\n", reason)
			}
		}
		b.WriteString("Undo those edits, or run booth config to decide (--beside keeps yours; --overwrite replaces them, kept as <name>.bak).")
		return errors.New(b.String())
	case len(adopt.lost) > 0:
		return fmt.Errorf("%v\nThe edits in %s read back, but a rewrite would remove these comments:\n%s"+
			"Delete them or move them out of .booth/, then run repair again — or save in booth config, which asks first.",
			refused, files, lostCommentsText(adopt.lost))
	}

	if into != "" && !check {
		fmt.Fprintf(w, "Nothing to move into %s: the edits read back without a template.\n", into)
	}
	if adopt.unchanged {
		switch {
		case check:
			fmt.Fprintf(w, "Not valid: .booth/%s is stale for %s, which %s what booth config writes.\n"+
				"booth config repair re-stamps it; no file content changes.\n", output.ManifestName, files, matchVerb(edited))
			return errInvalid
		case cli.dryrun:
			fmt.Fprintf(w, "Would re-stamp .booth/%s for %s: %s what booth config writes.\n", output.ManifestName, files, matchVerb(edited))
			return nil
		}
		if err := output.RefreshManifest(targetPath, edited); err != nil {
			return fmt.Errorf("Error: %v", err)
		}
		fmt.Fprintf(w, "Repaired: %s %s what booth config writes; re-stamped .booth/%s.\n", files, matchVerb(edited), output.ManifestName)
		return nil
	}

	out, err := compileRepaired(version, targetPath, baseline.flags, cli)
	if err != nil {
		return fmt.Errorf("%v\n%v", refused, err)
	}

	switch {
	case check:
		fmt.Fprintf(w, "Not valid: %s %s edited outside booth config. The edits read back as:\n", files, isOrAre(edited))
	case cli.dryrun:
		fmt.Fprintf(w, "Would repair: the edits in %s read back as:\n", files)
	default:
		fmt.Fprintf(w, "Repaired: the edits in %s read back as:\n", files)
	}
	for _, change := range baseline.adoptedChanges {
		fmt.Fprintf(w, "  %s\n", change)
	}
	switch {
	case check:
		fmt.Fprintln(w, "booth config repair records them in the header; the rest of .booth/ is untouched.")
		return errInvalid
	case cli.dryrun:
		fmt.Fprintln(w, "They would be recorded in the header; the rest of .booth/ is untouched.")
		return nil
	}
	fmt.Fprintln(w, "They are recorded in the header; the rest of .booth/ is untouched.")

	if err := output.WriteGuarded(out, targetPath); err != nil {
		return fmt.Errorf("Error: %v", err)
	}
	if still := output.Drifted(targetPath); len(still) > 0 {
		return fmt.Errorf("Error: .booth/%s still differs from what booth config writes after the repair", strings.Join(still, ", .booth/"))
	}
	return nil
}

// compileRepaired compiles the booth with its edits lifted, against the catalog
// that wrote it (the one the edits were proven against), keeping its APT snapshot.
func compileRepaired(version, targetPath string, lifted, cli initFlags) (*output.BoothOutput, error) {
	flags := mergeFlags(lifted, initFlags{templatesPath: cli.templatesPath}, targetPath)
	if err := expandSelectFlags(&flags, targetPath); err != nil {
		return nil, err
	}
	if len(flags.selectDSLs) > 0 {
		templatesPath, cleanup, err := adoptTemplatesPath(version, targetPath, flags, cli)
		defer cleanup()
		if err != nil {
			return nil, err
		}
		flags.templatesPath = templatesPath
	}

	out, err := compileForAdopt(flags, targetPath)
	if err != nil {
		return nil, fmt.Errorf("the edits do not compile: %v", err)
	}
	out.Command = buildConfigCommand(targetPath, flags)
	out.AdjustCommand = buildConfigAdjustCommand(flags)
	out.TemplatesVersion = output.ReadTemplatesVersion(targetPath)
	return out, nil
}

func isOrAre(names []string) string {
	if len(names) == 1 {
		return "is"
	}
	return "are"
}

func matchVerb(names []string) string {
	if len(names) == 1 {
		return "already matches"
	}
	return "already match"
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// repairInto is repair --into: the edits that no flag writes move into the project
// template name, which joins the selection. Refused, with nothing written, unless
// the result is proven to read back.
func repairInto(w io.Writer, version, targetPath, name, files string, baseline boothBaseline, cli initFlags) error {
	plan, reasons := planInto(version, targetPath, name, baseline, cli)
	if len(reasons) > 0 {
		var b strings.Builder
		fmt.Fprintf(&b, "%v\nThe edits in %s cannot be moved into a template %s:\n", errNotRepaired, files, name)
		for _, reason := range reasons {
			fmt.Fprintf(&b, "  - %s\n", reason)
		}
		b.WriteString("Undo those edits, or run booth config to decide (--beside keeps yours; --overwrite replaces them, kept as <name>.bak).")
		return errors.New(b.String())
	}

	rel := filepath.Join(".booth", "templates", name+".toml")
	verb := "Repaired"
	if cli.dryrun {
		verb = "Would repair"
	}
	fmt.Fprintf(w, "%s: the lines in %s that no booth config flag writes move into %s, selected as %s:\n", verb, files, rel, name)
	for _, line := range plan.describe() {
		fmt.Fprintf(w, "  %s\n", line)
	}
	if changes := describeAdoptedChanges(plan.adopt, baseline.flags); len(changes) > 0 {
		fmt.Fprintln(w, "Recorded in the header:")
		for _, change := range changes {
			fmt.Fprintf(w, "  %s\n", change)
		}
	}
	if cli.dryrun {
		fmt.Fprintf(w, "\n%s would hold:\n", rel)
		for _, line := range strings.Split(strings.TrimRight(plan.template, "\n"), "\n") {
			fmt.Fprintf(w, "  | %s\n", line)
		}
		return nil
	}

	path := plan.templatePath(targetPath)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("Error: %v", err)
	}
	if err := os.WriteFile(path, []byte(plan.template), 0o644); err != nil {
		return fmt.Errorf("Error: %v", err)
	}
	out, err := compileRepaired(version, targetPath, plan.flags, cli)
	if err != nil {
		os.Remove(path)
		return fmt.Errorf("%v\n%v", errNotRepaired, err)
	}
	if err := output.WriteGuarded(out, targetPath); err != nil {
		return fmt.Errorf("Error: %v", err)
	}
	if still := output.Drifted(targetPath); len(still) > 0 {
		return fmt.Errorf("Error: .booth/%s still differs from what booth config writes after the repair", strings.Join(still, ", .booth/"))
	}
	return nil
}

// intoWouldHelp says whether a failed --into probe is worth reporting: it found
// lines it could move, and something else stopped it.
func intoWouldHelp(probe intoPlan, reasons []string) bool {
	return len(reasons) > 0 && (strings.Contains(strings.Join(reasons, "\n"), "can only add") || strings.Contains(strings.Join(reasons, "\n"), "reordered"))
}
