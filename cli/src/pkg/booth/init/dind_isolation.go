// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// dindIsolationModes are the values --dind-isolation accepts. "none" is today's
// privileged docker:dind sidecar; "kata" runs that sidecar in its own Kata VM.
var dindIsolationModes = []string{"none", "kata"}

func isDindIsolationMode(value string) bool {
	value = strings.ToLower(strings.TrimSpace(value))
	for _, mode := range dindIsolationModes {
		if value == mode {
			return true
		}
	}
	return false
}

// normalizeDindIsolation lower-cases the mode, folds "none" into "", rejects
// unknown values and checks the VM sizes. A mode implies --dind. It runs before
// the engine is resolved, since --dind keeps Apple container out of the default
// pick.
func normalizeDindIsolation(config *appctx.AppConfig) error {
	mode := strings.ToLower(strings.TrimSpace(config.DindIsolation))
	if mode == "none" {
		mode = ""
	}
	if mode != "" && !isDindIsolationMode(mode) {
		return fmt.Errorf("invalid dind-isolation %q (supported: %s)", config.DindIsolation, strings.Join(dindIsolationModes, ", "))
	}
	config.DindIsolation = mode
	if mode != "" {
		config.Dind = true
	}

	config.DindVmMemory = strings.TrimSpace(config.DindVmMemory)
	config.DindVmCpus = strings.TrimSpace(config.DindVmCpus)
	if config.DindVmMemory != "" && appctx.DindVmMemoryMiB(config.DindVmMemory) < 256 {
		return fmt.Errorf("invalid dind-vm-memory %q (expected a size like 4g or 4096m, at least 256m)", config.DindVmMemory)
	}
	if config.DindVmCpus != "" {
		if n, err := strconv.Atoi(config.DindVmCpus); err != nil || n < 1 {
			return fmt.Errorf("invalid dind-vm-cpus %q (expected a whole number of CPUs, 1 or more)", config.DindVmCpus)
		}
	}
	return nil
}

// checkDindIsolationEngine refuses combinations that cannot work anywhere, and
// prints the experimental warning. Whether this machine can run the mode at all
// (Linux, Docker Engine, KVM, Kata) is settled at the start of the run by
// booth.ResolveDindIsolation, which falls back to the plain sidecar — with a
// warning and the usual consent — when it cannot.
func checkDindIsolationEngine(config *appctx.AppConfig) error {
	if config.DindIsolation == "" {
		if !config.Quiet && (config.DindVmMemory != "" || config.DindVmCpus != "") {
			fmt.Fprintln(os.Stderr, "Note: --dind-vm-memory / --dind-vm-cpus only apply with --dind-isolation kata; ignored.")
		}
		return nil
	}
	if config.Egress {
		return fmt.Errorf("--dind-isolation %s cannot be combined with --egress yet. See docs/BOOTH_SECURITY.md#dind-isolation", config.DindIsolation)
	}
	fmt.Fprintf(os.Stderr, "Warning: --dind-isolation %s is experimental. See docs/BOOTH_SECURITY.md#dind-isolation.\n", config.DindIsolation)
	return nil
}
