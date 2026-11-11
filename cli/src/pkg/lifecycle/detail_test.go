// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func TestParseStats(t *testing.T) {
	got, err := parseStats("0.27%\t48.23MiB / 123.3GiB\t0.04%\n")
	want := BoothStats{CPU: "0.27%", Memory: "48.23MiB / 123.3GiB", MemPerc: "0.04%"}
	if err != nil || got != want {
		t.Fatalf("parseStats = %+v, %v; want %+v", got, err, want)
	}
	if _, err := parseStats("\n"); err == nil {
		t.Error("empty output must be an error")
	}
}

func TestParseState(t *testing.T) {
	out := `{"ok":true,"viewers":2,"background":1,"expected":1}
{"enabled":true,"idle_time":1800,"base_idle_time":1800,"shutdown_time":60,"disabled":false,"pause_until":1794430000}
`
	got, err := parseState(out)
	if err != nil {
		t.Fatal(err)
	}
	want := BoothState{
		Presence: BoothPresence{Viewers: 2, Background: 1, Expected: 1},
		Idle:     BoothIdle{Enabled: true, IdleTime: 1800, ShutdownTime: 60, PauseUntil: 1794430000},
	}
	if got != want {
		t.Fatalf("parseState = %+v, want %+v", got, want)
	}
	if _, err := parseState(`{"ok":true}`); err == nil {
		t.Error("a missing idle line must be an error")
	}
}

func TestPendingMessagesIn(t *testing.T) {
	dir := t.TempDir()
	now := time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("b.msg.json", `{"id":"b","title":"Second","type":"yes-no","created":"2026-11-11T11:00:00Z"}`)
	write("a.msg.json", `{"id":"a","title":"First","type":"text","created":"2026-11-11T10:00:00Z"}`)
	write("answered.msg.json", `{"id":"answered","title":"Done","type":"yes-no","created":"2026-11-11T09:00:00Z"}`)
	write("answered.response.json", `{"id":"answered","answer":"yes"}`)
	write("toast.msg.json", `{"id":"toast","title":"Hi","type":"toast","created":"2026-11-11T09:00:00Z"}`)
	write("old.msg.json", `{"id":"old","title":"Old","type":"ok","created":"2026-11-11T08:00:00Z","expires":"2026-11-11T11:59:00Z"}`)
	write("junk.msg.json", `not json`)

	got, err := pendingMessagesIn(dir, now)
	if err != nil {
		t.Fatal(err)
	}
	want := []PendingMessage{{ID: "a", Title: "First", Type: "text"}, {ID: "b", Title: "Second", Type: "yes-no"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("pending = %+v, want %+v", got, want)
	}

	none, err := pendingMessagesIn(filepath.Join(dir, "missing"), now)
	if err != nil || len(none) != 0 {
		t.Errorf("missing dir: %v, %v", none, err)
	}
}

func TestContainerFromInspectReadsStateTimes(t *testing.T) {
	var data inspectData
	data.State.Status = "running"
	data.State.StartedAt = "2026-11-11T19:09:21Z"
	data.State.FinishedAt = "2026-11-10T19:01:18Z"
	c := containerFromInspect(data, "web")
	if c.StartedAt != "2026-11-11T19:09:21Z" || c.FinishedAt != "2026-11-10T19:01:18Z" {
		t.Fatalf("times = %q %q", c.StartedAt, c.FinishedAt)
	}
	b := boothsFrom([]managedContainer{c})[0]
	if b.StartedAt != c.StartedAt || b.FinishedAt != c.FinishedAt {
		t.Errorf("Booth lost the times: %+v", b)
	}
}
