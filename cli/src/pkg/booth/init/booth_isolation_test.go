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

func TestParseArgs_BoothIsolation(t *testing.T) {
	cases := []struct {
		args     []string
		wantMode string
		wantCmds []string
		wantRun  []string
	}{
		{args: []string{"--booth-isolation"}, wantMode: "kata"},
		{args: []string{"--booth-isolation", "kata"}, wantMode: "kata"},
		{args: []string{"--booth-isolation", "none"}, wantMode: "none"},
		{args: []string{"--booth-isolation=kata"}, wantMode: "kata"},
		// A following argument that is not a mode is left alone.
		{args: []string{"--booth-isolation", "--", "echo", "hi"}, wantMode: "kata", wantCmds: []string{"echo", "hi"}},
		{args: []string{"--booth-isolation", "-v", "/a:/a"}, wantMode: "kata", wantRun: []string{"-v", "/a:/a"}},
	}
	for _, c := range cases {
		config := emptyArgsConfig()
		if err := parseArgs(ilist.NewListFromSlice(c.args), &config); err != nil {
			t.Fatalf("%v: parseArgs failed: %v", c.args, err)
		}
		if config.BoothIsolation != c.wantMode {
			t.Errorf("%v: BoothIsolation = %q, want %q", c.args, config.BoothIsolation, c.wantMode)
		}
		if got := strings.Join(config.Cmds.Slice(), " "); got != strings.Join(c.wantCmds, " ") {
			t.Errorf("%v: cmds = %q, want %q", c.args, got, strings.Join(c.wantCmds, " "))
		}
		if got := strings.Join(config.RunArgs.Slice(), " "); got != strings.Join(c.wantRun, " ") {
			t.Errorf("%v: run-args = %q, want %q", c.args, got, strings.Join(c.wantRun, " "))
		}
	}
}

func TestNormalizeBoothIsolation(t *testing.T) {
	cases := []struct {
		mode, dindMode string
		dind           bool
		wantMode       string
		wantDindMode   string
		wantErr        bool
	}{
		{mode: "", wantMode: ""},
		{mode: "none", wantMode: ""},
		{mode: " KATA ", wantMode: "kata"},
		{mode: "gvisor", wantErr: true},
		// No --dind: the sidecar mode is left alone.
		{mode: "kata", wantMode: "kata", wantDindMode: ""},
		// --dind: the sidecar goes into Kata too, so the booth cannot reach a
		// privileged daemon on this machine.
		{mode: "kata", dind: true, wantMode: "kata", wantDindMode: "kata"},
		{mode: "kata", dind: true, dindMode: "none", wantMode: "kata", wantDindMode: "kata"},
		{mode: "kata", dind: true, dindMode: "kata", wantMode: "kata", wantDindMode: "kata"},
		// An ordinary booth keeps a plain sidecar.
		{mode: "", dind: true, wantMode: "", wantDindMode: ""},
	}
	for _, c := range cases {
		config := appctx.AppConfig{BoothIsolation: c.mode, Dind: c.dind, DindIsolation: c.dindMode}
		err := normalizeBoothIsolation(&config)
		if (err != nil) != c.wantErr {
			t.Fatalf("%+v: err = %v, wantErr %v", c, err, c.wantErr)
		}
		if c.wantErr {
			continue
		}
		if config.BoothIsolation != c.wantMode {
			t.Errorf("%+v: BoothIsolation = %q, want %q", c, config.BoothIsolation, c.wantMode)
		}
		if config.DindIsolation != c.wantDindMode {
			t.Errorf("%+v: DindIsolation = %q, want %q", c, config.DindIsolation, c.wantDindMode)
		}
	}
}

func TestCheckBoothIsolationEngine(t *testing.T) {
	if err := checkBoothIsolationEngine(&appctx.AppConfig{}); err != nil {
		t.Errorf("no isolation: unexpected error %v", err)
	}
	if err := checkBoothIsolationEngine(&appctx.AppConfig{BoothIsolation: "kata", Quiet: true}); err != nil {
		t.Errorf("kata: unexpected error %v", err)
	}
	err := checkBoothIsolationEngine(&appctx.AppConfig{BoothIsolation: "kata", Egress: true, Quiet: true})
	if err == nil || !strings.Contains(err.Error(), "--egress") {
		t.Errorf("kata + egress: want a refusal naming --egress, got %v", err)
	}
}

func TestCheckBoothIsolationEngine_Apple(t *testing.T) {
	// Engine apple is a VM per booth already: a note, no banner, no refusal, and
	// the booth runs as engine apple always does.
	config := appctx.AppConfig{BoothIsolation: "kata", Engine: "apple", Quiet: true}
	if err := checkBoothIsolationEngine(&config); err != nil {
		t.Errorf("apple: unexpected error %v", err)
	}
	if config.BoothIsolation != "" {
		t.Errorf("apple: BoothIsolation = %q, want it cleared", config.BoothIsolation)
	}
}
