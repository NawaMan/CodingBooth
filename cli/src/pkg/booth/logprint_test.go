// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bytes"
	"regexp"
	"testing"
)

func TestTimePrefix_Disabled(t *testing.T) {
	SetLogTime(false)
	defer SetLogTime(false)

	prefix := timePrefix()
	if prefix != "" {
		t.Errorf("Expected empty prefix when logTime disabled, got %q", prefix)
	}
}

func TestTimePrefix_Enabled(t *testing.T) {
	SetLogTime(true)
	defer SetLogTime(false)

	prefix := timePrefix()
	matched, _ := regexp.MatchString(`^\[\d{2}:\d{2}:\d{2}\] $`, prefix)
	if !matched {
		t.Errorf("Expected prefix matching [HH:MM:SS] format, got %q", prefix)
	}
}

func TestLogFprintf_WithTimestamp(t *testing.T) {
	SetLogTime(true)
	defer SetLogTime(false)

	var buf bytes.Buffer
	LogFprintf(&buf, "hello %s", "world")

	output := buf.String()
	matched, _ := regexp.MatchString(`^\[\d{2}:\d{2}:\d{2}\] hello world$`, output)
	if !matched {
		t.Errorf("Expected timestamped output, got %q", output)
	}
}

func TestLogFprintf_WithoutTimestamp(t *testing.T) {
	SetLogTime(false)
	defer SetLogTime(false)

	var buf bytes.Buffer
	LogFprintf(&buf, "hello %s", "world")

	output := buf.String()
	if output != "hello world" {
		t.Errorf("Expected 'hello world', got %q", output)
	}
}

func TestLogTimef_OnlyWhenEnabled(t *testing.T) {
	SetLogTime(false)
	defer SetLogTime(false)

	var buf bytes.Buffer
	LogTimef(&buf, "should not appear")

	if buf.Len() != 0 {
		t.Errorf("Expected no output when logTime disabled, got %q", buf.String())
	}
}

func TestLogTimef_WhenEnabled(t *testing.T) {
	SetLogTime(true)
	defer SetLogTime(false)

	var buf bytes.Buffer
	LogTimef(&buf, "timing info")

	output := buf.String()
	matched, _ := regexp.MatchString(`^\[\d{2}:\d{2}:\d{2}\] timing info$`, output)
	if !matched {
		t.Errorf("Expected timestamped output, got %q", output)
	}
}
