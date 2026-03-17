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
