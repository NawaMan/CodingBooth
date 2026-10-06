// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecyclelog

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLineMatchesTheBoothScriptFormat(t *testing.T) {
	at := time.Date(2026, 10, 4, 14, 2, 27, 0, time.FixedZone("EDT", -4*3600))
	got := Line(at, "empty-example", "stop-requested", "by=host-cli", "force=false")
	want := "2026-10-04T14:02:27-0400 empty-example stop-requested by=host-cli force=false"
	if got != want {
		t.Errorf("Line() = %q, want %q", got, want)
	}
}

func TestLineKeepsOneEventOnOneLine(t *testing.T) {
	got := Line(time.Unix(0, 0), "", "exited", "error=a\nforged line")
	if strings.Contains(got, "\n") {
		t.Errorf("Line() = %q, contains a newline", got)
	}
	if !strings.Contains(got, " booth exited ") {
		t.Errorf("Line() = %q, want the fallback name \"booth\"", got)
	}
}

func TestAppendWritesUnderBoothTmp(t *testing.T) {
	code := t.TempDir()
	os.MkdirAll(filepath.Join(code, ".booth"), 0755)

	Append(code, "demo", "started")
	Append(code, "demo", "exited", "status=0")

	data, err := os.ReadFile(Path(code))
	if err != nil {
		t.Fatalf("read log: %v", err)
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if len(lines) != 2 || !strings.HasSuffix(lines[0], " demo started") || !strings.HasSuffix(lines[1], " demo exited status=0") {
		t.Errorf("log = %q", data)
	}
}

func TestAppendNeverCreatesBoothDir(t *testing.T) {
	code := t.TempDir()
	Append(code, "demo", "started")
	if _, err := os.Stat(filepath.Join(code, ".booth")); !os.IsNotExist(err) {
		t.Errorf("Append created .booth/ in a folder without one")
	}
	Append("", "demo", "started") // no code path: a no-op, not a panic
}

func TestKeep(t *testing.T) {
	if !Keep("lifecycle.log") || Keep("booth-startup.txt") || Keep("messages") {
		t.Errorf("Keep should hold lifecycle.log only")
	}
}

func TestTrimDropsOldestWholeLines(t *testing.T) {
	code := t.TempDir()
	os.MkdirAll(filepath.Join(code, ".booth", ".tmp"), 0755)
	var b strings.Builder
	for i := 0; b.Len() <= maxSize; i++ {
		b.WriteString(Line(time.Unix(int64(i), 0), "demo", "event", strings.Repeat("x", i%50)) + "\n")
	}
	original := b.String()
	os.WriteFile(Path(code), []byte(original), 0644)

	Trim(code)

	data, _ := os.ReadFile(Path(code))
	if len(data) > maxSize/2 || len(data) == 0 {
		t.Fatalf("trimmed size = %d, want (0, %d]", len(data), maxSize/2)
	}
	if !strings.HasSuffix(original, string(data)) {
		t.Errorf("Trim kept something other than the newest lines")
	}
	if !strings.Contains(string(data[:strings.IndexByte(string(data), '\n')]), " demo event") {
		t.Errorf("first kept line is not whole: %q", data[:80])
	}
}

func TestTrimLeavesASmallLogAlone(t *testing.T) {
	code := t.TempDir()
	os.MkdirAll(filepath.Join(code, ".booth", ".tmp"), 0755)
	os.WriteFile(Path(code), []byte("one\n"), 0644)
	Trim(code)
	if data, _ := os.ReadFile(Path(code)); string(data) != "one\n" {
		t.Errorf("small log changed: %q", data)
	}
}
