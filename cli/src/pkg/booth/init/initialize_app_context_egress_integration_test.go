// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import "testing"

func TestIntegration_InitializeAppContext_Egress_ValidAllowlist(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{
			{
				Path: ".booth/config.toml",
				Content: `
sandboxed = true
sandbox-allowlist-file = ".booth/sandbox/allowlist.txt"
`,
			},
			{
				Path:    ".booth/sandbox/allowlist.txt",
				Content: "pypi.org\n",
			},
		},
	})

	if got := res.Ctx.EgressMode(); got != "envoy" {
		t.Fatalf("expected normalized egress mode %q, got %q", "envoy", got)
	}
	if got := res.Ctx.EgressEnforcement(); got != "iptables" {
		t.Fatalf("expected egress enforcement %q, got %q", "iptables", got)
	}
	if got := res.Ctx.EgressDefault(); got != "deny" {
		t.Fatalf("expected egress default %q, got %q", "deny", got)
	}
}

func TestIntegration_InitializeAppContext_EgressBlock_Panics(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic when egress.* is set, but did not panic")
		}
	}()

	_ = RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{
			{
				Path: ".booth/config.toml",
				Content: `
[egress]
allowlist-file = ".booth/sandbox/allowlist.txt"
`,
			},
		},
	})
}

func TestIntegration_InitializeAppContext_Sandbox_AllowlistAndPolicy_Panics(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic when both allowlist and policy are set, but did not panic")
		}
	}()

	_ = RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{
			{
				Path: ".booth/config.toml",
				Content: `
sandboxed = true
sandbox-allowlist-file = ".booth/sandbox/allowlist.txt"
sandbox-policy-file = ".booth/sandbox/envoy.yaml"
`,
			},
			{Path: ".booth/sandbox/allowlist.txt", Content: "pypi.org\n"},
			{Path: ".booth/sandbox/envoy.yaml", Content: "static_resources: {}\n"},
		},
	})
}

func TestIntegration_InitializeAppContext_Egress_SandboxFlagSetsDefaults(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		Args: []string{"--sandboxed"},
	})

	if !res.Ctx.Sandbox() {
		t.Fatalf("expected sandbox flag to be true")
	}
	if got := res.Ctx.EgressMode(); got != "envoy" {
		t.Fatalf("expected sandbox egress mode %q, got %q", "envoy", got)
	}
	if got := res.Ctx.EgressEnforcement(); got != "iptables" {
		t.Fatalf("expected sandbox enforcement %q, got %q", "iptables", got)
	}
	if got := res.Ctx.EgressDefault(); got != "deny" {
		t.Fatalf("expected sandbox default %q, got %q", "deny", got)
	}
}
