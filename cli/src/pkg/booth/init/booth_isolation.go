// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// boothIsolationModes are the values --booth-isolation accepts. "none" is an
// ordinary container; "kata" runs the booth in its own Kata VM.
var boothIsolationModes = []string{"none", "kata"}

func isBoothIsolationMode(value string) bool {
	value = strings.ToLower(strings.TrimSpace(value))
	for _, mode := range boothIsolationModes {
		if value == mode {
			return true
		}
	}
	return false
}

// normalizeBoothIsolation lower-cases the mode, folds "none" into "" and rejects
// unknown values. A Kata booth with --dind gets a Kata sidecar too: a privileged
// sidecar on this machine, reachable from the booth over TCP, would hand the
// booth the way out its VM exists to close. It runs before
// normalizeDindIsolation, which then checks that sidecar mode.
func normalizeBoothIsolation(config *appctx.AppConfig) error {
	mode := strings.ToLower(strings.TrimSpace(config.BoothIsolation))
	if mode == "none" {
		mode = ""
	}
	if mode != "" && !isBoothIsolationMode(mode) {
		return fmt.Errorf("invalid booth-isolation %q (supported: %s)", config.BoothIsolation, strings.Join(boothIsolationModes, ", "))
	}
	config.BoothIsolation = mode
	if mode == "kata" && config.Dind {
		dindMode := strings.ToLower(strings.TrimSpace(config.DindIsolation))
		if dindMode == "" || dindMode == "none" {
			config.DindIsolation = "kata"
		}
	}
	return nil
}

// checkBoothIsolationEngine refuses combinations that cannot work anywhere, and
// prints the experimental warning. Whether this machine can run the mode at all
// (Linux, Docker Engine, KVM, Kata) is settled at the start of the run by
// booth.ResolveBoothIsolation, which falls back to an ordinary container — with
// a warning — when it cannot.
func checkBoothIsolationEngine(config *appctx.AppConfig) error {
	if config.BoothIsolation == "" {
		return nil
	}
	// Engine apple already runs each booth in a VM of its own: there is nothing for
	// Kata to add, and nothing is lost, so it is a note, not the fallback banner.
	if config.Engine == "apple" {
		if !config.Quiet {
			fmt.Fprintf(os.Stderr, "ℹ️  --booth-isolation: engine apple already runs each booth in its own VM; nothing more to do.\n")
		}
		config.BoothIsolation = ""
		return nil
	}
	// --egress alone works (the booth goes on an internal network behind the
	// egress gateway); with --dind the booth shares the sidecar's network, which
	// a Kata booth cannot.
	if config.Egress && config.Dind {
		return fmt.Errorf("--booth-isolation %s cannot be combined with --egress and --dind together yet (--egress alone works). See docs/BOOTH_SECURITY.md#booth-isolation", config.BoothIsolation)
	}
	if !config.Quiet {
		fmt.Fprintf(os.Stderr, "Warning: --booth-isolation %s is experimental. See docs/BOOTH_SECURITY.md#booth-isolation.\n", config.BoothIsolation)
	}
	return nil
}
