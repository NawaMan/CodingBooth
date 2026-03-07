// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

func TestApplyEnvFile_DotEnvNotAutoDetected(t *testing.T) {
	// .env in project root should NOT be auto-detected — it belongs to the application
	tmpDir := t.TempDir()

	// Create .env file in workspace
	envFile := filepath.Join(tmpDir, ".env")
	if err := os.WriteFile(envFile, []byte("FOO=BAR"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	// Verify NO --env-file was added
	args := flattenArgs(newCtx.CommonArgs())
	for _, arg := range args {
		if arg == "--env-file" {
			t.Errorf("Expected NO --env-file arg for .env auto-detection, got args: %v", args)
		}
	}
}

func TestApplyEnvFile_Explicit(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "cb_test_explicit")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	myEnv := filepath.Join(tmpDir, "my.env")
	if err := os.WriteFile(myEnv, []byte("Make=ItSo"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.EnvFile = myEnv // Explicitly set

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())
	found := false
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			if args[i+1] == myEnv {
				found = true
				break
			}
		}
	}
	if !found {
		t.Errorf("Expected --env-file %s, got args: %v", myEnv, args)
	}
}

func TestApplyEnvFile_Disabled(t *testing.T) {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.EnvFile = "-" // Explicitly disabled
	builder.Config.Verbose = nillable.NewNillableBool(true)

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())
	for _, arg := range args {
		if arg == "--env-file" {
			t.Errorf("Expected NO --env-file arg when disabled, got args: %v", args)
		}
	}
}

// --- .env tests ---

func TestApplyEnvFile_BoothEnv_Only(t *testing.T) {
	// .booth/.env exists, no user env-file → single --env-file added
	tmpDir := t.TempDir()

	// Create .booth/.env (no git repo → gitignore check is skipped)
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	boothEnv := filepath.Join(boothDir, ".env")
	if err := os.WriteFile(boothEnv, []byte("SECRET=value"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())
	found := false
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) && args[i+1] == boothEnv {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("Expected --env-file %s, got args: %v", boothEnv, args)
	}
}

func TestApplyEnvFile_BoothEnv_WithDotEnvPresent(t *testing.T) {
	// Both .booth/.env and project .env exist → only .booth/.env is included (project .env is ignored)
	tmpDir := t.TempDir()

	// Create .booth/.env
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	boothEnv := filepath.Join(boothDir, ".env")
	if err := os.WriteFile(boothEnv, []byte("SECRET=local"), 0644); err != nil {
		t.Fatal(err)
	}

	// Create .env in workspace (should be ignored)
	envFile := filepath.Join(tmpDir, ".env")
	if err := os.WriteFile(envFile, []byte("SECRET=override"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())

	// Expect only one --env-file flag for .env
	envFileArgs := []string{}
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			envFileArgs = append(envFileArgs, args[i+1])
		}
	}
	if len(envFileArgs) != 1 {
		t.Fatalf("Expected 1 --env-file arg (booth env only), got %d: %v", len(envFileArgs), args)
	}
	if envFileArgs[0] != boothEnv {
		t.Errorf("Expected --env-file %s, got %s", boothEnv, envFileArgs[0])
	}
}

func TestApplyEnvFile_BoothEnv_WithDisabledEnvFile(t *testing.T) {
	// .booth/.env exists + env-file = "-" → only .booth/.env is included
	tmpDir := t.TempDir()

	// Create .booth/.env
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	boothEnv := filepath.Join(boothDir, ".env")
	if err := os.WriteFile(boothEnv, []byte("SECRET=value"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)
	builder.Config.EnvFile = "-" // Disabled

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())

	// Should have exactly one --env-file for .env
	envFileArgs := []string{}
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			envFileArgs = append(envFileArgs, args[i+1])
		}
	}
	if len(envFileArgs) != 1 {
		t.Fatalf("Expected 1 --env-file arg (booth env only), got %d: %v", len(envFileArgs), args)
	}
	if envFileArgs[0] != boothEnv {
		t.Errorf("Expected --env-file %s, got %s", boothEnv, envFileArgs[0])
	}
}

func TestApplyEnvFile_NoBoothEnv_NoDotEnv(t *testing.T) {
	// No .booth/.env, no project .env → no --env-file args
	tmpDir := t.TempDir()

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())
	for _, arg := range args {
		if arg == "--env-file" {
			t.Errorf("Expected NO --env-file args, got: %v", args)
		}
	}
}

// --- .env gitignore check tests ---

func TestCheckBoothEnvGitignored_NotGitRepo(t *testing.T) {
	dir := t.TempDir()
	boothEnv := filepath.Join(dir, ".booth", ".env")

	// Not a git repo — should skip check and return nil
	err := checkBoothEnvGitignored(boothEnv, dir)
	if err != nil {
		t.Fatalf("expected nil for non-git-repo, got %v", err)
	}
}

func TestCheckBoothEnvGitignored_NotIgnored(t *testing.T) {
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

	// Create .booth/.env but NO .gitignore
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	boothEnv := filepath.Join(boothDir, ".env")
	if err := os.WriteFile(boothEnv, []byte("SECRET=value"), 0644); err != nil {
		t.Fatal(err)
	}

	err := checkBoothEnvGitignored(boothEnv, dir)
	if err == nil {
		t.Fatal("expected error for non-gitignored file, got nil")
	}
	if !strings.Contains(err.Error(), "NOT gitignored") {
		t.Fatalf("expected 'NOT gitignored' in error, got %q", err.Error())
	}
}

func TestCheckBoothEnvGitignored_Ignored(t *testing.T) {
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

	// Create .booth/.gitignore with .env entry
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	gitignore := filepath.Join(boothDir, ".gitignore")
	if err := os.WriteFile(gitignore, []byte(".env\n"), 0644); err != nil {
		t.Fatal(err)
	}

	boothEnv := filepath.Join(boothDir, ".env")
	if err := os.WriteFile(boothEnv, []byte("SECRET=value"), 0644); err != nil {
		t.Fatal(err)
	}

	err := checkBoothEnvGitignored(boothEnv, dir)
	if err != nil {
		t.Fatalf("expected nil for gitignored file, got %v", err)
	}
}
