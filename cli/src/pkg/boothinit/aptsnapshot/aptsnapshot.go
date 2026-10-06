// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package aptsnapshot reads the value a user gives for a booth's apt freeze — the
// Ubuntu archive snapshot written to the Boothfile as `env APT_SNAPSHOT=<id>`.
//
// It is shared by `booth config --apt-snapshot` and the TUI's Apt Snapshot field,
// so both accept the same values and refuse the same ones for the same reason.
package aptsnapshot

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// idLayout is the snapshot id format apt's --snapshot takes: a UTC timestamp.
const idLayout = "20060102T150405Z"

// idShape is idLayout's shape, checked before the date itself so a value in the
// wrong format and a value naming a day that does not exist get different answers.
var idShape = regexp.MustCompile(`^[0-9]{8}T[0-9]{6}Z$`)

// earliest is the first snapshot Ubuntu's snapshot service has.
var earliest = time.Date(2023, 3, 1, 0, 0, 0, 0, time.UTC)

// Today is today's snapshot id: UTC, day granularity.
func Today() string {
	return time.Now().UTC().Format("20060102") + "T000000Z"
}

// Parse turns a user's value into the id to record:
//
//	today        Today()
//	none, ""     "" — no freeze
//	<id>         that id, checked to be a real date the snapshot service has
//
// The error says what is wrong with the value, not how to fix it: the CLI and the
// TUI word the way out differently (`none` vs an empty field), so each adds its own.
func Parse(value string) (string, error) {
	value = strings.TrimSpace(value)
	switch strings.ToLower(value) {
	case "today":
		return Today(), nil
	case "", "none":
		return "", nil
	}
	if !idShape.MatchString(value) {
		return "", fmt.Errorf("%q is not a snapshot id — the format is YYYYMMDDTHHMMSSZ in UTC, e.g. 20260601T000000Z", value)
	}
	at, err := time.Parse(idLayout, value)
	if err != nil {
		return "", fmt.Errorf("%q is not a real date and time", value)
	}
	if at.Before(earliest) {
		return "", fmt.Errorf("%q is before %s, the first snapshot Ubuntu has", value, earliest.Format(idLayout))
	}
	if at.After(time.Now().UTC()) {
		return "", fmt.Errorf("%q is in the future — no snapshot exists for it yet", value)
	}
	return value, nil
}
