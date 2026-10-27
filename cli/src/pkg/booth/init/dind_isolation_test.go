// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func emptyArgsConfig() appctx.AppConfig {
	return appctx.AppConfig{
		RunArgs:   ilist.SemicolonStringList{List: ilist.NewList[string]()},
		BuildArgs: ilist.SemicolonStringList{List: ilist.NewList[string]()},
		Cmds:      ilist.SemicolonStringList{List: ilist.NewList[string]()},
	}
}

func TestParseArgs_DindIsolation(t *testing.T) {
	cases := []struct {
		args     []string
		wantMode string
		wantCmds []string
		wantRun  []string
	}{
		{args: []string{"--dind-isolation"}, wantMode: "kata"},
		{args: []string{"--dind-isolation", "kata"}, wantMode: "kata"},
		{args: []string{"--dind-isolation", "none"}, wantMode: "none"},
		{args: []string{"--dind-isolation=kata"}, wantMode: "kata"},
		// A following argument that is not a mode is left alone.
		{args: []string{"--dind-isolation", "--", "echo", "hi"}, wantMode: "kata", wantCmds: []string{"echo", "hi"}},
		{args: []string{"--dind-isolation", "-v", "/a:/a"}, wantMode: "kata", wantRun: []string{"-v", "/a:/a"}},
	}
	for _, c := range cases {
		config := emptyArgsConfig()
		if err := parseArgs(ilist.NewListFromSlice(c.args), &config); err != nil {
			t.Fatalf("%v: parseArgs failed: %v", c.args, err)
		}
		if config.DindIsolation != c.wantMode {
			t.Errorf("%v: DindIsolation = %q, want %q", c.args, config.DindIsolation, c.wantMode)
		}
		if got := strings.Join(config.Cmds.Slice(), " "); got != strings.Join(c.wantCmds, " ") {
			t.Errorf("%v: cmds = %q, want %q", c.args, got, strings.Join(c.wantCmds, " "))
		}
		if got := strings.Join(config.RunArgs.Slice(), " "); got != strings.Join(c.wantRun, " ") {
			t.Errorf("%v: run-args = %q, want %q", c.args, got, strings.Join(c.wantRun, " "))
		}
	}
}

func TestParseArgs_DindVmSizing(t *testing.T) {
	config := emptyArgsConfig()
	args := []string{"--dind-vm-memory", "4g", "--dind-vm-cpus", "2"}
	if err := parseArgs(ilist.NewListFromSlice(args), &config); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}
	if config.DindVmMemory != "4g" || config.DindVmCpus != "2" {
		t.Errorf("got memory=%q cpus=%q", config.DindVmMemory, config.DindVmCpus)
	}
}

func TestNormalizeDindIsolation(t *testing.T) {
	cases := []struct {
		mode     string
		wantMode string
		wantDind bool
		wantErr  string
	}{
		{mode: "", wantMode: "", wantDind: false},
		{mode: "none", wantMode: "", wantDind: false},
		{mode: "kata", wantMode: "kata", wantDind: true},
		{mode: " KATA ", wantMode: "kata", wantDind: true},
		{mode: "sysbox", wantErr: `invalid dind-isolation "sysbox" (supported: none, kata)`},
	}
	for _, c := range cases {
		config := appctx.AppConfig{DindIsolation: c.mode}
		err := normalizeDindIsolation(&config)
		if c.wantErr != "" {
			if err == nil || err.Error() != c.wantErr {
				t.Errorf("%q: err = %v, want %q", c.mode, err, c.wantErr)
			}
			continue
		}
		if err != nil {
			t.Fatalf("%q: %v", c.mode, err)
		}
		if config.DindIsolation != c.wantMode || config.Dind != c.wantDind {
			t.Errorf("%q: got mode=%q dind=%t, want mode=%q dind=%t", c.mode, config.DindIsolation, config.Dind, c.wantMode, c.wantDind)
		}
	}
}

func TestNormalizeDindIsolation_VmSizes(t *testing.T) {
	cases := []struct {
		memory, cpus string
		wantErr      string
	}{
		{memory: "4g", cpus: "2"},
		{memory: "4096m"},
		{memory: "lots", wantErr: "invalid dind-vm-memory"},
		{memory: "100m", wantErr: "invalid dind-vm-memory"},
		{cpus: "0", wantErr: "invalid dind-vm-cpus"},
		{cpus: "two", wantErr: "invalid dind-vm-cpus"},
	}
	for _, c := range cases {
		config := appctx.AppConfig{DindIsolation: "kata", DindVmMemory: c.memory, DindVmCpus: c.cpus}
		err := normalizeDindIsolation(&config)
		switch {
		case c.wantErr == "" && err != nil:
			t.Errorf("memory=%q cpus=%q: unexpected %v", c.memory, c.cpus, err)
		case c.wantErr != "" && (err == nil || !strings.Contains(err.Error(), c.wantErr)):
			t.Errorf("memory=%q cpus=%q: err = %v, want %q", c.memory, c.cpus, err, c.wantErr)
		}
	}
}

func TestCheckDindIsolationEngine(t *testing.T) {
	cases := []struct {
		name    string
		config  appctx.AppConfig
		wantErr string
	}{
		{name: "off", config: appctx.AppConfig{Engine: "podman"}},
		{name: "docker", config: appctx.AppConfig{Engine: "docker", Dind: true, DindIsolation: "kata"}},
		// Not refused here: an engine Kata cannot run on falls back at the start of the run
		// (booth.ResolveDindIsolation), with a warning and the usual --dind consent.
		{name: "podman", config: appctx.AppConfig{Engine: "podman", Dind: true, DindIsolation: "kata"}},
		{name: "egress", config: appctx.AppConfig{Engine: "docker", Dind: true, DindIsolation: "kata", Egress: true}, wantErr: "cannot be combined with --egress"},
	}
	for _, c := range cases {
		err := checkDindIsolationEngine(&c.config)
		switch {
		case c.wantErr == "" && err != nil:
			t.Errorf("%s: unexpected %v", c.name, err)
		case c.wantErr != "" && (err == nil || !strings.Contains(err.Error(), c.wantErr)):
			t.Errorf("%s: err = %v, want %q", c.name, err, c.wantErr)
		}
	}
}

func TestDindVmMemoryMiB(t *testing.T) {
	cases := map[string]int{"4g": 4096, "4096m": 4096, "2048mb": 2048, "1.5g": 1536, "lots": 0, "": 0}
	for in, want := range cases {
		if got := appctx.DindVmMemoryMiB(in); got != want {
			t.Errorf("DindVmMemoryMiB(%q) = %d, want %d", in, got, want)
		}
	}
}
