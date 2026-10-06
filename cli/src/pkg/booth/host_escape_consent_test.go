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
	"github.com/nawaman/codingbooth/src/pkg/hostescape"
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

func TestConsent_Dind_FlagSkipsPromptButStillWarns(t *testing.T) {
	resetApprovals(t)
	env, warnings, opened := testConsentEnv("", true)
	if err := ensureHostEscapeConsent(newConsentCtx(consentCase{dind: true, dindAllowed: true}), env); err != nil {
		t.Fatalf("--dind-allowed must pass: %v", err)
	}
	if *opened != 0 {
		t.Fatal("--dind-allowed must not ask")
	}
	got := warnings.String()
	for _, want := range []string{
		"--dind (privileged Docker-in-Docker sidecar)",
		hostescape.Impact(hostescape.KindDind),
		hostescape.Link(hostescape.KindDind),
		"This only matters if the booth runs code you do not trust.",
		"Allowed by --dind-allowed — starting without asking.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("warning should contain %q, got:\n%s", want, got)
		}
	}
}

func TestConsent_BothFlags_NamedInNote(t *testing.T) {
	resetApprovals(t)
	env, warnings, _ := testConsentEnv("", true)
	ctx := newConsentCtx(consentCase{dind: true, dindAllowed: true, privilegedAllowed: true, runArgs: []string{"--privileged"}})
	if err := ensureHostEscapeConsent(ctx, env); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(warnings.String(), "Allowed by --dind-allowed and --privileged-allowed — starting without asking.") {
		t.Fatalf("note should name both flags, got:\n%s", warnings.String())
	}
}

func TestConsent_PartlyCovered_WarnsAllAsksForRest(t *testing.T) {
	resetApprovals(t)
	env, warnings, opened := testConsentEnv("y\n", false)
	ctx := newConsentCtx(consentCase{dind: true, dindAllowed: true, runArgs: []string{"--network=host"}})
	if err := ensureHostEscapeConsent(ctx, env); err != nil {
		t.Fatal(err)
	}
	if *opened != 1 {
		t.Fatalf("the uncovered --network=host must still ask; opened=%d", *opened)
	}
	got := warnings.String()
	if !strings.Contains(got, "--dind (") || !strings.Contains(got, "--network=host") {
		t.Fatalf("both reasons should be listed, got:\n%s", got)
	}
	if strings.Contains(got, "starting without asking") {
		t.Fatalf("must not claim it starts without asking when it asks, got:\n%s", got)
	}
}

func TestConsent_NoRootClaimForNonRootKinds(t *testing.T) {
	for _, kind := range []hostescape.Kind{hostescape.KindHostMounts, hostescape.KindHomeMounts, hostescape.KindHostNetwork} {
		if strings.Contains(hostescape.Impact(kind), "root") {
			t.Errorf("%s: impact must not claim root: %q", kind, hostescape.Impact(kind))
		}
	}
	for _, kind := range []hostescape.Kind{hostescape.KindDind, hostescape.KindEngineSocket, hostescape.KindKernelAccess} {
		if !strings.Contains(hostescape.Impact(kind), "root") {
			t.Errorf("%s: impact should say it can lead to root: %q", kind, hostescape.Impact(kind))
		}
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
	// The second run still prints the warning, and says why it did not ask.
	env3, warnings3, opened3 := testConsentEnv("", true)
	if err := ensureHostEscapeConsent(ctx, env3); err != nil {
		t.Fatal(err)
	}
	if *opened3 != 0 || !strings.Contains(warnings3.String(), "Approved earlier in this session — starting without asking.") {
		t.Fatalf("restart should warn without asking; opened=%d warnings=%q", *opened3, warnings3.String())
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

	kernel, socket, hostFS, homeFS, network := hostescape.KindKernelAccess, hostescape.KindEngineSocket,
		hostescape.KindHostMounts, hostescape.KindHomeMounts, hostescape.KindHostNetwork
	dangerous := map[string]struct {
		kind hostescape.Kind
		args []string
	}{
		"privileged":          {kernel, []string{"--privileged"}},
		"privileged=true":     {kernel, []string{"--privileged=true"}},
		"cap SYS_ADMIN":       {kernel, []string{"--cap-add", "SYS_ADMIN"}},
		"cap=all":             {kernel, []string{"--cap-add=all"}},
		"cap CAP_ prefix":     {kernel, []string{"--cap-add", "CAP_SYS_MODULE"}},
		"device disk":         {kernel, []string{"--device", "/dev/sda"}},
		"device=disk":         {kernel, []string{"--device=/dev/sda:/dev/xvda"}},
		"device cgroup rule":  {kernel, []string{"--device-cgroup-rule", "a *:* rwm"}},
		"pid host":            {kernel, []string{"--pid", "host"}},
		"pid=host":            {kernel, []string{"--pid=host"}},
		"ipc=host":            {kernel, []string{"--ipc=host"}},
		"userns=host":         {kernel, []string{"--userns=host"}},
		"network host":        {network, []string{"--network", "host"}},
		"net=host":            {network, []string{"--net=host"}},
		"seccomp unconfined":  {kernel, []string{"--security-opt", "seccomp=unconfined"}},
		"apparmor unconfined": {kernel, []string{"--security-opt=apparmor:unconfined"}},
		"selinux off":         {kernel, []string{"--security-opt", "label=disable"}},
		"docker.sock":         {socket, []string{"-v", "/var/run/docker.sock:/var/run/docker.sock"}},
		"docker.sock ro":      {socket, []string{"-v", "/var/run/docker.sock:/var/run/docker.sock:ro"}},
		"podman.sock":         {socket, []string{"--volume=/run/podman/podman.sock:/s"}},
		"mount socket":        {socket, []string{"--mount", "type=bind,source=/run/containerd/containerd.sock,target=/c"}},
		"root fs":             {hostFS, []string{"-v", "/:/host"}},
		"etc":                 {hostFS, []string{"-v", "/etc:/host-etc"}},
		"etc file":            {hostFS, []string{"-v", "/etc/sudoers:/x"}},
		"mount etc":           {hostFS, []string{"--mount", "type=bind,src=/etc,dst=/x"}},
		"run media":           {hostFS, []string{"-v", "/run/media/me/disk/data:/x"}},
		"home":                {homeFS, []string{"-v", "/home/me:/h"}},
		"home tilde":          {homeFS, []string{"-v", "~:/h"}},
		"home dotfile":        {homeFS, []string{"-v", "~/.bashrc:/x"}},
		"home dotdir":         {homeFS, []string{"-v", "/home/me/.ssh:/x"}},
		"home cache":          {homeFS, []string{"-v", "/home/me/.m2:/home/coder/.m2"}},
		"all homes":           {homeFS, []string{"-v", "/home:/x"}},
		"docker data":         {hostFS, []string{"-v", "/var/lib/docker:/x"}},
	}
	for name, c := range dangerous {
		hits := dangerousRunArgs(c.args, env, false)
		if len(hits) != 1 {
			t.Errorf("%s: %v should be reported once, got %v", name, c.args, hits)
			continue
		}
		if hits[0].Kind != c.kind {
			t.Errorf("%s: %v kind = %s, want %s", name, c.args, hits[0].Kind, c.kind)
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

func TestLabelHostEscape_RecordsReasons(t *testing.T) {
	ctx := LabelHostEscape(newConsentCtx(consentCase{dind: true, runArgs: []string{"--privileged"}}))
	var label string
	for _, group := range ctx.CommonArgs().Slice() {
		args := group.Slice()
		for i := 0; i+1 < len(args); i++ {
			if args[i] == "--label" && strings.HasPrefix(args[i+1], hostescape.LabelKey+"=") {
				label = strings.TrimPrefix(args[i+1], hostescape.LabelKey+"=")
			}
		}
	}
	reasons := hostescape.DecodeLabel(label)
	if len(reasons) != 2 || reasons[0].Kind != hostescape.KindDind || reasons[1].What != "--privileged" {
		t.Fatalf("label should record both reasons, got %q -> %v", label, reasons)
	}
}

func TestLabelHostEscape_NothingDangerous_NoLabel(t *testing.T) {
	ctx := LabelHostEscape(newConsentCtx(consentCase{runArgs: []string{"-p", "8080:8080"}}))
	for _, group := range ctx.CommonArgs().Slice() {
		for _, arg := range group.Slice() {
			if strings.HasPrefix(arg, hostescape.LabelKey) {
				t.Fatalf("no reasons must add no label, got %q", arg)
			}
		}
	}
}

func TestSecurityWarning_IgnoresAllowedFlags(t *testing.T) {
	text, found := SecurityWarning(newConsentCtx(consentCase{dind: true, dindAllowed: true}))
	if !found || !strings.Contains(text, "--dind (") {
		t.Fatalf("--dind-allowed must not hide the warning: found=%v text=%q", found, text)
	}
	if strings.Contains(text, "starting without asking") || strings.Contains(text, "[y/N]") {
		t.Fatalf("print-security-warning text has no closing line, got %q", text)
	}
	if text, found := SecurityWarning(newConsentCtx(consentCase{})); found || text != "" {
		t.Fatalf("no reasons: found=%v text=%q", found, text)
	}
}
