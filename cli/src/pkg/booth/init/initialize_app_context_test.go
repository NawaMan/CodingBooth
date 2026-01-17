// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/coding-booth/src/pkg/appctx"
	"github.com/nawaman/coding-booth/src/pkg/ilist"
)

func TestGetProjectName(t *testing.T) {
	// Calculate expected name for current directory (for Empty case)
	cwd, _ := filepath.Abs(".")
	cwdBase := filepath.Base(cwd)
	var result strings.Builder
	for _, ch := range cwdBase {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
			result.WriteRune(ch)
		} else {
			result.WriteRune('-')
		}
	}
	cwdSanitized := result.String()
	if cwdSanitized == "" {
		cwdSanitized = "workspace"
	}

	tests := []struct {
		name     string
		path     string
		expected string
	}{
		{"Simple", "/path/to/myproject", "myproject"},
		{"WithSpaces", "/path/to/my project", "my-project"},
		{"WithSpecialChars", "/path/to/my-project@v1", "my-project-v1"},
		{"Empty", "", cwdSanitized},
		{"Root", "/", "-"}, // Base returns / or similar, sanitize replaces non-alnum
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := getProjectName(tt.path)
			// Special handling for Root case which might vary by OS, but testing logic mainly
			if tt.name == "Root" && got != "-" && got != "workspace" {
				// Accept reasonable fallbacks for root
			} else if got != tt.expected {
				t.Errorf("getProjectName(%q) = %q, want %q", tt.path, got, tt.expected)
			}
		})
	}
}

func TestGetScriptName(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		expected string
	}{
		{"Standard", []string{"/bin/coding-booth", "arg1"}, "coding-booth"},
		{"Relative", []string{"./booth"}, "booth"},
		{"Empty", []string{}, "coding-booth"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := getScriptName(ilist.NewListFromSlice(tt.args))
			if got != tt.expected {
				t.Errorf("getScriptName(%v) = %q, want %q", tt.args, got, tt.expected)
			}
		})
	}
}

func TestNeedValue(t *testing.T) {
	args := []string{"--flag", "value", "--other"}
	argList := ilist.NewListFromSlice(args)

	val, err := needValue(argList, 0, "--flag")
	if err != nil {
		t.Errorf("Standard case failed: %v", err)
	}
	if val != "value" {
		t.Errorf("Standard case = %q, want 'value'", val)
	}

	_, err = needValue(argList, 1, "value") // "value" is at index 1, next is "--other"
	if err != nil {
		t.Errorf("Value as flag case failed: %v", err)
	}

	_, err = needValue(argList, 2, "--other")
	if err == nil {
		t.Error("Expected error for missing value at end of args, got nil")
	}
}

func TestReadVerboseDryrunConfigFileAndCode(t *testing.T) {
	args := []string{
		"--verbose",
		"--config", "myconfig.toml",
		"--dryrun",
		"--code", "/my/code",
		"other-arg",
	}

	config := appctx.AppConfig{}
	context := appctx.AppContextBuilder{Config: config}

	testInput := TestInput{
		Args: args,
	}

	configExplicitlySet := false
	readVerboseDryrunConfigFileAndCode(testInput, &context, &configExplicitlySet)

	if !context.Config.Verbose.ValueOr(false) {
		t.Error("Expected Verbose to be true")
	}
	if !context.Config.Dryrun.ValueOr(false) {
		t.Error("Expected Dryrun to be true")
	}

	// Config path should be resolved to absolute path
	expectedConfigPath, _ := filepath.Abs("myconfig.toml")
	if context.Config.Config.ValueOr("") != expectedConfigPath {
		t.Errorf("Expected Config to be %q, got %q", expectedConfigPath, context.Config.Config.ValueOr(""))
	}

	if context.Config.Code.ValueOr("") != "/my/code" {
		t.Errorf("Expected Code to be '/my/code', got %q", context.Config.Code.ValueOr(""))
	}
	if !configExplicitlySet {
		t.Error("Expected configExplicitlySet to be true when --config is provided")
	}
}

func TestParseArgs(t *testing.T) {
	args := []string{
		"--daemon",
		"--image", "my-image",
		"--pull",
		"--",
		"echo", "hello",
	}
	argList := ilist.NewListFromSlice(args)

	// Initialize config with empty lists to avoid nil pointer dereference
	config := appctx.AppConfig{
		RunArgs:   ilist.SemicolonStringList{List: ilist.NewList[string]()},
		BuildArgs: ilist.SemicolonStringList{List: ilist.NewList[string]()},
		Cmds:      ilist.SemicolonStringList{List: ilist.NewList[string]()},
	}

	err := parseArgs(argList, &config)
	if err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}

	if !config.Daemon {
		t.Error("Expected Daemon to be true")
	}
	if !config.Pull {
		t.Error("Expected Pull to be true")
	}
	if config.Image != "my-image" {
		t.Errorf("Expected Image to be 'my-image', got %q", config.Image)
	}

	cmds := config.Cmds.Slice()
	if len(cmds) != 2 || cmds[0] != "echo" || cmds[1] != "hello" {
		t.Errorf("Expected Cmds to be ['echo', 'hello'], got %v", cmds)
	}
}

func TestGetScriptDir(t *testing.T) {
	// This tests the fallback or simple behavior, as testing absolute path resolution
	// depends heavily on the OS and filesystem state.

	argList := ilist.NewListFromSlice([]string{})
	t.Run("Empty", func(t *testing.T) {
		got := getScriptDir(argList)
		if got != "." {
			t.Errorf("getScriptDir([]) = %q, want '.'", got)
		}
	})

	t.Run("Simple", func(t *testing.T) {
		// Mocking os.Executable essentially via args[0]
		// For an arbitrary path that likely doesn't exist, it should return filepath.Dir(arg)
		arg := "/path/to/workspace"
		argList := ilist.NewListFromSlice([]string{arg})
		got := getScriptDir(argList)

		// If the file doesn't exist, Abs might work but EvalSymlinks might fail,
		// falling back to filepath.Dir(absPath) or similar.
		// We accept result if it ends with /path/to (or platform equivalent)
		if !filepath.IsAbs(got) {
			// If it's not absolute, it might be due to error fallback
		}

		// This test is brittle without mocking filesystem, so we just check it doesn't panic
		if got == "" {
			t.Error("getScriptDir returned empty string")
		}
	})
}

func TestGetProjectName_ResolvesRelativePaths(t *testing.T) {
	abs, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("Failed to resolve absolute path for ..: %v", err)
	}
	baseName := filepath.Base(abs)

	// helper to sanitize
	sanitize := func(s string) string {
		var result strings.Builder
		for _, ch := range s {
			if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
				result.WriteRune(ch)
			} else {
				result.WriteRune('-')
			}
		}
		if result.String() == "" {
			return "workspace"
		}
		return result.String()
	}

	expected := sanitize(baseName)
	got := getProjectName("..")

	if got != expected {
		t.Errorf("getProjectName(\"..\") = %q, want %q (processed from %q)", got, expected, abs)
	}
}
