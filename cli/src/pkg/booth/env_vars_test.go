// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func TestFilterUnsetEnvVars_BarePassthrough(t *testing.T) {
	unsetEnvForTest(t, "CB_TEST_UNSET_ENV")
	t.Setenv("CB_TEST_EMPTY_ENV", "")
	t.Setenv("CB_TEST_SET_ENV", "value")

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.RunArgs.Append(ilist.NewList(
		"-e", "CB_TEST_UNSET_ENV",
		"-e", "CB_TEST_EMPTY_ENV",
		"--env", "CB_TEST_SET_ENV",
		"-e", "EXPLICIT_EMPTY=",
		"--env", "EXPLICIT_VALUE=1",
	))
	builder.CommonArgs.Append(ilist.NewList(
		"--env", "CB_TEST_UNSET_ENV",
		"--env", "COMMON_EXPLICIT_EMPTY=",
	))

	ctx := FilterUnsetEnvVars(builder.Build())

	runFlat := flattenArgGroups(ctx.RunArgs())
	if containsPair(runFlat, "-e", "CB_TEST_UNSET_ENV") {
		t.Fatalf("unset bare run env was kept: %v", runFlat)
	}
	if !containsPair(runFlat, "-e", "CB_TEST_EMPTY_ENV") {
		t.Fatalf("empty-but-set bare run env was dropped: %v", runFlat)
	}
	if !containsPair(runFlat, "--env", "CB_TEST_SET_ENV") {
		t.Fatalf("set bare run env was dropped: %v", runFlat)
	}
	if !containsPair(runFlat, "-e", "EXPLICIT_EMPTY=") {
		t.Fatalf("explicit empty run env was dropped: %v", runFlat)
	}
	if !containsPair(runFlat, "--env", "EXPLICIT_VALUE=1") {
		t.Fatalf("explicit value run env was dropped: %v", runFlat)
	}

	commonFlat := flattenArgGroups(ctx.CommonArgs())
	if containsPair(commonFlat, "--env", "CB_TEST_UNSET_ENV") {
		t.Fatalf("unset bare common env was kept: %v", commonFlat)
	}
	if !containsPair(commonFlat, "--env", "COMMON_EXPLICIT_EMPTY=") {
		t.Fatalf("explicit empty common env was dropped: %v", commonFlat)
	}
}

func TestFilterUnsetEnvVars_EqualsFlagSyntax(t *testing.T) {
	unsetEnvForTest(t, "CB_TEST_UNSET_EQUALS_ENV")
	t.Setenv("CB_TEST_EMPTY_EQUALS_ENV", "")

	got := filterUnsetEnvVarItems([]string{
		"-e=CB_TEST_UNSET_EQUALS_ENV",
		"--env=CB_TEST_EMPTY_EQUALS_ENV",
		"-e=EXPLICIT_EMPTY=",
		"--env=EXPLICIT_VALUE=1",
		"--name", "demo",
	})

	if containsSubstring(got, "CB_TEST_UNSET_EQUALS_ENV") {
		t.Fatalf("unset bare equals env was kept: %v", got)
	}
	if !containsSubstring(got, "--env=CB_TEST_EMPTY_EQUALS_ENV") {
		t.Fatalf("empty-but-set bare equals env was dropped: %v", got)
	}
	if !containsSubstring(got, "-e=EXPLICIT_EMPTY=") {
		t.Fatalf("explicit empty equals env was dropped: %v", got)
	}
	if !containsSubstring(got, "--env=EXPLICIT_VALUE=1") {
		t.Fatalf("explicit value equals env was dropped: %v", got)
	}
	if !containsPair(got, "--name", "demo") {
		t.Fatalf("non-env args were not preserved: %v", got)
	}
}

func unsetEnvForTest(t *testing.T, key string) {
	t.Helper()
	old, wasSet := os.LookupEnv(key)
	if err := os.Unsetenv(key); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if wasSet {
			_ = os.Setenv(key, old)
		} else {
			_ = os.Unsetenv(key)
		}
	})
}
