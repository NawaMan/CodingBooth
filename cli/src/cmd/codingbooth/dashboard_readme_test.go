// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// lookFor is an exec.LookPath that finds only have.
func lookFor(have ...string) func(string) (string, error) {
	return func(name string) (string, error) {
		for _, h := range have {
			if h == name {
				return "/bin/" + name, nil
			}
		}
		return "", errors.New(name + " is not installed")
	}
}

func readmeDir(t *testing.T, names ...string) string {
	t.Helper()
	dir := t.TempDir()
	for _, name := range names {
		path := filepath.Join(dir, name)
		if strings.HasSuffix(name, "/") {
			if err := os.MkdirAll(path, 0o755); err != nil {
				t.Fatal(err)
			}
			continue
		}
		if err := os.WriteFile(path, []byte("# "+name+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestFindReadme(t *testing.T) {
	cases := []struct {
		name  string
		files []string
		want  string // "" = none
	}{
		{"none", []string{"main.go", "NOTES.md"}, ""},
		{"markdown", []string{"README.md", "main.go"}, "README.md"},
		{"any case", []string{"Readme.MD"}, "Readme.MD"},
		{"markdown before plain", []string{"README", "README.md", "README.txt"}, "README.md"},
		{"plain before txt", []string{"README.txt", "README"}, "README"},
		{"txt", []string{"readme.txt"}, "readme.txt"},
		{"rst last", []string{"README.rst", "readme.txt"}, "readme.txt"},
		{"a folder named README is not one", []string{"README.md/", "README.txt"}, "README.txt"},
		{"not a prefix match", []string{"README-dev.md", "READMEs.md"}, ""},
	}
	for _, c := range cases {
		dir := readmeDir(t, c.files...)
		want := ""
		if c.want != "" {
			want = filepath.Join(dir, c.want)
		}
		if got := findReadme(dir); got != want {
			t.Errorf("%s: findReadme = %q, want %q", c.name, got, want)
		}
	}
	if got := findReadme(filepath.Join(t.TempDir(), "gone")); got != "" {
		t.Errorf("a folder that is not there: %q, want none", got)
	}
}

func TestReadmeCommandPicksThePager(t *testing.T) {
	md := readmeDir(t, "README.md")
	txt := readmeDir(t, "README.txt")
	cases := []struct {
		name string
		dir  string
		have []string
		want []string // the command; nil = an error
	}{
		{"markdown with glow", md, []string{"glow", "less"}, []string{"/bin/glow", "-p", filepath.Join(md, "README.md")}},
		{"markdown without glow", md, []string{"less", "more"}, []string{"/bin/less", "-R", filepath.Join(md, "README.md")}},
		{"plain text is not glow's", txt, []string{"glow", "less"}, []string{"/bin/less", "-R", filepath.Join(txt, "README.txt")}},
		{"no less", txt, []string{"more"}, []string{"/bin/more", filepath.Join(txt, "README.txt")}},
		{"no pager", txt, nil, nil},
	}
	for _, c := range cases {
		cmd, err := readmeCommand(c.dir, lookFor(c.have...))
		if c.want == nil {
			if err == nil || cmd != nil || !strings.Contains(err.Error(), "install glow or less") {
				t.Errorf("%s: cmd %v err %v, want the no-pager error", c.name, cmd, err)
			}
			continue
		}
		if err != nil || cmd == nil || !reflect.DeepEqual(cmd.Args, c.want) {
			t.Errorf("%s: cmd %v err %v, want %v", c.name, cmd, err, c.want)
		}
	}
	// No README: no command and no error, whatever is installed.
	if cmd, err := readmeCommand(readmeDir(t, "main.go"), lookFor()); cmd != nil || err != nil {
		t.Errorf("no README: cmd %v err %v, want neither", cmd, err)
	}
}
