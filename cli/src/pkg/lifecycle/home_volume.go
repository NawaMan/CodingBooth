// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"flag"
	"fmt"
	"io"
	"os"
	"os/user"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// ListHomeVolume lists all CodingBooth home volumes.
func ListHomeVolume(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("home-volume-list", flag.ContinueOnError)
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	engine := resolveLifecycleEngine("")
	output, err := docker.DockerOutput(docker.DockerFlags{Silent: true, Engine: engine}, "volume", ilist.NewList(
		ilist.NewList("ls"),
		ilist.NewList("--filter", "label=cb.managed=true"),
		ilist.NewList("--format", "{{.Name}}\t{{.Labels}}"),
	))
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to list volumes: %v", err))
	}

	output = strings.TrimSpace(output)
	if output == "" {
		_, _ = fmt.Fprintln(stdout, "No home volumes found.")
		return nil
	}

	_, _ = fmt.Fprintf(stdout, "%-40s  %s\n", "VOLUME", "PARENT")
	_, _ = fmt.Fprintf(stdout, "%-40s  %s\n", "------", "------")
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		volName := parts[0]
		if !strings.HasPrefix(volName, "cb-home-") {
			continue
		}
		parent := ""
		if len(parts) > 1 {
			for _, label := range strings.Split(parts[1], ",") {
				label = strings.TrimSpace(label)
				if strings.HasPrefix(label, "cb.parent=") {
					parent = strings.TrimPrefix(label, "cb.parent=")
				}
			}
		}
		_, _ = fmt.Fprintf(stdout, "%-40s  %s\n", volName, parent)
	}
	return nil
}

// exportUserNamespaceArgs keeps the host UID inside the export helper container
// under rootless Podman. Without it, --user <host uid> is an unprivileged
// subordinate UID on the host and cannot write the backup directory (or read the
// volume, which the booth's keep-id `coder` owns as the host user).
func exportUserNamespaceArgs(engine string, euid int) []string {
	if engine != "podman" || euid == 0 {
		return nil
	}
	return []string{"--userns=keep-id"}
}

// ExportHomeVolume exports a home volume to a tar.gz file.
func ExportHomeVolume(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("home-volume-export", flag.ContinueOnError)
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	positional := flagSet.Args()
	if len(positional) < 2 {
		return commandExit(1, "Usage: booth home-volume-export <container-name> <output-file>\n\nExports the home volume for a booth to a tar.gz file.")
	}

	containerName := positional[0]
	outputFile := positional[1]
	volName := "cb-home-" + containerName
	engine := resolveLifecycleEngine("")

	// Verify volume exists
	if _, err := docker.DockerOutput(docker.DockerFlags{Silent: true, Engine: engine}, "volume", ilist.NewList(
		ilist.NewList("inspect", volName),
	)); err != nil {
		return commandExit(1, fmt.Sprintf("Error: home volume %q not found. Is --persist-home enabled for %q?", volName, containerName))
	}

	absOutput, err := filepath.Abs(outputFile)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: invalid output path: %v", err))
	}
	dir := filepath.Dir(absOutput)
	base := filepath.Base(absOutput)

	_, _ = fmt.Fprintf(stdout, "Exporting %s to %s ...\n", volName, absOutput)

	// Run as host user so the output file has correct ownership
	u, _ := user.Current()
	userFlag := u.Uid + ":" + u.Gid

	runArgs := []ilist.List[string]{ilist.NewList("--rm")}
	if keepID := exportUserNamespaceArgs(engine, os.Geteuid()); len(keepID) > 0 {
		runArgs = append(runArgs, ilist.NewListFromSlice(keepID))
	}
	runArgs = append(runArgs,
		ilist.NewList("-v", volName+":/data:ro"),
		ilist.NewList("-v", dir+":/backup"),
		ilist.NewList("--user", userFlag),
		ilist.NewList("alpine"),
		ilist.NewList("tar", "czf", "/backup/"+base, "-C", "/data", "."),
	)
	err = docker.Docker(docker.DockerFlags{Silent: false, Engine: engine}, "run", ilist.NewListFromSlice(runArgs))
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to export volume: %v", err))
	}

	_, _ = fmt.Fprintf(stdout, "Exported %s to %s\n", volName, absOutput)
	return nil
}

// ImportHomeVolume imports a tar.gz file into a home volume.
func ImportHomeVolume(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("home-volume-import", flag.ContinueOnError)
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	positional := flagSet.Args()
	if len(positional) < 2 {
		return commandExit(1, "Usage: booth home-volume-import <container-name> <input-file>\n\nImports a tar.gz file into the home volume for a booth.")
	}

	containerName := positional[0]
	inputFile := positional[1]
	volName := "cb-home-" + containerName
	engine := resolveLifecycleEngine("")

	// Create volume if it doesn't exist (idempotent)
	_ = docker.Docker(docker.DockerFlags{Silent: true, Engine: engine}, "volume", ilist.NewList(
		ilist.NewList("create"),
		ilist.NewList("--label", "cb.managed=true"),
		ilist.NewList("--label", "cb.parent="+containerName),
		ilist.NewList(volName),
	))

	absInput, err := filepath.Abs(inputFile)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: invalid input path: %v", err))
	}
	dir := filepath.Dir(absInput)
	base := filepath.Base(absInput)

	_, _ = fmt.Fprintf(stdout, "Importing %s into %s ...\n", absInput, volName)

	err = docker.Docker(docker.DockerFlags{Silent: false, Engine: engine}, "run", ilist.NewList(
		ilist.NewList("--rm"),
		ilist.NewList("-v", volName+":/data"),
		ilist.NewList("-v", dir+":/backup:ro"),
		ilist.NewList("alpine"),
		ilist.NewList("tar", "xzf", "/backup/"+base, "-C", "/data"),
	))
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to import volume: %v", err))
	}

	_, _ = fmt.Fprintf(stdout, "Imported %s into %s\n", absInput, volName)
	return nil
}
