// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func TestParseArgs_PublicFlag(t *testing.T) {
	args := ilist.NewListFromSlice([]string{"--public"})
	config := appctx.AppConfig{
		RunArgs:   ilist.SemicolonStringList{List: ilist.NewList[string]()},
		BuildArgs: ilist.SemicolonStringList{List: ilist.NewList[string]()},
		Cmds:      ilist.SemicolonStringList{List: ilist.NewList[string]()},
	}
	err := parseArgs(args, &config)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !config.Public {
		t.Fatal("expected Public to be true")
	}
}

func TestValidatePasswordFile_PermissionsTooPermissive(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("permission check not applicable on Windows")
	}

	dir := t.TempDir()
	pwFile := filepath.Join(dir, ".booth.password")
	if err := os.WriteFile(pwFile, []byte("secret\n"), 0644); err != nil {
		t.Fatal(err)
	}

	err := validatePasswordFile(pwFile, dir)
	if err == nil {
		t.Fatal("expected error for permissive file, got nil")
	}
	if !strings.Contains(err.Error(), "too-permissive") {
		t.Fatalf("expected 'too-permissive' in error, got %q", err.Error())
	}
}

func TestValidatePasswordFile_CorrectPermissions(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("permission check not applicable on Windows")
	}

	// Need a git repo for the gitignore check to work
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}

	pwFile := filepath.Join(boothDir, ".booth.password")
	if err := os.WriteFile(pwFile, []byte("secret\n"), 0600); err != nil {
		t.Fatal(err)
	}

	// No git repo means gitignore check is skipped
	err := validatePasswordFile(pwFile, dir)
	if err != nil {
		t.Fatalf("unexpected error for correct permissions (no git repo): %v", err)
	}
}

func TestCheckPasswordFileGitignored_NotGitRepo(t *testing.T) {
	dir := t.TempDir()
	pwFile := filepath.Join(dir, ".booth", ".booth.password")

	// Not a git repo — should skip check and return nil
	err := checkPasswordFileGitignored(pwFile, dir)
	if err != nil {
		t.Fatalf("expected nil for non-git-repo, got %v", err)
	}
}

func TestCheckPasswordFileGitignored_NotIgnored(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not available")
	}

	dir := t.TempDir()

	// Init a git repo
	cmd := exec.Command("git", "init", dir)
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		t.Fatal(err)
	}

	// Create .booth/.booth.password but NO .gitignore
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	pwFile := filepath.Join(boothDir, ".booth.password")
	if err := os.WriteFile(pwFile, []byte("secret\n"), 0600); err != nil {
		t.Fatal(err)
	}

	err := checkPasswordFileGitignored(pwFile, dir)
	if err == nil {
		t.Fatal("expected error for non-gitignored file, got nil")
	}
	if !strings.Contains(err.Error(), "NOT gitignored") {
		t.Fatalf("expected 'NOT gitignored' in error, got %q", err.Error())
	}
}

func TestCheckPasswordFileGitignored_Ignored(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not available")
	}

	dir := t.TempDir()

	// Init a git repo
	cmd := exec.Command("git", "init", dir)
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		t.Fatal(err)
	}

	// Create .booth/.gitignore with .booth.password entry
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	gitignore := filepath.Join(boothDir, ".gitignore")
	if err := os.WriteFile(gitignore, []byte(".booth.password\n"), 0644); err != nil {
		t.Fatal(err)
	}

	pwFile := filepath.Join(boothDir, ".booth.password")
	if err := os.WriteFile(pwFile, []byte("secret\n"), 0600); err != nil {
		t.Fatal(err)
	}

	err := checkPasswordFileGitignored(pwFile, dir)
	if err != nil {
		t.Fatalf("expected nil for gitignored file, got %v", err)
	}
}
