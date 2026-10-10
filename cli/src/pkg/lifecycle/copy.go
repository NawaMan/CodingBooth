// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"flag"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// Copy transfers one file, directory, or tar stream between host and booth.
func Copy(args []string, stdout, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("cp", flag.ContinueOnError)
	flagSet.SetOutput(stderr)
	engine := engineFlag(flagSet)
	name := flagSet.String("name", "", "Booth name for the :PATH endpoint")
	code := flagSet.String("code", "", "Code path used to find the booth")
	if err := parseLifecycleFlags(flagSet, args); err != nil {
		if err == flag.ErrHelp {
			return nil
		}
		return commandExit(2, "")
	}
	if flagSet.NArg() != 2 {
		return commandExit(2, "Usage: booth cp [--name NAME | --code PATH] [--engine ENGINE] SOURCE DESTINATION\nExactly one path must be :PATH or NAME:PATH inside a booth.")
	}
	source, err := parseCopyEndpoint(flagSet.Arg(0))
	if err != nil {
		return commandExit(2, "Error: "+err.Error())
	}
	destination, err := parseCopyEndpoint(flagSet.Arg(1))
	if err != nil {
		return commandExit(2, "Error: "+err.Error())
	}
	if source.booth == destination.booth {
		return commandExit(2, "Error: exactly one copy path must be inside a booth (:PATH or NAME:PATH).")
	}
	remote, local := source, destination
	if destination.booth {
		remote, local = destination, source
	}
	if remote.name != "" {
		if *name != "" && *name != remote.name {
			return commandExit(2, "Error: --name conflicts with the booth name in the copy path.")
		}
		*name = remote.name
	}
	target, err := queryTarget(*name, *code, *engine, nil, stateAny, stderr)
	if err != nil {
		return err
	}
	if target.Engine == docker.EngineApple {
		if target.State != stateRunning {
			return commandExit(1, "Error: copying on engine apple requires a running booth; start it first.")
		}
		if local.path == "-" {
			return commandExit(1, "Error: tar streams ('-') are not supported by booth cp on engine apple.")
		}
	}
	// Preserve trailing '/' and '/.' because native cp gives them meaning.
	// Prefixing a relative host path also prevents an operand such as '-q' from
	// becoming an engine flag after the user protected it with '--'.
	localPath := local.path
	if localPath != "-" && !filepath.IsAbs(localPath) && !strings.HasPrefix(localPath, "."+string(filepath.Separator)) {
		localPath = "." + string(filepath.Separator) + localPath
	}
	remotePath := remote.path
	if !strings.HasPrefix(remotePath, "/") {
		remotePath = "/" + remotePath
	}
	remotePath = target.Name + ":" + remotePath
	nativeArgs := []string{localPath, remotePath}
	if source.booth {
		nativeArgs = []string{remotePath, localPath}
	}
	if err := docker.Native(target.Engine, "cp", nativeArgs, os.Stdin, stdout, stderr); err != nil {
		return forwardExitCode("copy files", target.Name, err)
	}
	return nil
}
