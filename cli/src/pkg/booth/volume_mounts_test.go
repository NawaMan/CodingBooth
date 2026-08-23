// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func TestVolumeSource(t *testing.T) {
	tests := []struct {
		name string
		spec string
		want string
	}{
		{"UnixAbsolute", "/home/u/.config/gh:/etc/seed/gh:ro", "/home/u/.config/gh"},
		{"UnixHomeTilde", "~/.config/gh:/etc/seed/gh:ro", "~/.config/gh"},
		{"UnixRelative", "./data:/data", "./data"},
		{"NamedVolume", "myvol:/data:ro", "myvol"},
		{"NamedVolumeNoMode", "cache_data:/var/cache", "cache_data"},
		{"MacAppSupport", "/Users/u/Library/Application Support/Antigravity:/etc/seed:ro", "/Users/u/Library/Application Support/Antigravity"},
		{"WindowsDriveFwd", `C:/Users/u/AppData/Roaming/gcloud:/etc/seed/gcloud:ro`, `C:/Users/u/AppData/Roaming/gcloud`},
		{"WindowsDriveBack", `C:\Users\u\AppData\Roaming\gcloud:/etc/seed/gcloud:ro`, `C:\Users\u\AppData\Roaming\gcloud`},
		{"WindowsDriveMixed", `C:\Users\u\AppData\Roaming/gcloud:/etc/seed/gcloud:ro`, `C:\Users\u\AppData\Roaming/gcloud`},
		{"WindowsLowerDrive", `c:\Users\u\.config\gh:/etc/seed/gh:ro`, `c:\Users\u\.config\gh`},
		{"WindowsToWindowsContainer", `C:\host\data:D:\container\data`, `C:\host\data`},
		{"UNCPath", `\\server\share\path:/container`, `\\server\share\path`},
		{"Empty", "", ""},
		{"SourceOnly", "/only/source", "/only/source"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := volumeSource(tt.spec)
			if got != tt.want {
				t.Fatalf("volumeSource(%q) = %q, want %q", tt.spec, got, tt.want)
			}
		})
	}
}

func TestIsBindMountSource(t *testing.T) {
	tests := []struct {
		source string
		want   bool
	}{
		{"/home/u/.config/gh", true},
		{"~/.config/gh", true},
		{"~", true},
		{`~\AppData\Roaming\gh`, true},
		{"./data", true},
		{"../data", true},
		{".", true},
		{"..", true},
		{"subdir/data", true},
		{`C:\Users\u\path`, true},
		{`C:/Users/u/path`, true},
		{`\\server\share`, true},
		{"myvol", false},
		{"cache_data", false},
		{"my.volume-1", false},
		{"", false},
	}
	for _, tt := range tests {
		t.Run(tt.source, func(t *testing.T) {
			got := isBindMountSource(tt.source)
			if got != tt.want {
				t.Fatalf("isBindMountSource(%q) = %v, want %v", tt.source, got, tt.want)
			}
		})
	}
}

func TestExpandHostPath(t *testing.T) {
	home := "/home/tester"
	if got := expandHostPath("~", home); got != home {
		t.Fatalf("expand ~ = %q, want %q", got, home)
	}
	if got := expandHostPath("~/.config/gh", home); got != filepath.Join(home, ".config/gh") {
		t.Fatalf("expand ~/ = %q", got)
	}
	if got := expandHostPath(`~\AppData\Roaming\gh`, home); got != filepath.Join(home, `AppData\Roaming\gh`) {
		t.Fatalf("expand ~\\ = %q", got)
	}
	if got := expandHostPath("/abs/path", home); got != "/abs/path" {
		t.Fatalf("abs path changed: %q", got)
	}
}

func TestFilterMissingVolumeMountItems(t *testing.T) {
	tmp := t.TempDir()
	existing := filepath.Join(tmp, "exists")
	if err := os.Mkdir(existing, 0o755); err != nil {
		t.Fatal(err)
	}
	missing := filepath.Join(tmp, "missing")

	home := filepath.Join(tmp, "home")
	if err := os.MkdirAll(filepath.Join(home, ".config", "gh"), 0o755); err != nil {
		t.Fatal(err)
	}

	items := []string{
		"-e", "FOO=1",
		"-v", existing + ":/in/container:ro",
		"-v", missing + ":/skip/me:ro",
		"--volume", "myvol:/named/vol",
		"-v", "~/.config/gh:/etc/seed/gh:ro",
		"-v", `C:\Users\nope\AppData\Roaming\gcloud:/etc/seed/gcloud:ro`,
		"-p", "8080:80",
	}

	got := filterMissingVolumeMountItems(items, home)

	// Flatten to string for easier assertions
	joined := strings.Join(got, " | ")

	if !containsPair(got, "-v", existing+":/in/container:ro") {
		t.Fatalf("expected existing bind mount kept; got: %s", joined)
	}
	if containsPair(got, "-v", missing+":/skip/me:ro") {
		t.Fatalf("expected missing bind mount removed; got: %s", joined)
	}
	if !containsPair(got, "--volume", "myvol:/named/vol") {
		t.Fatalf("expected named volume kept; got: %s", joined)
	}
	// Tilde expanded and kept
	wantGh := filepath.Join(home, ".config", "gh") + ":/etc/seed/gh:ro"
	if !containsPair(got, "-v", wantGh) {
		t.Fatalf("expected expanded tilde mount %q; got: %s", wantGh, joined)
	}
	// Windows path that does not exist on this machine should be skipped
	if containsSubstring(got, `C:\Users\nope`) {
		t.Fatalf("expected missing Windows path skipped; got: %s", joined)
	}
	// Non-volume flags preserved
	if !containsPair(got, "-e", "FOO=1") || !containsPair(got, "-p", "8080:80") {
		t.Fatalf("expected non-volume flags preserved; got: %s", joined)
	}
}

func TestFilterMissingVolumeMounts_RunAndCommonArgs(t *testing.T) {
	tmp := t.TempDir()
	exists := filepath.Join(tmp, "cert.pem")
	if err := os.WriteFile(exists, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	missing := filepath.Join(tmp, "missing-key.pem")

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.RunArgs.Append(ilist.NewList("-v", filepath.Join(tmp, "nope")+":/run/missing:ro", "-e", "A=1"))
	builder.CommonArgs.Append(ilist.NewList("-v", exists+":/tmp/cert.pem:ro", "-v", missing+":/tmp/key.pem:ro"))

	ctx := FilterMissingVolumeMounts(builder.Build())

	// RunArgs: missing bind removed, -e kept
	runFlat := flattenArgGroups(ctx.RunArgs())
	if containsSubstring(runFlat, "/run/missing") {
		t.Fatalf("run missing mount not filtered: %v", runFlat)
	}
	if !containsPair(runFlat, "-e", "A=1") {
		t.Fatalf("run -e not kept: %v", runFlat)
	}

	// CommonArgs: existing cert kept, missing key dropped
	commonFlat := flattenArgGroups(ctx.CommonArgs())
	if !containsPair(commonFlat, "-v", exists+":/tmp/cert.pem:ro") {
		t.Fatalf("common existing cert not kept: %v", commonFlat)
	}
	if containsSubstring(commonFlat, missing) {
		t.Fatalf("common missing key not filtered: %v", commonFlat)
	}
}

func TestVolumeSource_DoesNotTreatDriveLetterAsUnixSplit(t *testing.T) {
	// Regression: naive strings.Index(":", spec) yields "C" for Windows paths.
	spec := `C:\Users\u\AppData\Roaming\GitHub CLI:/etc/cb-home-seed/.config/gh:ro`
	got := volumeSource(spec)
	if got == "C" {
		t.Fatal("volumeSource incorrectly split on Windows drive-letter colon")
	}
	want := `C:\Users\u\AppData\Roaming\GitHub CLI`
	if got != want {
		t.Fatalf("volumeSource = %q, want %q", got, want)
	}
}

func TestVolumeTarget(t *testing.T) {
	tests := []struct {
		name string
		spec string
		want string
	}{
		{"UnixWithMode", "/home/u/.config/gh:/etc/seed/gh:ro", "/etc/seed/gh"},
		{"UnixNoMode", "~/.config/gh:/etc/seed/gh", "/etc/seed/gh"},
		{"MacAppSupport", "/Users/u/Library/Application Support/pip:/etc/seed/.config/pip:ro", "/etc/seed/.config/pip"},
		{"WindowsSource", `C:\Users\u\AppData\Roaming\pip:/etc/seed/.config/pip:ro`, "/etc/seed/.config/pip"},
		{"NamedVolume", "myvol:/data:ro", "/data"},
		{"SourceOnly", "/only/source", ""},
		{"Empty", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := volumeTarget(tt.spec); got != tt.want {
				t.Fatalf("volumeTarget(%q) = %q, want %q", tt.spec, got, tt.want)
			}
		})
	}
}

// The credential templates offer one host path per platform for the same container
// target. Exactly one of them normally exists, and Docker refuses a duplicate mount
// point -- so at most one may survive, whichever one that is.
func TestFilterMissingVolumeMountItems_PerPlatformAlternatives(t *testing.T) {
	home := t.TempDir()
	macPath := filepath.Join(home, "Library", "Application Support", "pip")
	if err := os.MkdirAll(macPath, 0o755); err != nil {
		t.Fatal(err)
	}

	items := []string{
		"-v", "~/.config/pip:/etc/cb-home-seed/.config/pip:ro",
		"-v", "~/Library/Application Support/pip:/etc/cb-home-seed/.config/pip:ro",
		"-v", "~/AppData/Roaming/pip:/etc/cb-home-seed/.config/pip:ro",
	}

	got := filterMissingVolumeMountItems(items, home)

	want := []string{"-v", macPath + ":/etc/cb-home-seed/.config/pip:ro"}
	if len(got) != len(want) {
		t.Fatalf("expected only the existing alternative kept; got: %v", got)
	}
	if !containsPair(got, want[0], want[1]) {
		t.Fatalf("expected %v; got: %v", want, got)
	}
}

// Two alternatives existing at once used to reach Docker as a duplicate mount point,
// which fails the run outright. The first one wins and the rest are dropped.
func TestFilterMissingVolumeMountItems_DropsDuplicateTargets(t *testing.T) {
	home := t.TempDir()
	for _, dir := range []string{
		filepath.Join(home, ".config", "Cursor"),
		filepath.Join(home, "Library", "Application Support", "Cursor"),
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}

	items := []string{
		"-v", "~/.config/Cursor:/etc/cb-home-seed/.config/Cursor:ro",
		"-v", "~/Library/Application Support/Cursor:/etc/cb-home-seed/.config/Cursor:ro",
	}

	got := filterMissingVolumeMountItems(items, home)

	if len(got) != 2 {
		t.Fatalf("expected a single mount for one target; got: %v", got)
	}
	first := filepath.Join(home, ".config", "Cursor") + ":/etc/cb-home-seed/.config/Cursor:ro"
	if !containsPair(got, "-v", first) {
		t.Fatalf("expected the first existing alternative kept; got: %v", got)
	}
}

func TestMissingVolumeMountNotice(t *testing.T) {
	single := missingVolumeMountNotice("/etc/seed/gh", []string{"~/.config/gh"})
	if !strings.Contains(single, "host path does not exist: ~/.config/gh") {
		t.Fatalf("single-candidate notice should name the path; got: %q", single)
	}

	many := missingVolumeMountNotice("/etc/seed/.config/pip", []string{"~/.config/pip", "~/AppData/Roaming/pip"})
	if !strings.Contains(many, "/etc/seed/.config/pip") ||
		!strings.Contains(many, "~/.config/pip") ||
		!strings.Contains(many, "~/AppData/Roaming/pip") {
		t.Fatalf("multi-candidate notice should name the target and every path tried; got: %q", many)
	}
}

func flattenArgGroups(args ilist.List[ilist.List[string]]) []string {
	var out []string
	args.Range(func(_ int, group ilist.List[string]) bool {
		out = append(out, group.Slice()...)
		return true
	})
	return out
}

func containsPair(items []string, a, b string) bool {
	for i := 0; i+1 < len(items); i++ {
		if items[i] == a && items[i+1] == b {
			return true
		}
	}
	return false
}

func containsSubstring(items []string, sub string) bool {
	for _, s := range items {
		if strings.Contains(s, sub) {
			return true
		}
	}
	return false
}
