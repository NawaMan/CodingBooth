// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/internal/fakebin"
)

// The fake keeps argument boundaries and supplies both native inspect schemas.
// No real daemon is needed to verify selection, refusal, and output forwarding.
func installCopyEngine(t *testing.T, engine, name, codePath, state string) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls.log")
	labels := map[string]string{"cb.managed": "true", "cb.code-path": codePath, "cb.variant": "base"}
	document := map[string]any{
		"Name": "/" + name, "State": map[string]string{"Status": state},
		"Config": map[string]any{"Labels": labels}, "NativeOnly": "keep-this-field",
	}
	if engine == "apple" {
		document = map[string]any{
			"id": name, "configuration": map[string]any{"labels": labels},
			"status": map[string]string{"state": state}, "NativeOnly": "keep-this-field",
		}
	}
	single, _ := json.Marshal(document)
	array, _ := json.Marshal([]any{document})
	t.Setenv("CB_TEST_INSPECT", string(single))
	t.Setenv("CB_TEST_INSPECT_ARRAY", string(array))
	t.Setenv("CB_TEST_NAME", name)
	t.Setenv("CB_TEST_CALLS", log)
	t.Setenv("CB_TEST_EXIT", "0")
	t.Setenv("CB_ENGINE", engine)
	t.Setenv(envFakeMode, fakeModeCopy)
	binary := engine
	if binary == "apple" {
		binary = "container"
	}
	fakebin.InstallInto(t, dir, binary)
	t.Setenv("PATH", dir)
	return log
}

// fakeCopyMain is what a stub installed by installCopyEngine does. Each
// argument is logged inside angle brackets, so a test can see exactly where
// the boundaries fell — a path with a space in it stays one argument.
func fakeCopyMain(name string, args []string) int {
	var line strings.Builder
	for _, arg := range args {
		line.WriteString("<" + arg + ">")
	}
	line.WriteString("\n")
	appendCall("CB_TEST_CALLS", line.String())

	subcommand := ""
	if len(args) > 0 {
		subcommand = args[0]
	}
	switch {
	case subcommand == "ps":
		fmt.Println(os.Getenv("CB_TEST_NAME"))
	case subcommand == "ls":
		fmt.Println(os.Getenv("CB_TEST_INSPECT_ARRAY"))
	case subcommand == "inspect":
		if len(args) > 1 && args[1] == "--format" {
			fmt.Println(os.Getenv("CB_TEST_INSPECT"))
		} else {
			fmt.Println(os.Getenv("CB_TEST_INSPECT_ARRAY"))
		}
	case subcommand == "port":
		fmt.Println("8080/tcp -> 127.0.0.1:12345")
	default:
		fmt.Println("native-output")
		fmt.Fprintln(os.Stderr, "native-stderr")
		code, err := strconv.Atoi(os.Getenv("CB_TEST_EXIT"))
		if err != nil {
			return 127
		}
		return code
	}
	return 0
}

func TestCopyEndpointPaths(t *testing.T) {
	cases := []struct {
		value string
		want  copyEndpoint
	}{
		{":/tmp/file", copyEndpoint{true, "", "/tmp/file"}},
		{"demo:tmp/dir/.", copyEndpoint{true, "demo", "tmp/dir/."}},
		{"./file:name", copyEndpoint{path: "./file:name"}},
		{"folder/file:name", copyEndpoint{path: "folder/file:name"}},
		{"/tmp/file:name", copyEndpoint{path: "/tmp/file:name"}},
		{`C:\Users\dev\file`, copyEndpoint{path: `C:\Users\dev\file`}},
		{"C:/Users/dev/file", copyEndpoint{path: "C:/Users/dev/file"}},
		{`\\server\share\file`, copyEndpoint{path: `\\server\share\file`}},
		{"-", copyEndpoint{path: "-"}},
	}
	for _, test := range cases {
		t.Run(test.value, func(t *testing.T) {
			got, err := parseCopyEndpoint(test.value)
			if err != nil || got != test.want {
				t.Fatalf("got %+v, %v; want %+v", got, err, test.want)
			}
		})
	}
	for _, invalid := range []string{"", ":", "demo:"} {
		if _, err := parseCopyEndpoint(invalid); err == nil {
			t.Errorf("accepted %q", invalid)
		}
	}
}

func TestCopyRoutingAndPathSemantics(t *testing.T) {
	cases := []struct {
		name, engine, state string
		args                []string
		call                string
	}{
		{"upload", "docker", "running", []string{"file with spaces", "demo:tmp/"}, "<cp><{rel}file with spaces><demo:/tmp/>"},
		{"stopped download", "docker", "exited", []string{"--name", "demo", ":/tmp/dir/.", "./output/"}, "<cp><demo:/tmp/dir/.><./output/>"},
		{"podman", "podman", "running", []string{"data/.", "demo:/tmp"}, "<cp><{rel}data/.><demo:/tmp>"},
		{"apple", "apple", "running", []string{"file", "demo:/tmp"}, "<cp><{rel}file><demo:/tmp>"},
		{"tar output", "docker", "running", []string{"demo:/tmp/data", "-"}, "<cp><demo:/tmp/data><->"},
		{"protected filename", "docker", "running", []string{"--name=demo", "--", "-q", ":/tmp/-q"}, "<cp><{rel}-q><demo:/tmp/-q>"},
		{"literal shell metacharacters", "docker", "running", []string{"./$(touch sentinel)", "demo:/tmp/a;echo b"}, "<cp><./$(touch sentinel)><demo:/tmp/a;echo b>"},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			log := installCopyEngine(t, test.engine, "demo", "", test.state)
			var stdout, stderr bytes.Buffer
			if err := Copy(test.args, &stdout, &stderr); err != nil {
				t.Fatalf("Copy: %v (%s)", err, stderr.String())
			}
			// "{rel}" stands for the prefix copy.go puts in front of a relative
			// host path: "." and the host's own separator, so "./" here and
			// ".\" on Windows, which is the form docker.exe there takes. A path
			// the caller already wrote as "./x" keeps its own prefix, and says
			// so above by carrying no "{rel}".
			want := strings.ReplaceAll(test.call, "{rel}", "."+string(filepath.Separator))
			if calls := readLog(t, log); !strings.Contains(calls, want+"\n") {
				t.Fatalf("calls = %s; want %s", calls, want)
			}
			if stdout.String() != "native-output\n" || stderr.String() != "native-stderr\n" {
				t.Fatalf("native output not forwarded: %q, %q", stdout.String(), stderr.String())
			}
		})
	}
}

func TestCopyRefusalsDoNotCopy(t *testing.T) {
	cases := []struct {
		name, engine, state string
		args                []string
		message             string
	}{
		{"two host paths", "docker", "running", []string{"a", "b"}, "exactly one"},
		{"two booths", "docker", "running", []string{"demo:/a", "other:/b"}, "exactly one"},
		{"missing operand", "docker", "running", []string{"demo:/a"}, "Usage:"},
		{"conflicting name", "docker", "running", []string{"--name=other", "a", "demo:/b"}, "conflicts"},
		{"missing booth", "docker", "running", []string{"a", "missing:/b"}, "not found"},
		{"stopped Apple", "apple", "stopped", []string{"a", "demo:/b"}, "requires a running"},
		{"Apple tar", "apple", "running", []string{"demo:/a", "-"}, "tar streams"},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			log := installCopyEngine(t, test.engine, "demo", "", test.state)
			var output bytes.Buffer
			err := Copy(test.args, &output, &output)
			if err == nil || !strings.Contains(err.Error(), test.message) {
				t.Fatalf("got %v; want %q", err, test.message)
			}
			calls, _ := os.ReadFile(log)
			if strings.Contains(string(calls), "<cp>") {
				t.Fatalf("refused copy ran: %s", calls)
			}
		})
	}
}

func TestCopyCodePathIdentityAndDefault(t *testing.T) {
	workspace := t.TempDir()
	log := installCopyEngine(t, "docker", defaultBoothName(), workspace, "running")
	var output bytes.Buffer
	for _, args := range [][]string{
		{"a", ":/tmp/b"},
		{"--code", workspace, "a", ":/tmp/b"},
		{"--name", defaultBoothName(), "--code", workspace, "a", ":/tmp/b"},
	} {
		if err := Copy(args, &output, &output); err != nil {
			t.Fatal(err)
		}
	}
	before := readLog(t, log)
	err := Copy([]string{"--code", t.TempDir(), "a", defaultBoothName() + ":/tmp/b"}, &output, &output)
	if err == nil || !strings.Contains(err.Error(), "was created from code path") {
		t.Fatalf("mismatched code path: %v", err)
	}
	if strings.Count(readLog(t, log), "<cp>") != strings.Count(before, "<cp>") {
		t.Fatal("copied into a booth from the wrong project")
	}
}

func TestCopyPropagatesEngineFailure(t *testing.T) {
	installCopyEngine(t, "docker", "demo", "", "running")
	t.Setenv("CB_TEST_EXIT", "23")
	var output bytes.Buffer
	if err := Copy([]string{"a", "demo:/b"}, &output, &output); ExitCode(err) != 23 {
		t.Fatalf("got %v, exit %d; want 23", err, ExitCode(err))
	}
}
