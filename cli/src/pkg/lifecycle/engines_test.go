// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeEngine is a stand-in "docker", "podman" or "container" (Apple container)
// binary. booths are the names its `ps` (or, for container, `ls`) reports, each
// shown as running; fail makes every call exit 1, like an engine whose daemon
// is down.
type fakeEngine struct {
	booths []string
	fail   bool
	// lowPorts (container only): every booth carries cb.apple-low-ports=true.
	lowPorts bool
}

// installFakeEngines puts a script per engine on an otherwise empty PATH and
// returns the file every call is logged to as "<engine> <args>".
func installFakeEngines(t *testing.T, engines map[string]fakeEngine) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls.log")
	for name, engine := range engines {
		var script string
		if engine.fail {
			script = "#!/bin/sh\necho \"" + name + " $*\" >> '" + log + "'\nexit 1\n"
		} else if name == "container" {
			// Apple container answers in JSON; the adapter filters and reshapes it.
			labels := `"cb.managed":"true","cb.variant":"base"`
			if engine.lowPorts {
				labels += `,"cb.apple-low-ports":"true"`
			}
			var docs []string
			for _, booth := range engine.booths {
				docs = append(docs, `{"id":"`+booth+`","configuration":{"labels":{`+labels+`}},"status":{"state":"running"}}`)
			}
			script = "#!/bin/sh\n" +
				"echo \"" + name + " $*\" >> '" + log + "'\n" +
				"case \"$1\" in\n" +
				"ls) echo '[" + strings.Join(docs, ",") + "]' ;;\n" +
				"inspect) for last; do :; done\n" +
				"  printf '[{\"id\":\"%s\",\"configuration\":{\"labels\":{" + strings.ReplaceAll(labels, `"`, `\"`) + "}},\"status\":{\"state\":\"running\"}}]\\n' \"$last\" ;;\n" +
				"esac\n"
		} else {
			script = "#!/bin/sh\n" +
				"echo \"" + name + " $*\" >> '" + log + "'\n" +
				"case \"$1\" in\n" +
				"ps) printf '%s\\n' " + strings.Join(engine.booths, " ") + " ;;\n" +
				"inspect) for last; do :; done\n" +
				"  printf '{\"Name\":\"/%s\",\"State\":{\"Status\":\"running\"},\"Config\":{\"Labels\":{\"cb.managed\":\"true\",\"cb.variant\":\"base\"}}}\\n' \"$last\" ;;\n" +
				"esac\n"
		}
		if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
	t.Setenv("CB_ENGINE", "")
	return log
}

func readLog(t *testing.T, log string) string {
	t.Helper()
	data, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestManagedContainersAcrossMergesAndTagsEngine(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker": {booths: []string{"web", "api"}},
		"podman": {booths: []string{"lab"}},
	})

	var stderr bytes.Buffer
	got, err := managedContainersAcross([]string{"docker", "podman"}, false, &stderr)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var summary []string
	for _, container := range got {
		summary = append(summary, container.Name+"@"+container.Engine)
	}
	want := "api@docker,lab@podman,web@docker"
	if strings.Join(summary, ",") != want {
		t.Errorf("containers = %v, want %s", summary, want)
	}
	if stderr.Len() != 0 {
		t.Errorf("unexpected warning: %q", stderr.String())
	}
}

func TestManagedContainersAcrossSkipsFailingEngineWithWarning(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker": {fail: true},
		"podman": {booths: []string{"lab"}},
	})

	var stderr bytes.Buffer
	got, err := managedContainersAcross([]string{"docker", "podman"}, false, &stderr)
	if err != nil {
		t.Fatalf("one engine failing must not fail the command: %v", err)
	}
	if len(got) != 1 || got[0].Name != "lab" || got[0].Engine != "podman" {
		t.Errorf("containers = %+v, want just lab@podman", got)
	}
	if !strings.Contains(stderr.String(), "could not list docker booths") {
		t.Errorf("stderr = %q, want a docker warning", stderr.String())
	}
}

// stubAppleService makes the "is Apple container's service up" check answer running.
func stubAppleService(t *testing.T, running bool) {
	t.Helper()
	saved := appleServiceRunning
	appleServiceRunning = func() bool { return running }
	t.Cleanup(func() { appleServiceRunning = saved })
}

func TestManagedContainersAcrossIncludesApple(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {booths: []string{"mac"}},
	})

	var stderr bytes.Buffer
	got, err := managedContainersAcross([]string{"docker", "apple"}, false, &stderr)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var summary []string
	for _, container := range got {
		summary = append(summary, container.Name+"@"+container.Engine)
	}
	if want := "mac@apple,web@docker"; strings.Join(summary, ",") != want {
		t.Errorf("containers = %v, want %s", summary, want)
	}
}

func TestManagedContainersAcrossSkipsStoppedAppleQuietly(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {fail: true},
	})
	stubAppleService(t, false)

	var stderr bytes.Buffer
	got, err := managedContainersAcross([]string{"docker", "apple"}, false, &stderr)
	if err != nil {
		t.Fatalf("a stopped Apple container must not fail the command: %v", err)
	}
	if len(got) != 1 || got[0].Name != "web" {
		t.Errorf("containers = %+v, want just web@docker", got)
	}
	if stderr.Len() != 0 {
		t.Errorf("a stopped Apple container service is not worth a warning, got %q", stderr.String())
	}
}

func TestManagedContainersAcrossWarnsWhenRunningAppleFails(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {fail: true},
	})
	stubAppleService(t, true)

	var stderr bytes.Buffer
	if _, err := managedContainersAcross([]string{"docker", "apple"}, false, &stderr); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(stderr.String(), "could not list apple booths") {
		t.Errorf("stderr = %q, want an apple warning: its service is up, so the failure is real", stderr.String())
	}
}

func TestManagedContainersAcrossStoppedAppleAndFailingDockerIsDockersError(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker":    {fail: true},
		"container": {fail: true},
	})
	stubAppleService(t, false)

	var stderr bytes.Buffer
	_, err := managedContainersAcross([]string{"docker", "apple"}, false, &stderr)
	if err == nil || !strings.Contains(err.Error(), "docker") {
		t.Fatalf("err = %v, want docker's error", err)
	}
}

func TestManagedContainersAcrossAppleAloneReportsItsError(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{"container": {fail: true}})
	stubAppleService(t, false)

	var stderr bytes.Buffer
	if _, err := managedContainersAcross([]string{"apple"}, false, &stderr); err == nil {
		t.Fatal("with apple the only engine asked, its failure is the answer")
	}
}

func TestManagedContainersAcrossAllFailingIsAnError(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker": {fail: true},
		"podman": {fail: true},
	})

	var stderr bytes.Buffer
	if _, err := managedContainersAcross([]string{"docker", "podman"}, false, &stderr); err == nil {
		t.Fatal("expected an error when every engine fails")
	}
	if stderr.Len() != 0 {
		t.Errorf("warnings would only duplicate the error, got %q", stderr.String())
	}
}

func TestManagedContainersAcrossSingleEngineReturnsItsError(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{"docker": {fail: true}})

	var stderr bytes.Buffer
	if _, err := managedContainersAcross([]string{"docker"}, false, &stderr); err == nil {
		t.Fatal("expected the engine's error")
	}
}

func TestAmbiguousEngineError(t *testing.T) {
	both := []managedContainer{
		{Name: "web", Engine: "docker"},
		{Name: "web", Engine: "podman"},
		{Name: "solo", Engine: "podman"},
	}
	err := ambiguousEngineError(both, "web")
	if err == nil || !strings.Contains(err.Error(), "docker and podman") || !strings.Contains(err.Error(), "CB_ENGINE") {
		t.Errorf("ambiguousEngineError(web) = %v, want a docker-and-podman error naming CB_ENGINE", err)
	}
	if err := ambiguousEngineError(both, "solo"); err != nil {
		t.Errorf("a name on one engine is not ambiguous, got %v", err)
	}
	if err := ambiguousEngineError(both, "missing"); err != nil {
		t.Errorf("an unknown name is not ambiguous, got %v", err)
	}

	if _, err := resolveSingleContainer(both, "web", "", nil, stateAny); err == nil || !strings.Contains(err.Error(), "exists on both") {
		t.Errorf("resolveSingleContainer must refuse an ambiguous name, got %v", err)
	}
}

func TestAmbiguousEngineErrorNamesAllThreeEngines(t *testing.T) {
	all := []managedContainer{
		{Name: "web", Engine: "podman"},
		{Name: "web", Engine: "apple"},
		{Name: "web", Engine: "docker"},
	}
	err := ambiguousEngineError(all, "web")
	if err == nil || !strings.Contains(err.Error(), `"web" exists on apple, docker and podman.`) {
		t.Errorf("ambiguousEngineError = %v, want it on apple, docker and podman", err)
	}
}

func TestListShowsAppleBoothsWhenNoneChosen(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {booths: []string{"mac"}},
	})

	var stdout, stderr bytes.Buffer
	if err := List(nil, &stdout, &stderr); err != nil {
		t.Fatalf("List: %v (stderr %q)", err, stderr.String())
	}
	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	if len(lines) != 3 || !strings.Contains(lines[0], "ENGINE") {
		t.Fatalf("want an ENGINE header and 2 booths, got:\n%s", stdout.String())
	}
	if !strings.HasPrefix(lines[1], "mac") || !strings.Contains(lines[1], "apple") {
		t.Errorf("first row = %q, want mac on apple", lines[1])
	}
}

func TestStopActsOnAppleWhenAppleOwnsTheBooth(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker":    {},
		"container": {booths: []string{"mac"}},
	})

	var stderr bytes.Buffer
	if err := Stop([]string{"--name", "mac", "--force"}, &stderr); err != nil {
		t.Fatalf("Stop: %v (stderr %q)", err, stderr.String())
	}
	calls := readLog(t, log)
	if !strings.Contains(calls, "container kill mac") {
		t.Errorf("Apple container never received the kill:\n%s", calls)
	}
	if strings.Contains(calls, "docker kill") {
		t.Errorf("docker must not be asked to act on an apple booth:\n%s", calls)
	}
}

func TestListShowsBothEnginesWhenNoneChosen(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker": {booths: []string{"web"}},
		"podman": {booths: []string{"lab"}},
	})

	var stdout, stderr bytes.Buffer
	if err := List(nil, &stdout, &stderr); err != nil {
		t.Fatalf("List: %v", err)
	}
	out := stdout.String()
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 3 {
		t.Fatalf("want a header and 2 booths, got:\n%s", out)
	}
	if !strings.Contains(lines[0], "ENGINE") {
		t.Errorf("header has no ENGINE column: %q", lines[0])
	}
	if !strings.HasPrefix(lines[1], "lab") || !strings.Contains(lines[1], "podman") {
		t.Errorf("first row = %q, want lab on podman", lines[1])
	}
	if !strings.HasPrefix(lines[2], "web") || !strings.Contains(lines[2], "docker") {
		t.Errorf("second row = %q, want web on docker", lines[2])
	}
}

func TestListOfOneChosenEngineKeepsTheOldLayout(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker": {booths: []string{"web"}},
		"podman": {booths: []string{"lab"}},
	})
	t.Setenv("CB_ENGINE", "docker")

	var stdout, stderr bytes.Buffer
	if err := List(nil, &stdout, &stderr); err != nil {
		t.Fatalf("List: %v", err)
	}
	if strings.Contains(stdout.String(), "ENGINE") {
		t.Errorf("a chosen engine must not add a column:\n%s", stdout.String())
	}
	if strings.Contains(stdout.String(), "lab") {
		t.Errorf("CB_ENGINE=docker must not list podman booths:\n%s", stdout.String())
	}
}

func TestStopActsOnTheEngineThatOwnsTheBooth(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker": {},
		"podman": {booths: []string{"lab"}},
	})

	var stderr bytes.Buffer
	if err := Stop([]string{"--name", "lab"}, &stderr); err != nil {
		t.Fatalf("Stop: %v (stderr %q)", err, stderr.String())
	}
	calls := readLog(t, log)
	if !strings.Contains(calls, "podman stop") {
		t.Errorf("podman never received the stop:\n%s", calls)
	}
	if strings.Contains(calls, "docker stop") || strings.Contains(calls, "docker rm") {
		t.Errorf("docker must not be asked to act on a podman booth:\n%s", calls)
	}
}

func TestRemoveRefusesANameOnBothEngines(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker": {booths: []string{"web"}},
		"podman": {booths: []string{"web"}},
	})

	var stderr bytes.Buffer
	err := Remove([]string{"--name", "web", "--force"}, &stderr)
	if err == nil || !strings.Contains(err.Error(), "exists on both") {
		t.Fatalf("Remove = %v, want the ambiguity error", err)
	}
	if calls := readLog(t, log); strings.Contains(calls, " rm ") {
		t.Errorf("nothing may be removed when the target is ambiguous:\n%s", calls)
	}
}

func TestPruneLabelsTheEngineWhenSeveralAreQueried(t *testing.T) {
	installFakeEngines(t, map[string]fakeEngine{
		"docker": {},
		"podman": {},
	})
	// Fakes report every booth as running, so there is nothing stopped to prune;
	// this checks the multi-engine path runs end to end without error.
	var stdout, stderr bytes.Buffer
	if err := Prune([]string{"--yes"}, strings.NewReader(""), &stdout, &stderr); err != nil {
		t.Fatalf("Prune: %v", err)
	}
	if !strings.Contains(stdout.String(), "No stopped booth containers to prune.") {
		t.Errorf("stdout = %q", stdout.String())
	}
}

func TestExecActsOnAppleWhenAppleOwnsTheBooth(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {booths: []string{"mac"}},
	})

	var stderr bytes.Buffer
	if err := Exec([]string{"mac", "--", "true"}, &stderr); err != nil {
		t.Fatalf("Exec: %v (stderr %q)", err, stderr.String())
	}
	calls := readLog(t, log)
	if !strings.Contains(calls, "container exec") || !strings.Contains(calls, "mac true") {
		t.Errorf("Apple container never received the exec:\n%s", calls)
	}
	if strings.Contains(calls, "docker exec") {
		t.Errorf("docker must not be asked to exec in an apple booth:\n%s", calls)
	}
}

func TestExecActsOnDockerWhenDockerOwnsTheBooth(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {booths: []string{"mac"}},
	})

	var stderr bytes.Buffer
	if err := Exec([]string{"web", "--", "true"}, &stderr); err != nil {
		t.Fatalf("Exec: %v (stderr %q)", err, stderr.String())
	}
	calls := readLog(t, log)
	if !strings.Contains(calls, "docker exec") {
		t.Errorf("docker never received the exec:\n%s", calls)
	}
	if strings.Contains(calls, "container exec") {
		t.Errorf("Apple container must not be asked to exec in a docker booth:\n%s", calls)
	}
}

func TestShellActsOnTheEngineThatOwnsTheBooth(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {booths: []string{"mac"}},
	})

	var stderr bytes.Buffer
	if err := Shell([]string{"mac"}, &stderr); err != nil {
		t.Fatalf("Shell: %v (stderr %q)", err, stderr.String())
	}
	if calls := readLog(t, log); !strings.Contains(calls, "container exec") || strings.Contains(calls, "docker exec") {
		t.Errorf("shell must exec on Apple container only:\n%s", calls)
	}
}

func TestExecRefusesANameOnSeveralEngines(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"docker":    {booths: []string{"web"}},
		"container": {booths: []string{"web"}},
	})

	var stderr bytes.Buffer
	err := Exec([]string{"web", "--", "true"}, &stderr)
	if err == nil || !strings.Contains(err.Error(), "exists on both apple and docker") {
		t.Fatalf("Exec = %v, want the ambiguity error", err)
	}
	if calls := readLog(t, log); strings.Contains(calls, " exec ") {
		t.Errorf("nothing may run when the target is ambiguous:\n%s", calls)
	}
}

func TestExecInALowPortsBoothStartsThroughTheHelper(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"container": {booths: []string{"mac"}, lowPorts: true},
	})
	t.Setenv("CB_ENGINE", "apple")

	var stderr bytes.Buffer
	if err := Exec([]string{"mac", "--", "id"}, &stderr); err != nil {
		t.Fatalf("Exec: %v (stderr %q)", err, stderr.String())
	}
	calls := readLog(t, log)
	if !strings.Contains(calls, "container exec -u root") {
		t.Errorf("a --apple-low-ports booth's session must start as root:\n%s", calls)
	}
	if !strings.Contains(calls, "booth--as-coder") || !strings.HasSuffix(strings.TrimSpace(calls), " id") {
		t.Errorf("the session must go through booth--as-coder and end with the command:\n%s", calls)
	}
}

func TestExecInAPlainBoothStaysCoder(t *testing.T) {
	log := installFakeEngines(t, map[string]fakeEngine{
		"container": {booths: []string{"mac"}},
	})
	t.Setenv("CB_ENGINE", "apple")

	var stderr bytes.Buffer
	if err := Exec([]string{"mac", "--", "id"}, &stderr); err != nil {
		t.Fatalf("Exec: %v (stderr %q)", err, stderr.String())
	}
	calls := readLog(t, log)
	if !strings.Contains(calls, "container exec -u coder") || strings.Contains(calls, "booth--as-coder") {
		t.Errorf("a booth without the flag must exec as coder directly:\n%s", calls)
	}
}
