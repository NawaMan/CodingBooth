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
	"github.com/nawaman/codingbooth/src/pkg/shellexpand"
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
	// .booth/.env exists, no user env-file → single --env-file added pointing
	// at booth's expanded temp file under .booth/.tmp/.
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

	expanded := expectExpandedEnvArg(t, newCtx, filepath.Join(tmpDir, ".booth", ".tmp"))
	gotContent, err := os.ReadFile(expanded)
	if err != nil {
		t.Fatalf("could not read expanded env file: %v", err)
	}
	if string(gotContent) != "SECRET=value\n" {
		t.Errorf("expanded env content = %q, want %q", string(gotContent), "SECRET=value\n")
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

	expectExpandedEnvArg(t, newCtx, filepath.Join(tmpDir, ".booth", ".tmp"))
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

	expectExpandedEnvArg(t, newCtx, filepath.Join(tmpDir, ".booth", ".tmp"))
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

// gitRepoWithBooth makes a temp git repo containing .booth/ and returns
// (repoDir, boothDir). Skips the test when git is not installed.
func gitRepoWithBooth(t *testing.T) (string, string) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not available")
	}
	dir := t.TempDir()
	if err := exec.Command("git", "init", dir).Run(); err != nil {
		t.Fatal(err)
	}
	boothDir := filepath.Join(dir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	return dir, boothDir
}

func writeBoothFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

// The regression this guards: the check used to hard-code ".booth/.env", so a
// profile env file passed whenever the BASE .env was ignored (or missing).
func TestCheckBoothEnvGitignored_ProfileFileNotIgnored(t *testing.T) {
	dir, boothDir := gitRepoWithBooth(t)
	writeBoothFile(t, filepath.Join(boothDir, ".gitignore"), ".env\n") // base only
	profileEnv := filepath.Join(boothDir, ".dev--env")
	writeBoothFile(t, profileEnv, "SECRET=value")

	err := checkBoothEnvGitignored(profileEnv, dir)
	if err == nil {
		t.Fatal("expected error: .dev--env is not ignored, even though the base .env is")
	}
	for _, want := range []string{"NOT gitignored", ".dev--env", ".*--env"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("expected %q in error, got %q", want, err.Error())
		}
	}
}

func TestCheckBoothEnvGitignored_ProfileFileIgnored(t *testing.T) {
	dir, boothDir := gitRepoWithBooth(t)
	writeBoothFile(t, filepath.Join(boothDir, ".gitignore"), ".env\n.*--env\n")
	profileEnv := filepath.Join(boothDir, ".dev--env")
	writeBoothFile(t, profileEnv, "SECRET=value")

	if err := checkBoothEnvGitignored(profileEnv, dir); err != nil {
		t.Fatalf("expected nil for gitignored profile env file, got %v", err)
	}
}

// Each profile file is judged on its own: ignoring one does not cover another.
func TestCheckBoothEnvGitignored_ProfileFilesJudgedIndividually(t *testing.T) {
	dir, boothDir := gitRepoWithBooth(t)
	writeBoothFile(t, filepath.Join(boothDir, ".gitignore"), ".dev--env\n")
	dev := filepath.Join(boothDir, ".dev--env")
	prod := filepath.Join(boothDir, ".prod--env")
	writeBoothFile(t, dev, "A=1")
	writeBoothFile(t, prod, "A=2")

	if err := checkBoothEnvGitignored(dev, dir); err != nil {
		t.Fatalf("dev is ignored, expected nil, got %v", err)
	}
	if err := checkBoothEnvGitignored(prod, dir); err == nil {
		t.Fatal("prod is not ignored, expected an error")
	}
}

// Ignoring a file after it was committed does not un-commit it, so a tracked
// env file must still be refused even when an ignore pattern matches it.
func TestCheckBoothEnvGitignored_TrackedProfileFileIsRefused(t *testing.T) {
	dir, boothDir := gitRepoWithBooth(t)
	profileEnv := filepath.Join(boothDir, ".prod--env")
	writeBoothFile(t, profileEnv, "SECRET=value")
	if out, err := exec.Command("git", "-C", dir, "add", "-f", ".booth/.prod--env").CombinedOutput(); err != nil {
		t.Fatalf("git add: %v: %s", err, out)
	}
	writeBoothFile(t, filepath.Join(boothDir, ".gitignore"), ".*--env\n") // too late

	if err := checkBoothEnvGitignored(profileEnv, dir); err == nil {
		t.Fatal("expected error: file is already tracked by git")
	}
}

// The base file keeps its original wording and hint.
func TestCheckBoothEnvGitignored_BaseFileHintIsDotEnv(t *testing.T) {
	dir, boothDir := gitRepoWithBooth(t)
	baseEnv := filepath.Join(boothDir, ".env")
	writeBoothFile(t, baseEnv, "SECRET=value")

	err := checkBoothEnvGitignored(baseEnv, dir)
	if err == nil {
		t.Fatal("expected error for non-gitignored base .env")
	}
	if !strings.Contains(err.Error(), "Add '.env' to .booth/.gitignore") {
		t.Errorf("expected the base-file hint, got %q", err.Error())
	}
}

// expectExpandedEnvArg fails the test unless the context's CommonArgs
// contains exactly one --env-file <path>, where <path> lives under
// expectedDir and ends in .expanded. Returns the expanded path so the
// caller can inspect its contents.
func expectExpandedEnvArg(t *testing.T, ctx appctx.AppContext, expectedDir string) string {
	t.Helper()
	args := flattenArgs(ctx.CommonArgs())
	var paths []string
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			paths = append(paths, args[i+1])
		}
	}
	if len(paths) != 1 {
		t.Fatalf("expected exactly 1 --env-file arg, got %d: %v", len(paths), args)
	}
	got := paths[0]
	if filepath.Dir(got) != expectedDir {
		t.Fatalf("expected --env-file under %s, got %s", expectedDir, got)
	}
	if !strings.HasSuffix(got, ".expanded") {
		t.Fatalf("expected --env-file path ending in .expanded, got %s", got)
	}
	if _, err := os.Stat(got); err != nil {
		t.Fatalf("expanded env file %s missing: %v", got, err)
	}
	return got
}

// --- Expansion behaviour ---

func TestApplyEnvFile_ExpandsTilde(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(boothDir, ".env"), []byte("BACKUP=~/data\n"), 0644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("HOME", "/home/cody")

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)

	newCtx := ApplyEnvFile(builder.Build())
	got := expectExpandedEnvArg(t, newCtx, filepath.Join(tmpDir, ".booth", ".tmp"))
	content, err := os.ReadFile(got)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "BACKUP=/home/cody/data\n" {
		t.Errorf("got %q, want %q", string(content), "BACKUP=/home/cody/data\n")
	}
}

func TestApplyEnvFile_ExpandsDefaultsAndQuotes(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	body := strings.Join([]string{
		`PORT=${APP_PORT:-8080}`,
		`LITERAL='$KEEP'`,
		`GREET="hi $USER"`,
		``,
	}, "\n")
	if err := os.WriteFile(filepath.Join(boothDir, ".env"), []byte(body), 0644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("USER", "cody")
	os.Unsetenv("APP_PORT")

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)

	newCtx := ApplyEnvFile(builder.Build())
	got := expectExpandedEnvArg(t, newCtx, filepath.Join(tmpDir, ".booth", ".tmp"))
	content, err := os.ReadFile(got)
	if err != nil {
		t.Fatal(err)
	}
	want := "PORT=8080\nLITERAL=$KEEP\nGREET=hi cody\n"
	if string(content) != want {
		t.Errorf("got %q, want %q", string(content), want)
	}
}

func TestApplyEnvFile_Dryrun_DoesNotWriteTempFile(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		t.Fatal(err)
	}
	boothEnv := filepath.Join(boothDir, ".env")
	if err := os.WriteFile(boothEnv, []byte("FOO=bar\n"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(tmpDir)
	builder.Config.Dryrun = nillable.NewNillableBool(true)

	newCtx := ApplyEnvFile(builder.Build())
	args := flattenArgs(newCtx.CommonArgs())
	var path string
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			path = args[i+1]
		}
	}
	if path != boothEnv {
		t.Errorf("dryrun should keep original path, got %s", path)
	}
	if _, err := os.Stat(filepath.Join(boothDir, ".tmp")); err == nil {
		t.Error("dryrun should not create .booth/.tmp/")
	}
}

func TestApplyEnvFile_RequiredVarAborts(t *testing.T) {
	// We can't easily test os.Exit, so verify the underlying parse +
	// expand error directly via the shellexpand API. The exit path is
	// exercised by integration tests.
	tmpDir := t.TempDir()
	envPath := filepath.Join(tmpDir, "test.env")
	if err := os.WriteFile(envPath, []byte("DB=${DATABASE_URL:?required for boot}\n"), 0644); err != nil {
		t.Fatal(err)
	}
	os.Unsetenv("DATABASE_URL")
	entries, err := shellexpand.ParseEnvFile(envPath)
	if err != nil {
		t.Fatalf("unexpected parse error: %v", err)
	}
	_, err = shellexpand.ExpandEntries(entries, shellexpand.DefaultLookup, envPath)
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "required for boot") {
		t.Errorf("error %q lacks expected message", err.Error())
	}
	if !strings.Contains(err.Error(), envPath) {
		t.Errorf("error %q lacks source path", err.Error())
	}
}
