// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package lifecyclelog is the host side of a booth's lifecycle log,
// <code>/.booth/.tmp/lifecycle.log: one line per thing that happened to the
// booth — started, told to stop or restart, idle-timed out, a console pane's
// terminal gone, the container's exit. The booth appends through the
// booth--lifecycle-log script; the host CLI appends here, in the same format, so
// both sides of a booth's end read as one story.
//
// The rest of .booth/.tmp/ is session scratch, emptied on every start and exit.
// This file is kept across both (see Keep): its whole point is to still be there
// after the container is gone, or after a restart has started a new session.
package lifecyclelog

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

// FileName is the log's name inside .booth/.tmp/.
const FileName = "lifecycle.log"

// maxSize is where Trim starts dropping the oldest lines. The log outlives every
// session of a code folder, so it needs some bound; at roughly 100 bytes a line
// this is a couple of thousand events.
const maxSize = 256 * 1024

// timeLayout matches booth--lifecycle-log's `date '+%Y-%m-%dT%H:%M:%S%z'`.
const timeLayout = "2006-01-02T15:04:05-0700"

// Path is the log file for a booth's code folder.
func Path(codePath string) string {
	return filepath.Join(codePath, ".booth", ".tmp", FileName)
}

// Keep reports whether an entry of .booth/.tmp/ survives the start/exit wipe.
func Keep(entryName string) bool {
	return entryName == FileName
}

// Line formats one log line.
func Line(now time.Time, boothName string, event string, details ...string) string {
	fields := append([]string{now.Format(timeLayout), nonEmpty(boothName, "booth"), event}, details...)
	// One line per event: a detail with a newline would forge a second one.
	return strings.NewReplacer("\r", " ", "\n", " ").Replace(strings.Join(fields, " "))
}

// Append adds one line to the log of the booth whose code is at codePath. It
// never fails its caller: no code path, no .booth/ folder (a booth run without
// one has no .booth/.tmp/ mount either, and creating .booth/ here would change
// what the next run mounts), or an unwritable file all drop the line.
func Append(codePath string, boothName string, event string, details ...string) {
	if codePath == "" {
		return
	}
	boothDir := filepath.Join(codePath, ".booth")
	if info, err := os.Stat(boothDir); err != nil || !info.IsDir() {
		return
	}
	if err := os.MkdirAll(filepath.Join(boothDir, ".tmp"), 0755); err != nil {
		return
	}
	file, err := os.OpenFile(Path(codePath), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = file.WriteString(Line(time.Now(), boothName, event, details...) + "\n")
}

// Trim keeps the log under maxSize by dropping its oldest lines, cutting at a
// line boundary so the first kept line is whole. Run at booth start, before the
// booth's own lines arrive.
func Trim(codePath string) {
	path := Path(codePath)
	info, err := os.Stat(path)
	if err != nil || info.Size() <= maxSize {
		return
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	kept := data[len(data)-maxSize/2:]
	if newline := strings.IndexByte(string(kept), '\n'); newline >= 0 {
		kept = kept[newline+1:]
	}
	_ = os.WriteFile(path, kept, info.Mode().Perm())
}

func nonEmpty(value string, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
