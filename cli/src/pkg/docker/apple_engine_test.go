// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// appleListJSON is trimmed from real `container ls --all --format json`
// output (container 1.5.0): one running booth, one stopped booth, one
// unmanaged container.
const appleListJSON = `[
 {"id":"web","configuration":{"creationDate":"2026-09-30T23:16:54Z",
   "image":{"reference":"docker.io/nawaman/codingbooth:base-0.80.0"},
   "initProcess":{"environment":["PATH=/usr/bin","BOOTH_ENGINE=container"]},
   "labels":{"cb.managed":"true","cb.variant":"base","cb.code-path":"/proj/web"},
   "publishedPorts":[{"containerPort":10000,"count":1,"hostAddress":"127.0.0.1","hostPort":10077,"proto":"tcp"}]},
  "status":{"state":"running","networks":[{"ipv4Address":"192.168.64.6/24","ipv4Gateway":"192.168.64.1"}]}},
 {"id":"api","configuration":{"creationDate":"2026-09-30T20:00:00Z",
   "image":{"reference":"docker.io/nawaman/codingbooth:base-0.80.0"},
   "labels":{"cb.managed":"true","cb.parent":"web"},
   "publishedPorts":[{"containerPort":10000,"count":1,"hostAddress":"127.0.0.1","hostPort":10001,"proto":"tcp"}]},
  "status":{"state":"stopped","networks":[]}},
 {"id":"0053e2ba","configuration":{"image":{"reference":"docker.io/library/hello-world:latest"},"labels":{},"publishedPorts":[]},
  "status":{"state":"stopped","networks":[]}}
]`

func onlyStep(t *testing.T, steps []appleStep, err error) appleStep {
	t.Helper()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(steps) != 1 {
		t.Fatalf("want 1 step, got %d: %+v", len(steps), steps)
	}
	return steps[0]
}

func render(t *testing.T, step appleStep, stdout string) string {
	t.Helper()
	out, err := step.render([]byte(stdout))
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	return out
}

func TestTranslateRunArgs_PassesSupportedFlagsAndLeavesCommandAlone(t *testing.T) {
	got, err := translateRunArgs([]string{
		"-i", "--rm", "--name", "web", "-e", "A=1", "-v", "/p:/home/coder/code", "-w", "/home/coder/code",
		"--label", "cb.managed=true", "-p", "127.0.0.1:10000:10000", "--shm-size", "1g", "--env-file=/e",
		"image:tag", "bash", "-c", "echo --privileged",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{
		"-i", "--rm", "--name", "web", "-e", "A=1", "-v", "/p:/home/coder/code", "-w", "/home/coder/code",
		"--label", "cb.managed=true", "-p", "127.0.0.1:10000:10000", "--shm-size", "1g", "--env-file=/e",
		"image:tag", "bash", "-c", "echo --privileged",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got  %q\nwant %q", got, want)
	}
}

func TestTranslateRunArgs_DropsHostGatewayAndPullNever(t *testing.T) {
	got, err := translateRunArgs([]string{
		"--add-host", "host.docker.internal:host-gateway", "--pull=never", "--pull", "missing", "--privileged=false", "img",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !reflect.DeepEqual(got, []string{"img"}) {
		t.Errorf("got %q, want only the image", got)
	}
}

func TestTranslateRunArgs_RefusesUnsupportedFlags(t *testing.T) {
	for _, args := range [][]string{
		{"--privileged", "img"},
		{"--privileged=true", "img"},
		{"--device", "/dev/kvm", "img"},
		{"--pid=host", "img"},
		{"--userns", "keep-id", "img"},
		{"--sysctl", "net.ipv4.ip_unprivileged_port_start=0", "img"},
		{"--security-opt", "seccomp=unconfined", "img"},
		{"--add-host", "db:10.0.0.5", "img"},
		{"--pull=always", "img"},
	} {
		_, err := translateRunArgs(args)
		var unsupported *UnsupportedOnAppleError
		if !errors.As(err, &unsupported) {
			t.Errorf("%q: want UnsupportedOnAppleError, got %v", args, err)
			continue
		}
		if !strings.Contains(err.Error(), "not supported on engine apple") {
			t.Errorf("%q: unexpected message %q", args, err)
		}
	}
}

func TestTranslateForApple_RunIsQuiet(t *testing.T) {
	steps, err := translateForApple("run", []string{"-d", "--name", "web", "img", "--progress", "x"})
	step := onlyStep(t, steps, err)
	want := []string{"run", "--progress", "none", "-d", "--name", "web", "img", "--progress", "x"}
	if !reflect.DeepEqual(step.args, want) {
		t.Errorf("got  %q\nwant %q", step.args, want)
	}

	steps, err = translateForApple("run", []string{"--name", "web", "--progress=plain", "img"})
	step = onlyStep(t, steps, err)
	if !reflect.DeepEqual(step.args, []string{"run", "--name", "web", "--progress=plain", "img"}) {
		t.Errorf("an explicit --progress must win, got %q", step.args)
	}
}

func TestTranslateForApple_Lifecycle(t *testing.T) {
	tests := []struct {
		subcommand string
		args       []string
		want       [][]string
	}{
		{"stop", []string{"--timeout", "10", "web"}, [][]string{{"stop", "--time", "10", "web"}}},
		{"start", []string{"-ai", "web"}, [][]string{{"start", "-a", "-i", "web"}}},
		{"restart", []string{"--time", "5", "web"}, [][]string{{"stop", "--time", "5", "web"}, {"start", "web"}}},
		{"rm", []string{"-f", "web"}, [][]string{{"rm", "-f", "web"}}},
		{"pull", []string{"img:tag"}, [][]string{{"image", "pull", "img:tag"}}},
		{"build", []string{"-f", "D", "-t", "img", "--pull=false", "."}, [][]string{{"build", "-f", "D", "-t", "img", "."}}},
		{"build", []string{"--pull=true", "."}, [][]string{{"build", "--pull", "."}}},
		{"exec", []string{"-i", "-t", "-u", "coder", "web", "bash"}, [][]string{{"exec", "-i", "-t", "-u", "coder", "web", "bash"}}},
		{"volume", []string{"create", "--label", "cb.managed=true", "vol"}, [][]string{{"volume", "create", "--label", "cb.managed=true", "vol"}}},
	}
	for _, tt := range tests {
		steps, err := translateForApple(tt.subcommand, tt.args)
		if err != nil {
			t.Fatalf("%s: %v", tt.subcommand, err)
		}
		var got [][]string
		for _, step := range steps {
			got = append(got, step.args)
		}
		if !reflect.DeepEqual(got, tt.want) {
			t.Errorf("%s %q:\n got  %q\n want %q", tt.subcommand, tt.args, got, tt.want)
		}
	}
}

func TestPsQuery_FiltersAndFormats(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want string
	}{
		{"managed, all", []string{"-a", "--filter", "label=cb.managed=true", "--format", "{{.Names}}"}, "web\napi\n"},
		{"running only", []string{"--filter", "label=cb.managed=true", "--format", "{{.Names}}"}, "web\n"},
		{"anchored name with docker slash", []string{"-a", "--filter", "name=^/api$", "--format", "{{.Names}}"}, "api\n"},
		{"anchored name without slash", []string{"-a", "--filter", "name=^api$", "--format", "{{.Names}}"}, "api\n"},
		{"names and ports", []string{"--format", "{{.Names}}\t{{.Ports}}"}, "web\t127.0.0.1:10077->10000/tcp\n"},
		{"status filter", []string{"-a", "--filter", "status=exited", "-q"}, "api\n0053e2ba\n"},
		{"label key only", []string{"-a", "-f", "label=cb.parent", "--format", "{{.Names}} {{.State}}"}, "api exited\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			steps, err := psQuery(tt.args)
			step := onlyStep(t, steps, err)
			if !reflect.DeepEqual(step.args, []string{"ls", "--all", "--format", "json"}) {
				t.Errorf("step args = %q", step.args)
			}
			if got := render(t, step, appleListJSON); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}

func TestPsQuery_RejectsUnknownFilter(t *testing.T) {
	if _, err := psQuery([]string{"--filter", "ancestor=ubuntu"}); err == nil {
		t.Error("want an error for an unsupported filter")
	}
}

// TestInspectQuery_JSONMatchesDockerShape checks the fields lifecycle.go's
// inspectData reads from `inspect --format '{{json .}}'`.
func TestInspectQuery_JSONMatchesDockerShape(t *testing.T) {
	steps, err := inspectQuery([]string{"--format", "{{json .}}", "web", "api"})
	step := onlyStep(t, steps, err)
	if !reflect.DeepEqual(step.args, []string{"inspect", "web", "api"}) {
		t.Errorf("step args = %q", step.args)
	}
	lines := strings.Split(strings.TrimSpace(render(t, step, appleListJSON)), "\n")
	if len(lines) != 3 {
		t.Fatalf("want one line per container, got %d: %q", len(lines), lines)
	}

	var running, stopped struct {
		Name   string
		State  struct{ Status string }
		Config struct {
			Labels map[string]string
		}
		NetworkSettings struct {
			Ports map[string][]struct{ HostPort string }
		}
		HostConfig struct {
			PortBindings map[string][]struct{ HostPort string }
		}
	}
	if err := json.Unmarshal([]byte(lines[0]), &running); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(lines[1]), &stopped); err != nil {
		t.Fatal(err)
	}
	if running.Name != "/web" || running.State.Status != "running" || running.Config.Labels["cb.variant"] != "base" {
		t.Errorf("running = %+v", running)
	}
	if got := running.NetworkSettings.Ports["10000/tcp"][0].HostPort; got != "10077" {
		t.Errorf("running live port = %q", got)
	}
	if stopped.State.Status != "exited" {
		t.Errorf("stopped status = %q, want exited", stopped.State.Status)
	}
	if len(stopped.NetworkSettings.Ports) != 0 {
		t.Errorf("a stopped container has no live ports, got %v", stopped.NetworkSettings.Ports)
	}
	if got := stopped.HostConfig.PortBindings["10000/tcp"][0].HostPort; got != "10001" {
		t.Errorf("stopped configured port = %q", got)
	}
}

func TestInspectQuery_IndexTemplate(t *testing.T) {
	steps, err := inspectQuery([]string{"--format", `{{index .Config.Labels "cb.parent"}}`, "api"})
	step := onlyStep(t, steps, err)
	if got := render(t, step, appleListJSON); !strings.HasPrefix(got, "\n") || !strings.Contains(got, "web\n") {
		t.Errorf("got %q", got)
	}
}

func TestPortQuery(t *testing.T) {
	steps, err := portQuery([]string{"web"})
	step := onlyStep(t, steps, err)
	if got := render(t, step, appleListJSON); got != "10000/tcp -> 127.0.0.1:10077\n" {
		t.Errorf("got %q", got)
	}

	steps, err = portQuery([]string{"web", "10000"})
	step = onlyStep(t, steps, err)
	if got := render(t, step, appleListJSON); got != "127.0.0.1:10077\n" {
		t.Errorf("got %q", got)
	}
}

func TestVolumeListQuery(t *testing.T) {
	const volumes = `[{"configuration":{"driver":"local","labels":{"cb.managed":"true","cb.parent":"web"},"name":"cb-home-web","source":"/v/cb-home-web/volume.img"},"id":"cb-home-web"},
	 {"configuration":{"driver":"local","labels":{},"name":"other"},"id":"other"}]`
	steps, err := translateForApple("volume", []string{"ls", "--filter", "label=cb.managed=true", "--format", "{{.Name}}\t{{.Labels}}"})
	step := onlyStep(t, steps, err)
	if got := render(t, step, volumes); got != "cb-home-web\tcb.managed=true,cb.parent=web\n" {
		t.Errorf("got %q", got)
	}
}

func TestImageInspectQuery(t *testing.T) {
	const images = `[{"id":"419275f647eb","configuration":{"name":"docker.io/nawaman/codingbooth:base-0.80.0","descriptor":{"digest":"sha256:419275f647eb"}}}]`
	steps, err := translateForApple("image", []string{"inspect", "--format", "{{.Id}}", "nawaman/codingbooth:base-0.80.0"})
	step := onlyStep(t, steps, err)
	if !reflect.DeepEqual(step.args, []string{"image", "inspect", "nawaman/codingbooth:base-0.80.0"}) {
		t.Errorf("step args = %q", step.args)
	}
	if got := render(t, step, images); got != "sha256:419275f647eb\n" {
		t.Errorf("got %q", got)
	}
}

// installFakeContainer puts a `container` script on PATH that logs its args
// and prints appleListJSON for ls/inspect.
func installFakeContainer(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls.log")
	fixture := filepath.Join(dir, "list.json")
	if err := os.WriteFile(fixture, []byte(appleListJSON), 0o644); err != nil {
		t.Fatal(err)
	}
	script := "#!/bin/sh\necho \"container $*\" >> '" + log + "'\n" +
		"case \"$1\" in ls|inspect) /bin/cat '" + fixture + "' ;; esac\n"
	if err := os.WriteFile(filepath.Join(dir, "container"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	return log
}

func TestDockerOutput_AppleEngineAnswersPsFromJSON(t *testing.T) {
	log := installFakeContainer(t)

	out, err := DockerOutput(DockerFlags{Silent: true, Engine: EngineApple}, "ps", ilist.NewList(
		ilist.NewList("-a"),
		ilist.NewList("--filter", "label=cb.managed=true"),
		ilist.NewList("--format", "{{.Names}}"),
	))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out != "web\napi\n" {
		t.Errorf("out = %q", out)
	}
	calls, _ := os.ReadFile(log)
	if strings.TrimSpace(string(calls)) != "container ls --all --format json" {
		t.Errorf("calls = %q", calls)
	}
}

func TestDocker_AppleEngineRestartIsStopThenStart(t *testing.T) {
	log := installFakeContainer(t)

	err := Docker(DockerFlags{Silent: true, Engine: EngineApple}, "restart", ilist.NewList(
		ilist.NewList("--time", "10"),
		ilist.NewList("web"),
	))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	calls, _ := os.ReadFile(log)
	if got := strings.TrimSpace(string(calls)); got != "container stop --time 10 web\ncontainer start web" {
		t.Errorf("calls = %q", got)
	}
}

func TestDocker_AppleEngineRefusesBeforeRunning(t *testing.T) {
	log := installFakeContainer(t)

	err := Docker(DockerFlags{Engine: EngineApple}, "run", ilist.NewList(ilist.NewList("--privileged", "img")))
	var unsupported *UnsupportedOnAppleError
	if !errors.As(err, &unsupported) || unsupported.Flag != "--privileged" {
		t.Fatalf("want --privileged refused, got %v", err)
	}
	if _, statErr := os.Stat(log); statErr == nil {
		t.Error("nothing should have been run")
	}
}

func TestDocker_DryrunPrintsTranslatedAppleCommand(t *testing.T) {
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	err := Docker(DockerFlags{Dryrun: true, Engine: EngineApple}, "run", ilist.NewList(
		ilist.NewList("--name", "web"),
		ilist.NewList("--add-host", "host.docker.internal:host-gateway"),
		ilist.NewList("--pull=never", "img"),
	))

	writer.Close()
	os.Stdout = oldStdout
	var buf bytes.Buffer
	buf.ReadFrom(reader)
	output := buf.String()

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(output, "container") || !strings.Contains(output, "--name web") {
		t.Errorf("unexpected dryrun output %q", output)
	}
	if strings.Contains(output, "--add-host") || strings.Contains(output, "--pull") {
		t.Errorf("dropped flags leaked into dryrun output %q", output)
	}
}

// fakeContainerScript puts a `container` whose body is the given shell script
// alone on PATH.
func fakeContainerScript(t *testing.T, body string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "container"), []byte("#!/bin/sh\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
}

func TestAppleNetworkGateway(t *testing.T) {
	tests := []struct {
		name   string
		script string
		want   string
	}{
		// The shape `container network inspect` prints (pretty JSON, an array).
		// Shell built-ins only: PATH holds nothing but the fake.
		{"reads the gateway", `[ "$1 $2 $3" = "network inspect default" ] || exit 1
printf '%s\n' '[ { "id" : "default", "status" : { "ipv4Gateway" : "192.168.70.1", "ipv4Subnet" : "192.168.70.0/24" } } ]'
`, "192.168.70.1"},
		{"failing command falls back", "exit 1\n", AppleDefaultGateway},
		{"invalid JSON falls back", "echo not-json\n", AppleDefaultGateway},
		{"empty list falls back", "echo '[]'\n", AppleDefaultGateway},
		{"no gateway falls back", `echo '[{"status":{}}]'` + "\n", AppleDefaultGateway},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fakeContainerScript(t, tt.script)
			if got := AppleNetworkGateway("default", false); got != tt.want {
				t.Errorf("AppleNetworkGateway = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestAppleNetworkGatewayDryrunRunsNothing(t *testing.T) {
	// A command that would answer differently proves dryrun never asks it.
	fakeContainerScript(t, `echo '[{"status":{"ipv4Gateway":"10.9.9.9"}}]'`+"\n")
	if got := AppleNetworkGateway("default", true); got != AppleDefaultGateway {
		t.Errorf("dryrun gateway = %q, want the default %q", got, AppleDefaultGateway)
	}
}

func TestAppleServiceRunning(t *testing.T) {
	tests := []struct {
		name   string
		script string
		want   bool
	}{
		{"running", `echo '{"status":"running","server":{"version":"1.5.0"}}'` + "\n", true},
		{"stopped status", `echo '{"status":"stopped"}'` + "\n", false},
		{"command fails", "exit 1\n", false},
		{"not JSON", "echo running\n", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fakeContainerScript(t, tt.script)
			if got := AppleServiceRunning(); got != tt.want {
				t.Errorf("AppleServiceRunning = %t, want %t", got, tt.want)
			}
		})
	}
}

func TestTranslatePushUsesImagePush(t *testing.T) {
	steps, err := translateForApple("push", []string{"ghcr.io/team/app:v1"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(steps) != 1 || !reflect.DeepEqual(steps[0].args, []string{"image", "push", "ghcr.io/team/app:v1"}) {
		t.Errorf("push = %+v, want container image push ghcr.io/team/app:v1 (there is no top-level push)", steps)
	}
}

func TestLocalRegistryScheme(t *testing.T) {
	tests := map[string]bool{
		"localhost:5000/app:v1":                      true,
		"localhost/app:v1":                           true,
		"127.0.0.1:5055/team/app:v1":                 true,
		"[::1]:5000/app:v1":                          true,
		"ghcr.io/team/app:v1":                        false,
		"123.dkr.ecr.us-east-1.amazonaws.com/app:v1": false,
		"docker.io/library/ubuntu":                   false,
		"ubuntu:26.04":                               false, // Docker Hub
		"nawaman/codingbooth:base":                   false, // Docker Hub user repo
	}
	for ref, wantHTTP := range tests {
		got := localRegistryScheme([]string{ref})
		if wantHTTP != (len(got) == 2 && got[1] == "http") {
			t.Errorf("localRegistryScheme(%q) = %v, want http=%t", ref, got, wantHTTP)
		}
	}
}

func TestTranslatePushToLocalRegistryUsesHTTP(t *testing.T) {
	steps, err := translateForApple("push", []string{"localhost:5055/app:v1"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"image", "push", "--scheme", "http", "localhost:5055/app:v1"}
	if len(steps) != 1 || !reflect.DeepEqual(steps[0].args, want) {
		t.Errorf("push = %+v, want %v", steps, want)
	}
}
