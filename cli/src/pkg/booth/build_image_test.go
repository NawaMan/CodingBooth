// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import "testing"

func TestAssembleImageName_LocalOnly(t *testing.T) {
	got := AssembleImageName("", "myproject", "abc123")
	want := "myproject:abc123"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestAssembleImageName_WithRegistry(t *testing.T) {
	got := AssembleImageName("ghcr.io/myteam", "myproject", "abc123")
	want := "ghcr.io/myteam/myproject:abc123"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestAssembleImageName_RegistryTrailingSlash(t *testing.T) {
	got := AssembleImageName("ghcr.io/myteam/", "myproject", "v1.0")
	want := "ghcr.io/myteam/myproject:v1.0"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestAssembleImageName_DockerHub(t *testing.T) {
	got := AssembleImageName("docker.io/library", "myapp", "latest")
	want := "docker.io/library/myapp:latest"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestExtractRegistryHost_WithPath(t *testing.T) {
	got := ExtractRegistryHost("ghcr.io/myteam")
	want := "ghcr.io"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestExtractRegistryHost_HostOnly(t *testing.T) {
	got := ExtractRegistryHost("docker.io")
	want := "docker.io"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestExtractRegistryHost_DeepPath(t *testing.T) {
	got := ExtractRegistryHost("us-docker.pkg.dev/my-project/my-repo")
	want := "us-docker.pkg.dev"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestRegistryLoginCommand(t *testing.T) {
	tests := map[string]string{
		"docker": "docker login ghcr.io",
		"":       "docker login ghcr.io",
		"podman": "podman login ghcr.io",
		"apple":  "container registry login ghcr.io",
	}
	for engine, want := range tests {
		if got := RegistryLoginCommand(engine, "ghcr.io"); got != want {
			t.Errorf("RegistryLoginCommand(%q) = %q, want %q", engine, got, want)
		}
	}
}

func TestSanitizeRepoName(t *testing.T) {
	cases := map[string]string{
		"myproject":          "myproject",
		"NPQAA238":           "npqaa238",
		"CodingBooth":        "codingbooth",
		"my_app":             "my_app",
		"my__app":            "my__app",
		"my.app":             "my.app",
		"my--app":            "my--app",
		"My App":             "my-app",
		"a___b":              "a-b",
		"a._b":               "a-b",
		"-Leading.Trailing_": "leading.trailing",
		"日本":                 "booth",
		"":                   "booth",
	}
	for in, want := range cases {
		if got := SanitizeRepoName(in); got != want {
			t.Errorf("SanitizeRepoName(%q) = %q, want %q", in, got, want)
		}
	}
}
