// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"archive/tar"
	"bytes"
	"io"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func flatGroups(groups []ilist.List[string]) []string {
	var flat []string
	for _, group := range groups {
		flat = append(flat, group.Slice()...)
	}
	return flat
}

func TestParseLogsArgs(t *testing.T) {
	opts, err := parseLogsArgs([]string{"excalidraw", "-f", "--name", "web", "penpot.log", "--tail", "20"}, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if opts.name != "web" || !opts.follow || opts.tail != "20" {
		t.Errorf("flags after service names not parsed: %+v", opts)
	}
	if want := []string{"excalidraw", "penpot"}; !reflect.DeepEqual(opts.services, want) {
		t.Errorf("services = %q, want %q", opts.services, want)
	}

	opts, err = parseLogsArgs([]string{"--startup", "-n", "5"}, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"startups"}; !reflect.DeepEqual(opts.services, want) || opts.tail != "5" {
		t.Errorf("--startup -n 5 = %+v", opts)
	}
}

func TestParseLogsArgsRejects(t *testing.T) {
	for _, args := range [][]string{
		{"../etc/passwd"},
		{"a/b"},
		{"--tail", "lots"},
		{"--tail", "-3"},
		{"--list", "excalidraw"},
		{"--list", "-f"},
		{"excalidraw", "--since", "10m"},
		{"--startup", "-t"},
	} {
		if _, err := parseLogsArgs(args, io.Discard); err == nil {
			t.Errorf("parseLogsArgs(%q) accepted", args)
		}
	}
}

func TestContainerLogsArgs(t *testing.T) {
	opts := logsOptions{follow: true, tail: "100", since: "10m", until: "1m", stamps: true}
	got := flatGroups(containerLogsArgs(opts, "web"))
	want := []string{"--follow", "--tail", "100", "--since", "10m", "--until", "1m", "--timestamps", "web"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
	if got := flatGroups(containerLogsArgs(logsOptions{}, "web")); !reflect.DeepEqual(got, []string{"web"}) {
		t.Errorf("no flags: got %q", got)
	}
}

func TestLogTailExecArgs(t *testing.T) {
	paths := []string{"/tmp/a.log", "/tmp/b.log"}

	got := flatGroups(logTailExecArgs("web", paths, logsOptions{}))
	want := []string{"-u", "root", "web", "tail", "-n", "+1", "/tmp/a.log", "/tmp/b.log"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("whole file: got %q, want %q", got, want)
	}

	got = flatGroups(logTailExecArgs("web", paths[:1], logsOptions{tail: "all"}))
	want = []string{"-u", "root", "web", "tail", "-n", "+1", "/tmp/a.log"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("--tail all: got %q, want %q", got, want)
	}

	// Following runs under the watchdog, with -i for the stdin it watches.
	got = flatGroups(logTailExecArgs("web", paths, logsOptions{follow: true, tail: "10"}))
	want = []string{"-i", "-u", "root", "web", "sh", "-c", followWatchdog, "booth-logs", "tail", "-n", "10", "-F", "/tmp/a.log", "/tmp/b.log"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("follow: got %q, want %q", got, want)
	}
}

func logFiles(paths ...string) []logFile {
	files := make([]logFile, 0, len(paths))
	for _, path := range paths {
		files = append(files, logFile{Path: path})
	}
	return files
}

func selectedPaths(files []logFile) []string {
	paths := make([]string, 0, len(files))
	for _, file := range files {
		paths = append(paths, file.Path)
	}
	return paths
}

func TestSelectLogFiles(t *testing.T) {
	files := logFiles("/tmp/excalidraw.log", "/tmp/penpot-backend.log", "/tmp/penpot-exporter.log", "/tmp/penpot.log", "/tmp/n8n-sandbox.log", "/tmp/n8n-search.log", "/tmp/startups.log")

	tests := []struct {
		services []string
		want     []string
	}{
		// An exact <name>.log wins over the <name>-*.log family.
		{[]string{"penpot"}, []string{"/tmp/penpot.log"}},
		{[]string{"penpot-backend"}, []string{"/tmp/penpot-backend.log"}},
		// No exact file: every <name>-*.log, as one tail of several files.
		{[]string{"n8n"}, []string{"/tmp/n8n-sandbox.log", "/tmp/n8n-search.log"}},
		// Order follows the names; a file named twice is shown once.
		{[]string{"startups", "excalidraw", "startups"}, []string{"/tmp/startups.log", "/tmp/excalidraw.log"}},
	}
	for _, tt := range tests {
		got, err := selectLogFiles(tt.services, files)
		if err != nil {
			t.Fatalf("%q: %v", tt.services, err)
		}
		if paths := selectedPaths(got); !reflect.DeepEqual(paths, tt.want) {
			t.Errorf("%q: got %q, want %q", tt.services, paths, tt.want)
		}
	}
}

func TestSelectLogFilesNamesWhatIsMissingAndWhatExists(t *testing.T) {
	_, err := selectLogFiles([]string{"excalidraw", "ollama"}, logFiles("/tmp/excalidraw.log", "/tmp/startups.log"))
	if err == nil {
		t.Fatal("missing service accepted")
	}
	for _, want := range []string{`"ollama"`, "available: excalidraw, startups"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q lacks %q", err, want)
		}
	}
	if strings.Contains(err.Error(), `"excalidraw"`) {
		t.Errorf("error %q names a service that was found", err)
	}
}

func TestParseLogList(t *testing.T) {
	out := "12 1700000000 /tmp/startups.log\n" +
		"3 1700000100 /tmp/a b.log\n" +
		"garbage\n"
	got := parseLogList(out)
	if len(got) != 2 {
		t.Fatalf("got %d files, want 2: %+v", len(got), got)
	}
	if got[0].Path != "/tmp/a b.log" || got[0].Size != 3 || got[0].Service() != "a b" {
		t.Errorf("first = %+v", got[0])
	}
	if got[1].Path != "/tmp/startups.log" || !got[1].ModTime.Equal(time.Unix(1700000000, 0)) {
		t.Errorf("second = %+v", got[1])
	}
}

func TestReadLogTarKeepsTopLevelLogFiles(t *testing.T) {
	var archive bytes.Buffer
	writer := tar.NewWriter(&archive)
	add := func(name string, kind byte, body string) {
		if err := writer.WriteHeader(&tar.Header{Name: name, Typeflag: kind, Size: int64(len(body)), Mode: 0o644}); err != nil {
			t.Fatal(err)
		}
		if body != "" {
			_, _ = writer.Write([]byte(body))
		}
	}
	add("tmp/", tar.TypeDir, "")
	add("tmp/excalidraw.log", tar.TypeReg, "one\ntwo\n")
	add("tmp/notes.txt", tar.TypeReg, "not a log")
	add("tmp/cache/", tar.TypeDir, "")
	add("tmp/cache/deep.log", tar.TypeReg, "too deep")
	add("tmp/startups.log", tar.TypeReg, "hooks\n")
	_ = writer.Close()

	files, err := readLogTar(&archive)
	if err != nil {
		t.Fatal(err)
	}
	if paths := selectedPaths(files); !reflect.DeepEqual(paths, []string{"/tmp/excalidraw.log", "/tmp/startups.log"}) {
		t.Fatalf("paths = %q", paths)
	}
	if string(files[0].Content) != "one\ntwo\n" || files[0].Size != 8 {
		t.Errorf("excalidraw.log = %+v", files[0])
	}
}

func TestWriteTailMatchesTail(t *testing.T) {
	a := logFile{Path: "/tmp/a.log", Content: []byte("1\n2\n3\n")}
	b := logFile{Path: "/tmp/b.log", Content: []byte("x\ny")}

	var out bytes.Buffer
	writeTail(&out, []logFile{a}, "2")
	if out.String() != "2\n3\n" {
		t.Errorf("one file, last 2: %q", out.String())
	}

	out.Reset()
	writeTail(&out, []logFile{a, b}, "")
	if want := "==> /tmp/a.log <==\n1\n2\n3\n\n==> /tmp/b.log <==\nx\ny"; out.String() != want {
		t.Errorf("two files:\n got %q\nwant %q", out.String(), want)
	}

	out.Reset()
	writeTail(&out, []logFile{b}, "1")
	if out.String() != "y" {
		t.Errorf("no trailing newline, last 1: %q", out.String())
	}

	out.Reset()
	writeTail(&out, []logFile{a}, "0")
	if out.String() != "" {
		t.Errorf("last 0: %q", out.String())
	}
}

func TestPrintLogList(t *testing.T) {
	var out bytes.Buffer
	printLogList(&out, "web", []logFile{{Path: "/tmp/excalidraw.log", Size: 2048, ModTime: time.Unix(0, 0)}})
	for _, want := range []string{"SERVICE", "excalidraw", "2.0K", "/tmp/excalidraw.log", "booth logs <SERVICE>"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("list lacks %q:\n%s", want, out.String())
		}
	}

	out.Reset()
	printLogList(&out, "web", nil)
	if !strings.Contains(out.String(), `No log files in /tmp of booth "web"`) {
		t.Errorf("empty list: %q", out.String())
	}
}

func TestLogsReadsTheContainerOutputOfTheOwningEngine(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker": {booths: []string{"web"}},
		"podman": {booths: []string{"lab"}},
	})
	if err := Logs([]string{"--name", "lab", "--tail", "5"}, io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	if calls := readLog(t, log); !strings.Contains(calls, "podman logs --tail 5 lab") {
		t.Errorf("calls:\n%s", calls)
	}
}

func TestLogsTailsTheServiceFileInARunningBooth(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{"docker": {booths: []string{"web"}}})
	// The fake answers the exec that lists /tmp with nothing, so the service is
	// reported missing — after the listing ran as root, not as coder.
	err := Logs([]string{"--name", "web", "excalidraw"}, io.Discard, io.Discard)
	if err == nil || !strings.Contains(err.Error(), `no log for "excalidraw"`) {
		t.Fatalf("err = %v", err)
	}
	if calls := readLog(t, log); !strings.Contains(calls, "docker exec -u root web sh -c") {
		t.Errorf("calls:\n%s", calls)
	}
}
