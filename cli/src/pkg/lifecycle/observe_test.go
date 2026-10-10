// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"
)

func TestObserveNativeCommands(t *testing.T) {
	cases := []struct {
		command string
		args    []string
		call    string
	}{
		{"inspect", []string{"demo", "--json"}, "<inspect><demo>"},
		{"inspect", []string{"demo", "--format", "{{.Name}}"}, "<inspect><--format><{{.Name}}><demo>"},
		{"stats", []string{"demo", "--no-stream", "--format=json"}, "<stats><--no-stream><--format><json><demo>"},
		{"top", []string{"demo", "--", "-eo", "pid,args"}, "<top><demo><-eo><pid,args>"},
		{"diff", []string{"demo"}, "<diff><demo>"},
		{"wait", []string{"demo"}, "<wait><demo>"},
	}
	for _, engine := range []string{"docker", "podman"} {
		for _, test := range cases {
			t.Run(engine+"/"+test.command+"/"+strings.Join(test.args, " "), func(t *testing.T) {
				log := installCopyEngine(t, engine, "demo", "", "running")
				var stdout, stderr bytes.Buffer
				if err := Observe(test.command, test.args, &stdout, &stderr); err != nil {
					t.Fatalf("got %v (%s)", err, stderr.String())
				}
				if !strings.Contains(readLog(t, log), test.call+"\n") {
					t.Fatalf("calls: %s; want %s", readLog(t, log), test.call)
				}
			})
		}
	}
}

func TestObserveAppleCapabilitiesAndCompleteInspect(t *testing.T) {
	log := installCopyEngine(t, "apple", "demo", "", "running")
	var stdout, stderr bytes.Buffer
	if err := Observe("inspect", []string{"demo"}, &stdout, &stderr); err != nil {
		t.Fatal(err)
	}
	// The internal Docker-shaped adapter drops NativeOnly. The user's inspect
	// must not drop fields such as mounts and resource limits it doesn't model.
	if !json.Valid(stdout.Bytes()) || !strings.Contains(stdout.String(), "NativeOnly") {
		t.Fatalf("incomplete inspect: %s", stdout.String())
	}
	if err := Observe("stats", []string{"demo", "--no-stream"}, &stdout, &stderr); err != nil {
		t.Fatal(err)
	}
	for _, command := range []string{"top", "diff", "wait"} {
		err := Observe(command, []string{"demo"}, &stdout, &stderr)
		if err == nil || !strings.Contains(err.Error(), "not supported on engine apple") {
			t.Fatalf("%s: %v", command, err)
		}
		if strings.Contains(readLog(t, log), "<"+command+">") {
			t.Fatalf("called unsupported %s", command)
		}
	}
	if err := Observe("inspect", []string{"demo", "--format=json"}, &stdout, &stderr); err == nil {
		t.Fatal("accepted unsupported Apple inspect formatting")
	}
}

func TestObserveStateAndExitCodes(t *testing.T) {
	log := installCopyEngine(t, "docker", "demo", "", "exited")
	var output bytes.Buffer
	for _, command := range []string{"inspect", "diff", "wait"} {
		if err := Observe(command, []string{"demo"}, &output, &output); err != nil {
			t.Fatal(err)
		}
	}
	for _, command := range []string{"stats", "top"} {
		if err := Observe(command, []string{"demo"}, &output, &output); err == nil || !strings.Contains(err.Error(), "not running") {
			t.Fatalf("%s accepted stopped booth: %v", command, err)
		}
		if strings.Contains(readLog(t, log), "<"+command+">") {
			t.Fatal("invoked command after refusing")
		}
	}
	t.Setenv("CB_TEST_EXIT", "17")
	if err := Observe("wait", []string{"demo"}, &output, &output); ExitCode(err) != 17 {
		t.Fatalf("engine failure lost: %v", err)
	}
}

func TestExplicitEngineSelectsDuplicateName(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker": {booths: []string{"demo"}}, "podman": {booths: []string{"demo"}},
	})
	var output bytes.Buffer
	if err := Observe("diff", []string{"demo"}, &output, &output); err == nil || !strings.Contains(err.Error(), "exists on both") {
		t.Fatalf("ambiguous engine: %v", err)
	}
	t.Setenv("CB_ENGINE", "docker")
	if err := Observe("diff", []string{"demo", "--engine", "podman"}, &output, &output); err != nil {
		t.Fatal(err)
	}
	if calls := readLog(t, log); !strings.Contains(calls, "podman diff demo") || strings.Contains(calls, "docker diff") {
		t.Fatalf("wrong engine: %s", calls)
	}
}

func TestJSONListAndExpose(t *testing.T) {
	installCopyEngine(t, "docker", "demo", "", "running")
	var stdout, stderr bytes.Buffer
	if err := List([]string{"--json"}, &stdout, &stderr); err != nil {
		t.Fatal(err)
	}
	var booths []boothListEntry
	if err := json.Unmarshal(stdout.Bytes(), &booths); err != nil || len(booths) != 1 || booths[0].Engine != "docker" || booths[0].Name != "demo" {
		t.Fatalf("list: %s (%v)", stdout.String(), err)
	}
	stdout.Reset()
	if err := Expose([]string{"list", "demo", "--json"}, &stdout, &stderr); err != nil {
		t.Fatal(err)
	}
	var ports struct {
		Engine string      `json:"engine"`
		Ports  []exposeRow `json:"ports"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &ports); err != nil || ports.Engine != "docker" || len(ports.Ports) != 1 || ports.Ports[0].HostPort != 12345 {
		t.Fatalf("expose: %s (%v)", stdout.String(), err)
	}
	stdout.Reset()
	if err := List([]string{"--stopped", "--json"}, &stdout, &stderr); err != nil || strings.TrimSpace(stdout.String()) != "[]" {
		t.Fatalf("empty list: %q, %v", stdout.String(), err)
	}
}

func TestInvalidEngineNeverInvokesEngine(t *testing.T) {
	log := installCopyEngine(t, "docker", "demo", "", "running")
	var output bytes.Buffer
	if err := Observe("inspect", []string{"demo", "--engine=typo"}, &output, &output); ExitCode(err) != 2 {
		t.Fatalf("invalid engine: %v", err)
	}
	if _, err := os.Stat(log); !os.IsNotExist(err) {
		t.Fatal("queried an engine for an invalid request")
	}
}
