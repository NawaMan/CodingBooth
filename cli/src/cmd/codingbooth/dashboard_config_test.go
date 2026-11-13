// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/dash"
)

func TestDashProjectConfig(t *testing.T) {
	write := func(t *testing.T, dir, name, content string) {
		t.Helper()
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cases := []struct {
		name  string
		files map[string]string // "" = no .booth at all
		want  dash.ProjectConfig
	}{
		{"no .booth", nil, dash.ProjectConfig{}},
		{"hand-written", map[string]string{"Boothfile": "# my own\nsetup go\n"},
			dash.ProjectConfig{Exists: true}},
		{"from the Boothfile", map[string]string{
			"Boothfile":   "# Configured by: booth config --no-tui --overwrite --select go/zig --set debug=true\n",
			"config.toml": "# Configured by: booth config --select other\n"},
			dash.ProjectConfig{Exists: true, Generated: true, Items: []string{"go", "zig"}}},
		{"from config.toml when the Boothfile has none", map[string]string{
			"Boothfile":   "setup go\n",
			"config.toml": "# Configured by: booth config --no-tui --select 'go+go-pkg:\"github.com/x@latest\"'\n"},
			dash.ProjectConfig{Exists: true, Generated: true, Items: []string{`go+go-pkg:"github.com/x@latest"`}}},
		{"several --select", map[string]string{
			"config.toml": "# Configured by: booth config --select go --select zig\n"},
			dash.ProjectConfig{Exists: true, Generated: true, Items: []string{"go", "zig"}}},
		{"a quoted / stays in its item", map[string]string{
			"config.toml": "# Configured by: booth config --select 'go+go-pkg:\"github.com/a/b@latest\"/zig+zls/shell-history'\n"},
			dash.ProjectConfig{Exists: true, Generated: true, Items: []string{`go+go-pkg:"github.com/a/b@latest"`, "zig+zls", "shell-history"}}},
		{"no templates", map[string]string{"config.toml": "# Configured by: booth config --no-tui --overwrite\n"},
			dash.ProjectConfig{Exists: true, Generated: true}},
		{"a malformed header does not exit", map[string]string{"config.toml": "# Configured by: booth config --port\n"},
			dash.ProjectConfig{Exists: true, Generated: true}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := filepath.Join(t.TempDir(), ".booth")
			for name, content := range c.files {
				write(t, dir, name, content)
			}
			got, err := dashProjectConfig(dir)
			if err != nil || !reflect.DeepEqual(got, c.want) {
				t.Errorf("got %+v, %v; want %+v", got, err, c.want)
			}
		})
	}
}
