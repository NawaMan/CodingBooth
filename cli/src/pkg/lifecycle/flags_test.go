// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bytes"
	"flag"
	"reflect"
	"strings"
	"testing"
)

func TestLifecycleFlagOperandsStayLiteral(t *testing.T) {
	flagSet := flag.NewFlagSet("test", flag.ContinueOnError)
	engine := engineFlag(flagSet)
	force := flagSet.Bool("force", false, "")
	name := flagSet.String("name", "", "")
	err := parseLifecycleFlags(flagSet, []string{"first", "--force", "--engine=PoDmAn", "--name", "a b", "-", "--", "--engine", "apple"})
	if err != nil || *engine != "podman" || !*force || *name != "a b" || !reflect.DeepEqual(flagSet.Args(), []string{"first", "-", "--engine", "apple"}) {
		t.Fatalf("engine=%q force=%v name=%q operands=%v err=%v", *engine, *force, *name, flagSet.Args(), err)
	}
}

func TestLifecycleMissingEngineValueIsAnError(t *testing.T) {
	flagSet := flag.NewFlagSet("test", flag.ContinueOnError)
	engineFlag(flagSet)
	var output bytes.Buffer
	flagSet.SetOutput(&output)
	if err := parseLifecycleFlags(flagSet, []string{"demo", "--engine"}); err == nil || !strings.Contains(output.String(), "flag needs an argument") {
		t.Fatalf("err=%v output=%q", err, output.String())
	}
}

func TestEngineChoiceSurvivesConnectCreation(t *testing.T) {
	args := buildConnectRunArgs("demo", true, connectCreateOpts{engine: "podman"}, false)
	if !strings.Contains(strings.Join(args, " "), "--engine podman") {
		t.Fatalf("--run lost explicit engine: %v", args)
	}
}

func TestShellRunCreatesInBaseByDefault(t *testing.T) {
	args := strings.Join(buildConnectRunArgs("", false, connectCreateOpts{variant: shellCreateVariant(shellRunVariant)}, false), " ")
	if !strings.Contains(args, "--variant base") {
		t.Fatalf("shell --run should create a base booth: %v", args)
	}
}

func TestShellRunVariantOverride(t *testing.T) {
	args := strings.Join(buildConnectRunArgs("", false, connectCreateOpts{variant: shellCreateVariant("desktop")}, false), " ")
	if !strings.Contains(args, "--variant desktop") {
		t.Fatalf("--variant not forwarded: %v", args)
	}
}

// terminal is base plus a bash command; under --run's --daemon that command
// would exit at once, so shell turns it into plain base.
func TestShellRunTerminalMeansBase(t *testing.T) {
	if got := shellCreateVariant("terminal"); got != "base" {
		t.Fatalf("shellCreateVariant(terminal) = %q, want base", got)
	}
}

// exec keeps the project's own variant: no --variant reaches `booth run`.
func TestExecRunKeepsProjectVariant(t *testing.T) {
	args := buildConnectRunArgs("", false, connectCreateOpts{}, false)
	for _, a := range args {
		if a == "--variant" {
			t.Fatalf("exec --run must not pick a variant: %v", args)
		}
	}
}

func TestVariantFlagTakesAValue(t *testing.T) {
	positional, flags := extractPositionalAndFlags([]string{"--variant", "desktop", "demo"})
	if len(positional) != 1 || positional[0] != "demo" || strings.Join(flags, " ") != "--variant desktop" {
		t.Fatalf("positional=%v flags=%v", positional, flags)
	}
}
