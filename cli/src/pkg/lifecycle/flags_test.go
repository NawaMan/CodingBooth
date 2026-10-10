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
