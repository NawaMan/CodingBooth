// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package prepare

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const ubuntu2604 = `PRETTY_NAME="Ubuntu 26.04 LTS"
NAME="Ubuntu"
VERSION_ID="26.04"
ID=ubuntu
`

func envOf(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestCheckMachine(t *testing.T) {
	ok := ParseOSRelease(ubuntu2604)
	gha := envOf(map[string]string{"GITHUB_ACTIONS": "true", "GITHUB_ENV": "/e", "GITHUB_PATH": "/p"})
	none := envOf(nil)

	if err := CheckMachine(Ubuntu, ok, none); err != nil {
		t.Errorf("ubuntu on 26.04: %v", err)
	}
	if err := CheckMachine(GHA, ok, gha); err != nil {
		t.Errorf("gha on a runner: %v", err)
	}
	if err := CheckMachine(GHA, ok, none); err == nil || !strings.Contains(err.Error(), "GitHub Actions runner") {
		t.Errorf("gha off a runner: want a runner error, got %v", err)
	}
	if err := CheckMachine(GHA, ok, envOf(map[string]string{"GITHUB_ACTIONS": "true"})); err == nil {
		t.Error("gha without GITHUB_ENV: want an error")
	}
	old := ParseOSRelease("PRETTY_NAME=\"Ubuntu 24.04.3 LTS\"\nID=ubuntu\nVERSION_ID=\"24.04\"\n")
	if err := CheckMachine(Ubuntu, old, none); err == nil || !strings.Contains(err.Error(), "Ubuntu 24.04.3 LTS") || !strings.Contains(err.Error(), "26.04") {
		t.Errorf("ubuntu 24.04: want a release error naming both, got %v", err)
	}
	if err := CheckMachine(Ubuntu, ParseOSRelease("ID=debian\nVERSION_ID=13\n"), none); err == nil {
		t.Error("debian: want an error")
	}
}

func TestResolveVariant(t *testing.T) {
	cases := []struct {
		target        Target
		flag, config  string
		want          string
		wantNote, err bool
	}{
		{GHA, "", "", "base", false, false},
		{GHA, "", "xfce", "base", true, false},
		{GHA, "", "base", "base", false, false},
		{GHA, "base", "notebook", "base", true, false},
		{GHA, "console", "", "base", false, false},
		{GHA, "codeserver", "", "", false, true},
		{Ubuntu, "", "", "base", false, false},
		{Ubuntu, "", "xfce", "desktop-xfce", false, false},
		{Ubuntu, "kde", "xfce", "desktop-kde", false, false},
		{Ubuntu, "ide", "", "codeserver", false, false},
		{Ubuntu, "notebook", "", "notebook", false, false},
		{Ubuntu, "nope", "", "", false, true},
		{Ubuntu, "", "nope", "", false, true},
	}
	for _, c := range cases {
		got, note, err := ResolveVariant(c.target, c.flag, c.config)
		if (err != nil) != c.err || got != c.want || (note != "") != c.wantNote {
			t.Errorf("ResolveVariant(%s, %q, %q) = %q, %q, %v", c.target, c.flag, c.config, got, note, err)
		}
	}
}

func TestRunArgsEnv(t *testing.T) {
	env, skipped := RunArgsEnv([]string{
		"-e", "N8N_SANDBOX_PORT=21280",
		"--env", "A=b=c",
		"--env=Q='quoted'",
		"-eX=1",
		"-e", "FROM_HOST",
		"-v", "~/.npmrc:/etc/cb-home-seed/.npmrc:ro",
		"--publish", "21200:21200",
	})
	want := []EnvVar{{"N8N_SANDBOX_PORT", "21280"}, {"A", "b=c"}, {"Q", "'quoted'"}, {"X", "1"}}
	if !reflect.DeepEqual(env, want) {
		t.Errorf("env = %v, want %v", env, want)
	}
	if len(skipped) != 5 || !strings.Contains(skipped[0], "FROM_HOST") {
		t.Errorf("skipped = %v", skipped)
	}
}

func TestRewriteHome(t *testing.T) {
	in := []EnvVar{{"GOMODCACHE", "/home/coder/go/pkg/mod"}, {"P", "/home/coder/a:/home/coder/b"}, {"N", "/opt/x"}}
	got := RewriteHome(in, "/home/runner")
	want := []EnvVar{{"GOMODCACHE", "/home/runner/go/pkg/mod"}, {"P", "/home/runner/a:/home/runner/b"}, {"N", "/opt/x"}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("RewriteHome = %v, want %v", got, want)
	}
	if in[0].Value != "/home/coder/go/pkg/mod" {
		t.Error("RewriteHome changed its input")
	}
}

func TestConfigProfile(t *testing.T) {
	got := ConfigProfile("gha", []EnvVar{{"GOMODCACHE", "/home/runner/go/pkg/mod"}, {"Q", "it's"}})
	want := "# Profile: booth prepare's target and the -e run-args of .booth/config.toml.\n" +
		"export CB_TARGET='gha'\n" +
		"export GOMODCACHE='/home/runner/go/pkg/mod'\n" +
		"export Q='it'\\''s'\n"
	if got != want {
		t.Errorf("ConfigProfile =\n%s\nwant\n%s", got, want)
	}
	if got := ConfigProfile("host", nil); !strings.Contains(got, "export CB_TARGET='host'\n") {
		t.Errorf("no env: %q", got)
	}
}

func TestLoadConfig(t *testing.T) {
	dir := t.TempDir()
	if c, err := LoadConfig(filepath.Join(dir, "missing.toml")); err != nil || c.Variant != "" {
		t.Errorf("missing file: %v %v", c, err)
	}
	p := filepath.Join(dir, "config.toml")
	os.WriteFile(p, []byte("variant = \"xfce\"\ndind = true\nrun-args = [\n  \"-e\", \"K=V\",\n]\ncache-dirs = [\"x\"]\n"), 0644)
	c, err := LoadConfig(p)
	if err != nil || c.Variant != "xfce" || !c.Dind || !reflect.DeepEqual(c.RunArgs, []string{"-e", "K=V"}) {
		t.Errorf("LoadConfig = %+v, %v", c, err)
	}
}

func TestDecideUser(t *testing.T) {
	if _, err := DecideUser(0, "root", ""); err == nil || !strings.Contains(err.Error(), "--add-user <name>") {
		t.Errorf("root without --add-user: want the hint, got %v", err)
	}
	if d, err := DecideUser(0, "root", "dev"); err != nil || d != (UserDecision{Name: "dev", Create: true}) {
		t.Errorf("root --add-user dev = %+v, %v", d, err)
	}
	for _, bad := range []string{"root", "1dev", "Dev", "a b", "-x"} {
		if _, err := DecideUser(0, "root", bad); err == nil {
			t.Errorf("--add-user %q: want an error", bad)
		}
	}
	if d, err := DecideUser(1001, "runner", ""); err != nil || d != (UserDecision{Name: "runner", UseSudo: true}) {
		t.Errorf("runner = %+v, %v", d, err)
	}
	if _, err := DecideUser(1001, "runner", "dev"); err == nil {
		t.Error("--add-user as non-root: want an error")
	}
}

func TestGitHubExports(t *testing.T) {
	before := map[string]string{"PATH": "/usr/bin:/bin", "KEEP": "1", "CHANGED": "old", "GITHUB_ENV": "/e"}
	after := map[string]string{
		"PATH":    "/opt/codingbooth/setups:/home/runner/.local/bin:/usr/bin:/bin:/usr/local/go/bin",
		"KEEP":    "1",
		"CHANGED": "new",
		"NEW":     "line1\nline2",
		"SHLVL":   "2", "PWD": "/x", "GITHUB_ENV": "/other", "BASH_FUNC_f%%": "() { :; }",
	}
	env, path := GitHubExports(before, after, "EOF")
	if env != "CHANGED<<EOF\nnew\nEOF\nNEW<<EOF\nline1\nline2\nEOF\n" {
		t.Errorf("env file = %q", env)
	}
	// GitHub puts the last line first, so the lines are the login order reversed.
	if want := []string{"/usr/local/go/bin", "/home/runner/.local/bin", "/opt/codingbooth/setups"}; !reflect.DeepEqual(path, want) {
		t.Errorf("path lines = %v, want %v", path, want)
	}
}

func TestParseEnv0(t *testing.T) {
	got := ParseEnv0([]byte("A=1\x00B=x=y\x00C=multi\nline\x00"))
	want := map[string]string{"A": "1", "B": "x=y", "C": "multi\nline"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("ParseEnv0 = %v", got)
	}
}

func TestReportFailures(t *testing.T) {
	r := "== go-example\nPASS  setup go\nFAIL  setup zig  (last line: boom)\nDROP  port = 1\nFAIL  example: t1\n"
	if got := ReportFailures(r); len(got) != 2 || !strings.Contains(got[0], "zig") {
		t.Errorf("ReportFailures = %v", got)
	}
}

func tarGz(t *testing.T, files map[string]struct {
	mode int64
	body string
}) []byte {
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for name, f := range files {
		tw.WriteHeader(&tar.Header{Name: name, Mode: f.mode, Size: int64(len(f.body)), Typeflag: tar.TypeReg})
		tw.Write([]byte(f.body))
	}
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

func TestExtractKeepsModesAndRejectsEscapes(t *testing.T) {
	dir := t.TempDir()
	data := tarGz(t, map[string]struct {
		mode int64
		body string
	}{
		"experiments/host-provision/base-provision.sh": {0755, "#!/bin/bash\n"},
		"variants/base/setups/go--setup.sh":            {0755, "#!/bin/bash\n"},
		"version.txt":                                  {0644, "0.81.0\n"},
	})
	if err := extractTarGz(bytes.NewReader(data), dir); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(dir, "experiments/host-provision/base-provision.sh"))
	if err != nil || info.Mode().Perm()&0100 == 0 {
		t.Errorf("script mode: %v %v", info, err)
	}
	if err := CheckSource(dir); err != nil {
		t.Errorf("CheckSource on the extracted kit: %v", err)
	}
	if err := CheckSource(t.TempDir()); err == nil {
		t.Error("CheckSource on an empty folder: want an error")
	}

	bad := tarGz(t, map[string]struct {
		mode int64
		body string
	}{"../escape": {0644, "x"}})
	if err := extractTarGz(bytes.NewReader(bad), t.TempDir()); err == nil {
		t.Error("../escape: want an error")
	}
}

func TestCBTarget(t *testing.T) {
	if GHA.CBTarget() != "gha" || Ubuntu.CBTarget() != "host" {
		t.Error("CB_TARGET values")
	}
	if _, err := ParseTarget("host"); err == nil {
		t.Error("ParseTarget(host): want an error; the command word is ubuntu")
	}
}
