// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bytes"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

type consentCase struct {
	dind, dindAllowed, privilegedAllowed, dryrun bool
	engine                                       string
	runArgs                                      []string
}

func newConsentCtx(c consentCase) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	if len(c.runArgs) > 0 {
		builder.RunArgs.Append(ilist.NewListFromSlice(c.runArgs))
	}
	builder.Config.Dind = c.dind
	builder.Config.DindAllowed = c.dindAllowed
	builder.Config.PrivilegedAllowed = c.privilegedAllowed
	builder.Config.Engine = c.engine
	builder.Config.Dryrun = nillable.NewNillableBool(c.dryrun)
	return builder.Build()
}

// fakeTTY answers the prompt with a fixed line and records what was written to it.
type fakeTTY struct {
	in  *strings.Reader
	out bytes.Buffer
}

func (tty *fakeTTY) Read(p []byte) (int, error)  { return tty.in.Read(p) }
func (tty *fakeTTY) Write(p []byte) (int, error) { return tty.out.Write(p) }
func (tty *fakeTTY) Close() error                { return nil }

// testConsentEnv is a rootful host with a home at /home/me where every device exists. answer is
// what the user types; "" with noTTY means there is no terminal at all.
func testConsentEnv(answer string, noTTY bool) (consentEnv, *bytes.Buffer, *int) {
	warnings := &bytes.Buffer{}
	opened := 0
	env := consentEnv{
		euid:   0,
		home:   "/home/me",
		exists: func(string) bool { return true },
		openTTY: func() (io.ReadWriteCloser, error) {
			opened++
			if noTTY {
				return nil, errors.New("no tty")
			}
			return &fakeTTY{in: strings.NewReader(answer)}, nil
		},
		warnings: warnings,
	}
	return env, warnings, &opened
}

func resetApprovals(t *testing.T) {
	t.Helper()
	approvedReasons = map[string]bool{}
	t.Cleanup(func() { approvedReasons = map[string]bool{} })
}

func TestConsent_NothingDangerous_DoesNotAsk(t *testing.T) {
	resetApprovals(t)
	env, warnings, opened := testConsentEnv("", true)
	ctx := newConsentCtx(consentCase{runArgs: []string{"-e", "FOO=1", "-p", "8080:8080"}})
	if err := ensureHostEscapeConsent(ctx, env); err != nil {
		t.Fatalf("unexpected refusal: %v", err)
	}
	if *opened != 0 || warnings.Len() != 0 {
		t.Fatalf("should not warn or ask; opened=%d warnings=%q", *opened, warnings.String())
	}
}

func TestConsent_Dind_NoTerminal_Refuses(t *testing.T) {
	resetApprovals(t)
	env, warnings, _ := testConsentEnv("", true)
	err := ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true}), env)
	if err == nil {
		t.Fatal("--dind with no terminal and no --dind-allowed must refuse")
	}
	if !strings.Contains(err.Error(), "--dind-allowed") || strings.Contains(err.Error(), "--privileged-allowed") {
		t.Fatalf("refusal should name only --dind-allowed, got %q", err)
	}
	if !strings.Contains(warnings.String(), "--dind") {
		t.Fatalf("warning should list --dind, got %q", warnings.String())
	}
}

func TestConsent_Dind_Answers(t *testing.T) {
	for answer, wantOK := range map[string]bool{"y\n": true, "YES\n": true, "n\n": false, "\n": false, "sure\n": false} {
		resetApprovals(t)
		env, _, _ := testConsentEnv(answer, false)
		err := ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true}), env)
		if (err == nil) != wantOK {
			t.Errorf("answer %q: err=%v, want ok=%v", answer, err, wantOK)
		}
	}
}

func TestConsent_Dind_FlagSkipsPrompt(t *testing.T) {
	resetApprovals(t)
	env, warnings, opened := testConsentEnv("", true)
	if err := ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true, dindAllowed: true}), env); err != nil {
		t.Fatalf("--dind-allowed must pass: %v", err)
	}
	if *opened != 0 || warnings.Len() != 0 {
		t.Fatal("--dind-allowed must not warn or ask")
	}
}

func TestConsent_FlagsCoverOnlyTheirOwnKind(t *testing.T) {
	resetApprovals(t)
	env, _, _ := testConsentEnv("", true)
	// --dind-allowed does not cover --privileged, and vice versa.
	if ensureHostEscapeConsent(newConsentCtx(consentCase{dindAllowed: true, runArgs: []string{"--privileged"}}), env) == nil {
		t.Error("--dind-allowed must not approve --privileged run-args")
	}
	if ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true, privilegedAllowed: true}), env) == nil {
		t.Error("--privileged-allowed must not approve --dind")
	}
	if err := ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true, dindAllowed: true, privilegedAllowed: true,
		runArgs: []string{"--privileged"}}), env); err != nil {
		t.Errorf("both flags must approve both: %v", err)
	}
}

func TestConsent_Dryrun_DoesNotAsk(t *testing.T) {
	resetApprovals(t)
	env, _, opened := testConsentEnv("", true)
	if err := ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true, dryrun: true, runArgs: []string{"--privileged"}}), env); err != nil {
		t.Fatalf("dryrun starts nothing, so it must not refuse: %v", err)
	}
	if *opened != 0 {
		t.Fatal("dryrun must not ask")
	}
}

func TestConsent_RootlessPodman_DoesNotAsk(t *testing.T) {
	resetApprovals(t)
	env, _, opened := testConsentEnv("", true)
	env.euid = 1000
	ctx := newConsentCtx(consentCase{dind: true, engine: "podman", runArgs: []string{"--privileged", "--pid=host", "-v", "/etc:/x"}})
	if err := ensureHostEscapeConsent(ctx, env); err != nil {
		t.Fatalf("rootless Podman must not ask: %v", err)
	}
	if *opened != 0 {
		t.Fatal("rootless Podman must not ask")
	}
}

func TestConsent_RootlessPodman_StillAsksForEngineSocket(t *testing.T) {
	resetApprovals(t)
	env, _, _ := testConsentEnv("", true)
	env.euid = 1000
	ctx := newConsentCtx(consentCase{engine: "podman", runArgs: []string{"-v", "/var/run/docker.sock:/var/run/docker.sock"}})
	if ensureHostEscapeConsent(ctx, env) == nil {
		t.Fatal("a docker.sock mount reaches a rootful daemon even from rootless Podman")
	}
}

func TestConsent_RootfulPodman_Asks(t *testing.T) {
	resetApprovals(t)
	env, _, _ := testConsentEnv("", true)
	env.euid = 0
	if ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true, engine: "podman"}), env) == nil {
		t.Fatal("rootful Podman (sudo podman) must ask for --dind")
	}
}

func TestConsent_ApprovalRemembered_ForRestart(t *testing.T) {
	resetApprovals(t)
	env, _, opened := testConsentEnv("y\n", false)
	ctx := newConsentCtx(consentCase{dind: true})
	if err := ensureHostEscapeConsent(ctx, env); err != nil {
		t.Fatal(err)
	}
	if err := ensureHostEscapeConsent(ctx, env); err != nil {
		t.Fatal(err)
	}
	if *opened != 1 {
		t.Fatalf("a restart of an approved booth should not ask again; asked %d times", *opened)
	}
	// Something new since the approval still asks.
	env2, _, _ := testConsentEnv("", true)
	if ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true, runArgs: []string{"--privileged"}}), env2) == nil {
		t.Fatal("a new reason after approval must still ask")
	}
}

func TestDangerousRunArgs(t *testing.T) {
	env, _, _ := testConsentEnv("", true)
	env.exists = func(path string) bool { return path != "/dev/nope" }

	dangerous := map[string][]string{
		"privileged":          {"--privileged"},
		"privileged=true":     {"--privileged=true"},
		"cap SYS_ADMIN":       {"--cap-add", "SYS_ADMIN"},
		"cap=all":             {"--cap-add=all"},
		"cap CAP_ prefix":     {"--cap-add", "CAP_SYS_MODULE"},
		"device disk":         {"--device", "/dev/sda"},
		"device=disk":         {"--device=/dev/sda:/dev/xvda"},
		"device cgroup rule":  {"--device-cgroup-rule", "a *:* rwm"},
		"pid host":            {"--pid", "host"},
		"pid=host":            {"--pid=host"},
		"ipc=host":            {"--ipc=host"},
		"userns=host":         {"--userns=host"},
		"network host":        {"--network", "host"},
		"net=host":            {"--net=host"},
		"seccomp unconfined":  {"--security-opt", "seccomp=unconfined"},
		"apparmor unconfined": {"--security-opt=apparmor:unconfined"},
		"selinux off":         {"--security-opt", "label=disable"},
		"docker.sock":         {"-v", "/var/run/docker.sock:/var/run/docker.sock"},
		"docker.sock ro":      {"-v", "/var/run/docker.sock:/var/run/docker.sock:ro"},
		"podman.sock":         {"--volume=/run/podman/podman.sock:/s"},
		"mount socket":        {"--mount", "type=bind,source=/run/containerd/containerd.sock,target=/c"},
		"root fs":             {"-v", "/:/host"},
		"etc":                 {"-v", "/etc:/host-etc"},
		"etc file":            {"-v", "/etc/sudoers:/x"},
		"mount etc":           {"--mount", "type=bind,src=/etc,dst=/x"},
		"home":                {"-v", "/home/me:/h"},
		"home tilde":          {"-v", "~:/h"},
		"home dotfile":        {"-v", "~/.bashrc:/x"},
		"home dotdir":         {"-v", "/home/me/.ssh:/x"},
		"all homes":           {"-v", "/home:/x"},
		"docker data":         {"-v", "/var/lib/docker:/x"},
	}
	for name, args := range dangerous {
		if hits := dangerousRunArgs(args, env, false); len(hits) == 0 {
			t.Errorf("%s: %v should be reported", name, args)
		}
	}

	safe := map[string][]string{
		"privileged=false":  {"--privileged=false"},
		"cap NET_ADMIN":     {"--cap-add", "NET_ADMIN"},
		"cap SYS_PTRACE":    {"--cap-add=SYS_PTRACE"},
		"kvm":               {"--device", "/dev/kvm"},
		"dri":               {"--device=/dev/dri/renderD128"},
		"missing device":    {"--device", "/dev/nope"},
		"pid container":     {"--pid=container:other"},
		"network bridge":    {"--network", "mynet"},
		"seccomp profile":   {"--security-opt", "seccomp=/path/profile.json"},
		"named volume":      {"-v", "booth-pgdata:/var/lib/postgresql"},
		"project dir":       {"-v", "/home/me/work/app:/x"},
		"cred seed ro":      {"-v", "~/.aws/credentials:/etc/cb-home-seed/.aws/credentials:ro"},
		"etc ro":            {"-v", "/etc/localtime:/etc/localtime:ro"},
		"mount etc ro":      {"--mount", "type=bind,src=/etc,dst=/x,readonly"},
		"volume mount type": {"--mount", "type=volume,src=data,dst=/data"},
		"env value":         {"-e", "PRIVILEGED=--privileged"},
		"tmp":               {"-v", "/tmp/share:/share"},
	}
	for name, args := range safe {
		if hits := dangerousRunArgs(args, env, false); len(hits) != 0 {
			t.Errorf("%s: %v should not be reported, got %v", name, args, hits)
		}
	}
}
