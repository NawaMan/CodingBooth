// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/lifecyclelog"
)

// lifecycleService is the name `booth logs lifecycle` takes. Unlike the other
// services it is not in the booth's /tmp but on the host, in the code folder's
// .booth/.tmp/ (see package lifecyclelog) — so it is read even for a booth that
// is stopped, or removed and gone from `booth list`.
const lifecycleService = "lifecycle"

// lifecycleFollowInterval is how often `booth logs -f lifecycle` checks the file.
const lifecycleFollowInterval = 500 * time.Millisecond

// wantsLifecycleLog reports whether the command asks for the lifecycle log, and
// rejects mixing it with in-booth services: those are read through the engine,
// this one from the host, and one command does one or the other.
func wantsLifecycleLog(opts logsOptions) (bool, error) {
	found := false
	for _, service := range opts.services {
		if service == lifecycleService {
			found = true
		}
	}
	if found && len(opts.services) > 1 {
		return false, commandExit(1, "Error: the lifecycle log is read from the host, not the booth; ask for it on its own: booth logs lifecycle")
	}
	return found, nil
}

// lifecycleLogCodePath is the code folder whose lifecycle log to read: --code
// when given; the named booth's folder for --name; otherwise the current folder.
// Neither --code nor the default needs the booth to still exist. Pure for unit
// tests.
func lifecycleLogCodePath(opts logsOptions, containers []managedContainer, cwd string) (string, error) {
	if opts.code != "" {
		return normalizeCodePath(opts.code), nil
	}
	if opts.name != "" {
		if err := ambiguousEngineError(containers, opts.name); err != nil {
			return "", err
		}
		container, found := findByName(containers, opts.name)
		if !found {
			return "", fmt.Errorf("Error: booth %q not found. For a booth already removed, give its folder: booth logs --code <path> lifecycle", opts.name)
		}
		if container.CodePath == "" {
			return "", fmt.Errorf("Error: booth %q does not record its code folder; give it: booth logs --code <path> lifecycle", opts.name)
		}
		return container.CodePath, nil
	}
	return cwd, nil
}

// showLifecycleLog prints (or follows) the lifecycle log of the booth opts names.
func showLifecycleLog(opts logsOptions, stdout io.Writer, stderr io.Writer) error {
	var containers []managedContainer
	if opts.name != "" {
		var err error
		containers, err = managedContainersAcross(resolveLifecycleEngines(""), false, stderr)
		if err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
		}
	}
	cwd, err := os.Getwd()
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: cannot read the current folder: %v", err))
	}
	codePath, err := lifecycleLogCodePath(opts, containers, cwd)
	if err != nil {
		return commandExit(1, err.Error())
	}

	path := lifecyclelog.Path(codePath)
	content, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) && !opts.follow {
		return commandExit(1, fmt.Sprintf("No lifecycle log at %s yet: nothing has been recorded for the booth of %s.", path, codePath))
	}
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return commandExit(1, fmt.Sprintf("Error: failed to read %s: %v", path, err))
	}
	_, _ = stdout.Write(lastLines(content, opts.tail))
	if !opts.follow {
		return nil
	}
	followLifecycleLog(path, int64(len(content)), stdout)
	return nil
}

// followLifecycleLog prints what is appended to path from offset on, until
// interrupted. A file that shrinks (lifecyclelog.Trim at a booth start) is read
// again from its start.
func followLifecycleLog(path string, offset int64, stdout io.Writer) {
	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)
	defer signal.Stop(interrupt)
	ticker := time.NewTicker(lifecycleFollowInterval)
	defer ticker.Stop()
	for {
		select {
		case <-interrupt:
			return
		case <-ticker.C:
			offset = copyAppended(path, offset, stdout)
		}
	}
}

// copyAppended writes path's bytes from offset on and returns the new offset.
func copyAppended(path string, offset int64, stdout io.Writer) int64 {
	file, err := os.Open(path)
	if err != nil {
		return offset
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return offset
	}
	if info.Size() < offset {
		offset = 0
	}
	if info.Size() == offset {
		return offset
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		return offset
	}
	written, _ := io.Copy(stdout, file)
	return offset + written
}

// lifecycleLogEntry is the --list row for a booth's lifecycle log, if it has one.
func lifecycleLogEntry(codePath string) (logFile, bool) {
	if codePath == "" {
		return logFile{}, false
	}
	path := lifecyclelog.Path(codePath)
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return logFile{}, false
	}
	return logFile{Path: path, Size: info.Size(), ModTime: info.ModTime()}, true
}
