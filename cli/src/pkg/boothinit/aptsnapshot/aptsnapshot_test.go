// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package aptsnapshot

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParse_Accepted(t *testing.T) {
	for in, want := range map[string]string{
		"20260601T000000Z":   "20260601T000000Z",
		" 20260601T123456Z ": "20260601T123456Z",
		"20230301T000000Z":   "20230301T000000Z",
		"today":              Today(),
		"TODAY":              Today(),
		"none":               "",
		"None":               "",
		"":                   "",
		"   ":                "",
	} {
		got, err := Parse(in)
		require.NoError(t, err, in)
		assert.Equal(t, want, got, in)
	}
}

func TestParse_RefusedWithTheReason(t *testing.T) {
	future := time.Now().UTC().AddDate(0, 0, 2).Format("20060102") + "T000000Z"
	for in, reason := range map[string]string{
		"2026-06-01":       "not a snapshot id",
		"20260601":         "not a snapshot id",
		"20260601T000000":  "not a snapshot id",
		"yesterday":        "not a snapshot id",
		"20261301T000000Z": "not a real date", // month 13
		"20260230T000000Z": "not a real date", // Feb 30
		"20260601T250000Z": "not a real date", // hour 25
		"20230228T000000Z": "before 20230301T000000Z",
		future:             "in the future",
	} {
		_, err := Parse(in)
		if assert.Error(t, err, in) {
			assert.Contains(t, err.Error(), reason, in)
			assert.Contains(t, err.Error(), in, "the error names the value it refused")
		}
	}
}

func TestToday_IsUTCMidnight(t *testing.T) {
	assert.Regexp(t, `^\d{8}T000000Z$`, Today())
	_, err := Parse(Today())
	assert.NoError(t, err, "today's own id must parse")
}
