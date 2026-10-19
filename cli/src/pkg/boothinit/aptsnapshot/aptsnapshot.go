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

// Lag is how far behind the current day `today` lands. A snapshot id names a
// UTC day, and the day a user calls "today" can be one Ubuntu has not published
// yet — late in the evening west of UTC, or before that day's snapshot is cut.
// A week back is a day that exists everywhere, with room to spare.
const Lag = 7 * 24 * time.Hour

// Release is the snapshot the images of this binary's release were built
// against: the repo's apt-snapshot.txt, stamped in by build/cli-build.sh via
// -ldflags "-X …/aptsnapshot.Release=<id>". Empty in a binary built any other
// way (go test, go run, a bare go build).
var Release = ""

// Today is the snapshot id the `today` keyword means: the UTC day Lag ago, at
// day granularity.
func Today() string {
	return time.Now().UTC().Add(-Lag).Format("20060102") + "T000000Z"
}

// Default is the snapshot a new booth is frozen to: Release, the one its images
// were built against, so a booth never starts out older than its own image —
// apt cannot downgrade a package the image already has newer. Today when the
// binary carries no usable Release.
func Default() string {
	if id, err := Parse(Release); err == nil && id != "" && id == Release {
		return id
	}
	return Today()
}

// Parse turns a user's value into the id to record:
//
//	today        Today() — a week back, not the current day
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
