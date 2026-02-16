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

func TestApplyEnvFile_Default(t *testing.T) {
	// Setup temporary directory as workspace
	tmpDir, err := os.MkdirTemp("", "cb_test_default")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create .env file in workspace
	envFile := filepath.Join(tmpDir, ".env")
	if err := os.WriteFile(envFile, []byte("FOO=BAR"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	// Mock Workspace path by assuming the function uses builder.Config or we can set it somehow?
	// ApplyEnvFile uses ctx.Code() which usually comes from Config.Code or calculated.
	// Let's check how ctx.Code() is derived. It seems it might be missing in AppContextBuilder for simple tests if not set.
	// Looking at AppContext (implied from previous reads), it seems to have a Code() method.
	// For testing, we might need to set the Workspace dir in the context.
	// Let's assume there is a way to set it in builder or we'll need to mock it.

	// Wait, ApplyEnvFile logic:
	// candidate := ctx.Code() + "/.env"
	// if candidate == "" { candidate = "./.env" }

	// If ctx.Code() is empty, it checks "./.env".
	// So we can change Cwd to tmpDir to test "./.env" path or set Workspace in context.

	// Set Workspace explicitely to tmpDir
	builder.Config.Code = nillable.NewNillableString(tmpDir)

	ctx := builder.Build()

	// Execute
	newCtx := ApplyEnvFile(ctx)

	// Verify
	// It should have added --env-file ./.env to CommonArgs
	args := flattenArgs(newCtx.CommonArgs())
	found := false
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			if args[i+1] == "./.env" || args[i+1] == envFile {
				found = true
				break
			}
		}
	}

	if !found {
		t.Errorf("Expected --env-file arg to be added, got args: %v", args)
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

// --- .env-local tests ---

func TestApplyEnvFile_EnvLocal_Only(t *testing.T) {
	// .booth/.env-local exists, no user env-file → single --env-file added
	tmpDir := t.TempDir()

	// Create .booth/.env-local (no git repo → gitignore check is skipped)
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	envLocal := filepath.Join(boothDir, ".env-local")
	if err := os.WriteFile(envLocal, []byte("SECRET=value"), 0644); err != nil {
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
		if arg == "--env-file" && i+1 < len(args) && args[i+1] == envLocal {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("Expected --env-file %s, got args: %v", envLocal, args)
	}
}

func TestApplyEnvFile_EnvLocal_WithUserEnvFile(t *testing.T) {
	// Both .env-local and user .env exist → two --env-file flags, .env-local first
	tmpDir := t.TempDir()

	// Create .booth/.env-local
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	envLocal := filepath.Join(boothDir, ".env-local")
	if err := os.WriteFile(envLocal, []byte("SECRET=local"), 0644); err != nil {
		t.Fatal(err)
	}

	// Create .env in workspace
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

	// Expect two --env-file flags: .env-local first, .env second
	envFileArgs := []string{}
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			envFileArgs = append(envFileArgs, args[i+1])
		}
	}
	if len(envFileArgs) != 2 {
		t.Fatalf("Expected 2 --env-file args, got %d: %v", len(envFileArgs), args)
	}
	if envFileArgs[0] != envLocal {
		t.Errorf("Expected first --env-file to be %s, got %s", envLocal, envFileArgs[0])
	}
	if envFileArgs[1] != envFile {
		t.Errorf("Expected second --env-file to be %s, got %s", envFile, envFileArgs[1])
	}
}

func TestApplyEnvFile_EnvLocal_WithDisabledEnvFile(t *testing.T) {
	// .env-local exists + env-file = "-" → only .env-local is included
	tmpDir := t.TempDir()

	// Create .booth/.env-local
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	envLocal := filepath.Join(boothDir, ".env-local")
	if err := os.WriteFile(envLocal, []byte("SECRET=value"), 0644); err != nil {
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

	// Should have exactly one --env-file for .env-local
	envFileArgs := []string{}
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			envFileArgs = append(envFileArgs, args[i+1])
		}
	}
	if len(envFileArgs) != 1 {
		t.Fatalf("Expected 1 --env-file arg (env-local only), got %d: %v", len(envFileArgs), args)
	}
	if envFileArgs[0] != envLocal {
		t.Errorf("Expected --env-file %s, got %s", envLocal, envFileArgs[0])
	}
}

func TestApplyEnvFile_NoEnvLocal(t *testing.T) {
	// No .env-local → unchanged behavior (backward compatible)
	tmpDir := t.TempDir()

	// Create .env in workspace but NO .env-local
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

	args := flattenArgs(newCtx.CommonArgs())

	// Should have exactly one --env-file for .env
	envFileArgs := []string{}
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			envFileArgs = append(envFileArgs, args[i+1])
		}
	}
	if len(envFileArgs) != 1 {
		t.Fatalf("Expected 1 --env-file arg, got %d: %v", len(envFileArgs), args)
	}
	if envFileArgs[0] != envFile {
		t.Errorf("Expected --env-file %s, got %s", envFile, envFileArgs[0])
	}
}

// --- .env-local gitignore check tests ---

func TestCheckEnvLocalGitignored_NotGitRepo(t *testing.T) {
	dir := t.TempDir()
	envLocal := filepath.Join(dir, ".booth", ".env-local")

	// Not a git repo — should skip check and return nil
	err := checkEnvLocalGitignored(envLocal, dir)
	if err != nil {
		t.Fatalf("expected nil for non-git-repo, got %v", err)
	}
}

func TestCheckEnvLocalGitignored_NotIgnored(t *testing.T) {
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

	// Create .booth/.env-local but NO .gitignore
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	envLocal := filepath.Join(boothDir, ".env-local")
	if err := os.WriteFile(envLocal, []byte("SECRET=value"), 0644); err != nil {
		t.Fatal(err)
	}

	err := checkEnvLocalGitignored(envLocal, dir)
	if err == nil {
		t.Fatal("expected error for non-gitignored file, got nil")
	}
	if !strings.Contains(err.Error(), "NOT gitignored") {
		t.Fatalf("expected 'NOT gitignored' in error, got %q", err.Error())
	}
}

func TestCheckEnvLocalGitignored_Ignored(t *testing.T) {
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

	// Create .booth/.gitignore with .env-local entry
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	gitignore := filepath.Join(boothDir, ".gitignore")
	if err := os.WriteFile(gitignore, []byte(".env-local\n"), 0644); err != nil {
		t.Fatal(err)
	}

	envLocal := filepath.Join(boothDir, ".env-local")
	if err := os.WriteFile(envLocal, []byte("SECRET=value"), 0644); err != nil {
		t.Fatal(err)
	}

	err := checkEnvLocalGitignored(envLocal, dir)
	if err != nil {
		t.Fatalf("expected nil for gitignored file, got %v", err)
	}
}
