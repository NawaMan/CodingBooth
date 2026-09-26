// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import "testing"

// The consent overrides come from the command line only. A cloned repo controls config.toml and
// can ship an env file, so neither may be able to pre-approve a booth that reaches the host.

func TestConsentFlags_FromCommandLine(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		Args: []string{"--dind", "--dind-allowed", "--privileged-allowed"},
	})
	if !res.Ctx.DindAllowed() || !res.Ctx.PrivilegedAllowed() {
		t.Fatalf("flags should set both: dind=%v privileged=%v", res.Ctx.DindAllowed(), res.Ctx.PrivilegedAllowed())
	}
	if len(res.Ctx.RunArgs().Slice()) != 0 {
		t.Fatalf("the flags must not fall through as docker run-args, got %v", res.Ctx.RunArgs().Slice())
	}
}

func TestConsentFlags_NotFromEnv(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		Args: []string{"--dind"},
		EnvMap: map[string]string{
			"DIND_ALLOWED": "true", "PRIVILEGED_ALLOWED": "true",
			"CB_DIND_ALLOWED": "true", "CB_PRIVILEGED_ALLOWED": "true",
		},
	})
	if res.Ctx.DindAllowed() || res.Ctx.PrivilegedAllowed() {
		t.Fatal("no environment variable may pre-approve")
	}
}

func TestConsentFlags_NotFromConfigToml(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{{
			Path: ".booth/config.toml",
			Content: "dind = true\n" +
				"dind-allowed = true\nprivileged-allowed = true\n" +
				"DindAllowed = true\nPrivilegedAllowed = true\n",
		}},
	})
	if !res.Ctx.Dind() {
		t.Fatal("fixture should have enabled dind from config.toml")
	}
	if res.Ctx.DindAllowed() || res.Ctx.PrivilegedAllowed() {
		t.Fatal("config.toml may not pre-approve")
	}
}
