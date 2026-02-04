// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

// EgressConfig controls outbound network policy orchestration.
//
// It is intentionally TOML-only for now; runtime wiring comes in later phases.
type EgressConfig struct {
	Mode          string `toml:"mode,omitempty"`
	Enforcement   string `toml:"enforcement,omitempty"`
	Default       string `toml:"default,omitempty"`
	AllowlistFile string `toml:"allowlist-file,omitempty"`
	PolicyFile    string `toml:"policy-file,omitempty"`
}
