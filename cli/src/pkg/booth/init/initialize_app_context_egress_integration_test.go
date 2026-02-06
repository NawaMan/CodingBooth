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
[egress]
mode = "Envoy"
enforcement = "iptables"
default = "deny"
allowlist-file = ".booth/egress/allowlist.txt"
`,
			},
			{
				Path:    ".booth/egress/allowlist.txt",
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

func TestIntegration_InitializeAppContext_Egress_InvalidMode_Panics(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for invalid egress.mode, but did not panic")
		}
	}()

	_ = RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{
			{
				Path: ".booth/config.toml",
				Content: `
[egress]
mode = "not-supported"
`,
			},
		},
	})
}

func TestIntegration_InitializeAppContext_Egress_AllowlistAndPolicy_Panics(t *testing.T) {
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
[egress]
allowlist-file = ".booth/egress/allowlist.txt"
policy-file = ".booth/egress/envoy.yaml"
`,
			},
			{Path: ".booth/egress/allowlist.txt", Content: "pypi.org\n"},
			{Path: ".booth/egress/envoy.yaml", Content: "static_resources: {}\n"},
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
