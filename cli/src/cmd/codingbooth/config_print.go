// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// `booth config print [path]` lists what a booth is configured with — the
// template-and-extension summary a save prints at the end — without opening the
// TUI or writing anything. The selection is read the way a reconfigure reads it:
// the header, with edits made outside booth config read back on top when they can
// be, and the Boothfile's param pins (arg lines) applied. Flags a reconfigure
// takes apply too, so `booth config print --add-select go+lsp` shows what that
// change would give before making it.
func runConfigPrint(version string, args []string) {
	targetPath := "."
	flagArgs := args
	if len(args) > 0 && !strings.HasPrefix(args[0], "--") {
		targetPath = args[0]
		flagArgs = args[1:]
	}
	if len(flagArgs) > 0 && (flagArgs[0] == "--help" || flagArgs[0] == "-h") {
		printConfigHelp()
		return
	}

	if err := printBoothSelection(os.Stdout, os.Stderr, version, targetPath, parseInitFlags(flagArgs)); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// printBoothSelection writes the summary of the booth at targetPath to out, and
// notes about how it was read to notes.
func printBoothSelection(out, notes io.Writer, version, targetPath string, cli initFlags) error {
	if _, _, found := readBoothHeader(targetPath); !found {
		if _, err := os.Stat(filepath.Join(targetPath, ".booth", "Boothfile")); err != nil {
			return fmt.Errorf("no booth configured in %s (no .booth/Boothfile)", targetPath)
		}
		return fmt.Errorf("%s has no \"# Configured by:\" header, so there is no selection to print — it was not written by booth config", filepath.Join(targetPath, ".booth", "Boothfile"))
	}

	baseline := readBoothBaseline(version, targetPath, cli)
	if len(baseline.drifted) > 0 {
		fmt.Fprintf(notes, "Note: .booth/%s edited outside booth config and could not be read back; this is the selection its header records.\n",
			strings.Join(baseline.drifted, ", .booth/"))
	}

	flags := mergeFlags(baseline.flags, cli, targetPath)
	if err := expandSelectFlags(&flags, targetPath); err != nil {
		return fmt.Errorf("%v", err)
	}
	if len(flags.selectDSLs) == 0 {
		fmt.Fprintln(out, "No templates selected.")
		return nil
	}

	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()
	flags.templatesPath = templatesPath
	_, resolved, err := compileSelectionE(flags, targetPath, readExistingArgs(targetPath))
	if err != nil {
		return err
	}

	var b bytes.Buffer
	writeSummary(&b, resolved)
	_, err = out.Write(bytes.TrimRight(b.Bytes(), "\n"))
	if err == nil {
		_, err = fmt.Fprintln(out)
	}
	return err
}
