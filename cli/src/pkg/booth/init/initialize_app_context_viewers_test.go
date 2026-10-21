// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"os"
	"testing"

	"github.com/kelseyhightower/envconfig"
	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func newViewersTestConfig() appctx.AppConfig {
	return appctx.AppConfig{
		RunArgs:   ilist.SemicolonStringList{List: ilist.NewList[string]()},
		BuildArgs: ilist.SemicolonStringList{List: ilist.NewList[string]()},
		Cmds:      ilist.SemicolonStringList{List: ilist.NewList[string]()},
	}
}

// With nothing set, the count shows once a second page is in.
func TestExpectedViewerCount_DefaultsToOne(t *testing.T) {
	t.Setenv("CB_EXPECTED_VIEWER_COUNT", "") // restored afterwards; envconfig needs it unset, not empty
	os.Unsetenv("CB_EXPECTED_VIEWER_COUNT")
	config := newViewersTestConfig()
	if err := envconfig.Process("", &config); err != nil {
		t.Fatalf("envconfig: %v", err)
	}
	if config.ExpectedViewerCount != 1 {
		t.Errorf("default ExpectedViewerCount = %d, want 1", config.ExpectedViewerCount)
	}
}

func TestParseArgs_ExpectedViewerCount(t *testing.T) {
	for _, tc := range []struct {
		value string
		want  int
	}{{"0", 0}, {"1", 1}, {"3", 3}} {
		config := newViewersTestConfig()
		args := ilist.NewListFromSlice([]string{"--expected-viewer-count", tc.value})
		if err := parseArgs(args, &config); err != nil {
			t.Fatalf("--expected-viewer-count %s: %v", tc.value, err)
		}
		if config.ExpectedViewerCount != tc.want {
			t.Errorf("--expected-viewer-count %s set %d, want %d", tc.value, config.ExpectedViewerCount, tc.want)
		}
	}
}

func TestParseArgs_ExpectedViewerCountRefusesBadValues(t *testing.T) {
	for _, args := range [][]string{
		{"--expected-viewer-count", "-1"},
		{"--expected-viewer-count", "two"},
		{"--expected-viewer-count"},
	} {
		config := newViewersTestConfig()
		if err := parseArgs(ilist.NewListFromSlice(args), &config); err == nil {
			t.Errorf("%v must be an error", args)
		}
	}
}

// config.toml and the env var skip the flag's check; validateConfig catches them.
func TestValidateConfig_RefusesNegativeExpectedViewerCount(t *testing.T) {
	config := newViewersTestConfig()
	config.Engine = "docker"
	config.ExpectedViewerCount = -2
	defer func() {
		if recover() == nil {
			t.Error("validateConfig accepted expected-viewer-count = -2")
		}
	}()
	validateConfig(&config)
}
