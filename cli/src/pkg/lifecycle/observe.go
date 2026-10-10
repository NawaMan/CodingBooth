// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// Observe runs a native inspection command against a booth-managed container.
func Observe(command string, args []string, stdout, stderr io.Writer) error {
	flagSet := flag.NewFlagSet(command, flag.ContinueOnError)
	flagSet.SetOutput(stderr)
	engine := engineFlag(flagSet)
	name := flagSet.String("name", "", "Booth name")
	code := flagSet.String("code", "", "Code path used to find the booth")
	var format string
	var noStream bool
	var psArgs []string
	state := stateAny
	switch command {
	case "inspect":
		flagSet.Bool("json", false, "Print the complete engine-native JSON document (the default)")
		flagSet.StringVar(&format, "format", "", "Engine-native output format (Docker and Podman only)")
		flagSet.StringVar(&format, "f", "", "Alias for --format")
	case "stats":
		state = stateRunning
		flagSet.BoolVar(&noStream, "no-stream", false, "Print one sample and exit")
		flagSet.StringVar(&format, "format", "", "Engine-native output format")
	case "top":
		state = stateRunning
		args, psArgs = splitAtSeparator(args)
	case "diff", "wait":
	default:
		return commandExit(2, fmt.Sprintf("Error: unknown inspection command %q.", command))
	}
	if err := parseLifecycleFlags(flagSet, args); err != nil {
		if err == flag.ErrHelp {
			return nil
		}
		return commandExit(2, "")
	}
	if command == "inspect" && format != "" && flagSet.Lookup("json").Value.String() == "true" {
		return commandExit(2, "Error: use either --json or --format, not both.")
	}
	target, err := queryTarget(*name, *code, *engine, flagSet.Args(), state, stderr)
	if err != nil {
		return err
	}
	if target.Engine == docker.EngineApple {
		if command == "top" || command == "diff" || command == "wait" {
			return commandExit(1, fmt.Sprintf("Error: booth %s is not supported on engine apple: Apple container has no native %s command.", command, command))
		}
		if command == "inspect" && format != "" {
			return commandExit(1, "Error: --format for inspect is not supported on engine apple; use the default JSON output.")
		}
	}
	var nativeArgs []string
	if noStream {
		nativeArgs = append(nativeArgs, "--no-stream")
	}
	if format != "" {
		nativeArgs = append(nativeArgs, "--format", format)
	}
	nativeArgs = append(nativeArgs, target.Name)
	nativeArgs = append(nativeArgs, psArgs...)
	if err := docker.Native(target.Engine, command, nativeArgs, os.Stdin, stdout, stderr); err != nil {
		return forwardExitCode(command, target.Name, err)
	}
	return nil
}
