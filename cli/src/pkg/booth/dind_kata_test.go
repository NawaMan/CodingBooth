// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"errors"
	"os"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/hostescape"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func kataCtx(dind bool, isolation string, egress bool) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dind = dind
	builder.Config.DindIsolation = isolation
	builder.Config.Egress = egress
	builder.Config.Engine = "docker"
	return builder.Build()
}

func TestKataDindSidecarArgs(t *testing.T) {
	args := kataDindSidecarArgs("b-10000-dind", "b-10000-net", "b", []string{"8080:8080"},
		[]string{"nameserver 192.168.2.1", "nameserver 9.9.9.9"}, 4096, 2)
	line := strings.Join(args, " ")

	for _, want := range []string{
		"--runtime io.containerd.kata.v2",
		"--cap-add ALL",
		"--security-opt systempaths=unconfined",
		"--network b-10000-net",
		"--label cb.parent=b",
		"--label cb.dind-isolation=kata",
		"--annotation io.katacontainers.config.hypervisor.default_memory=4096",
		"--annotation io.katacontainers.config.hypervisor.default_vcpus=2",
		"-p 8080:8080",
		"DIND_NAMESERVERS=nameserver 192.168.2.1;nameserver 9.9.9.9",
		"--entrypoint sh " + kataDindImage + " -c ",
	} {
		if !strings.Contains(line, want) {
			t.Errorf("sidecar args missing %q:\n%s", want, line)
		}
	}
	// --privileged under Kata hands the host's devices to the VM: the very thing
	// this mode removes. And the booth publishes its own front door.
	for _, unwanted := range []string{"--privileged", "--cgroupns", "/sys/fs/cgroup:/sys/fs/cgroup", ":10000"} {
		if strings.Contains(line, unwanted) {
			t.Errorf("sidecar args must not contain %q:\n%s", unwanted, line)
		}
	}
}

func TestKataDindSidecarArgs_DefaultSize(t *testing.T) {
	line := strings.Join(kataDindSidecarArgs("d", "n", "b", nil, nil, 0, 0), " ")
	if strings.Contains(line, "--annotation") {
		t.Errorf("no size given, so no annotation expected:\n%s", line)
	}
}

func TestKataDindStartupScript(t *testing.T) {
	for _, want := range []string{
		"mount -o remount,rw /sys/fs/cgroup",
		"mknod /dev/kmsg c 1 11",
		"> /etc/resolv.conf",
		"mkfs.ext4",
		"mount -o loop /dind-disk/docker.img /var/lib/docker",
		"exec dockerd-entrypoint.sh",
	} {
		if !strings.Contains(kataDindStartupScript, want) {
			t.Errorf("startup script missing %q", want)
		}
	}
}

func TestUpstreamNameservers(t *testing.T) {
	files := map[string]string{
		"/run/systemd/resolve/resolv.conf": "# resolved\nnameserver 192.168.2.1\nnameserver 127.0.0.53\nsearch lan\nnameserver ::1\nnameserver 2001:db8::1\n",
		"/etc/resolv.conf":                 "nameserver 127.0.0.53\n",
	}
	read := func(path string) ([]byte, error) {
		if s, ok := files[path]; ok {
			return []byte(s), nil
		}
		return nil, os.ErrNotExist
	}
	got := strings.Join(upstreamNameservers(read), ";")
	if want := "nameserver 192.168.2.1;nameserver 2001:db8::1"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}

	// Only a loopback stub anywhere: public resolvers stand in.
	delete(files, "/run/systemd/resolve/resolv.conf")
	if got := strings.Join(upstreamNameservers(read), ";"); got != "nameserver 1.1.1.1;nameserver 8.8.8.8" {
		t.Errorf("fallback: got %q", got)
	}
}

func TestKataPreflight(t *testing.T) {
	found := func(string) (string, error) { return "/usr/local/bin/" + kataShim, nil }
	missing := func(string) (string, error) { return "", errors.New("not found") }
	yes := func(string) bool { return true }
	no := func(string) bool { return false }
	desktop := func() bool { return true }
	engine := func() bool { return false }

	cases := []struct {
		name    string
		err     error
		wantErr string
	}{
		{"ready", kataPreflight("docker", "linux", yes, found, engine), ""},
		{"podman", kataPreflight("podman", "linux", yes, found, engine), "needs engine docker"},
		{"macos", kataPreflight("docker", "darwin", yes, found, engine), "needs Linux"},
		{"windows", kataPreflight("docker", "windows", yes, found, engine), "needs Linux"},
		{"desktop", kataPreflight("docker", "linux", yes, found, desktop), "Docker Desktop"},
		{"no kvm", kataPreflight("docker", "linux", no, found, engine), "/dev/kvm is missing"},
		{"no shim", kataPreflight("docker", "linux", yes, missing, engine), kataShim + " is not on PATH"},
	}
	for _, c := range cases {
		switch {
		case c.wantErr == "" && c.err != nil:
			t.Errorf("%s: unexpected %v", c.name, c.err)
		case c.wantErr != "" && (c.err == nil || !strings.Contains(c.err.Error(), c.wantErr)):
			t.Errorf("%s: err = %v, want %q", c.name, c.err, c.wantErr)
		}
	}
}

func TestResolveDindIsolation_Available(t *testing.T) {
	ctx, banner := resolveDindIsolation(kataCtx(true, "kata", false), func() error { return nil })
	if !ctx.DindKata() || banner != "" || ctx.DindIsolationUnavailable() != "" {
		t.Errorf("Kata available: want kata kept, no banner; got kata=%t banner=%q", ctx.DindKata(), banner)
	}
}

func TestResolveDindIsolation_FallsBack(t *testing.T) {
	ctx, banner := resolveDindIsolation(kataCtx(true, "kata", false), func() error {
		return errors.New("--dind-isolation kata needs Linux; this is darwin.")
	})
	if ctx.DindKata() || !ctx.Dind() {
		t.Errorf("want plain --dind after the fallback; got kata=%t dind=%t", ctx.DindKata(), ctx.Dind())
	}
	if !strings.Contains(ctx.DindIsolationUnavailable(), "needs Linux") {
		t.Errorf("the reason should be kept; got %q", ctx.DindIsolationUnavailable())
	}
	for _, want := range []string{"NOT AVAILABLE ON THIS MACHINE", "needs Linux", "PLAIN, PRIVILEGED DinD sidecar", "--dind-allowed"} {
		if !strings.Contains(banner, want) {
			t.Errorf("banner missing %q:\n%s", want, banner)
		}
	}
}

func TestResolveDindIsolation_NotAskedFor(t *testing.T) {
	called := false
	_, banner := resolveDindIsolation(kataCtx(true, "", false), func() error { called = true; return nil })
	if called || banner != "" {
		t.Errorf("plain --dind must not run the Kata check; called=%t banner=%q", called, banner)
	}
}

// After a fallback the booth is a plain privileged --dind, so the usual consent applies:
// refused with no terminal, allowed by --dind-allowed.
func TestConsent_KataFallback_AsksLikePlainDind(t *testing.T) {
	resetApprovals(t)
	ctx, _ := resolveDindIsolation(kataCtx(true, "kata", false), func() error { return errors.New("no kata here") })
	env, warnings, _ := testConsentEnv("", true)
	if err := ensureHostEscapeConsent(ctx, env); err == nil || !strings.Contains(err.Error(), "--dind-allowed") {
		t.Fatalf("no terminal, no --dind-allowed: want a refusal naming --dind-allowed, got %v", err)
	}
	if !strings.Contains(warnings.String(), "--dind (privileged Docker-in-Docker sidecar)") {
		t.Errorf("want the --dind warning, got %q", warnings.String())
	}

	resetApprovals(t)
	builder := ctx.ToBuilder()
	builder.Config.DindAllowed = true
	env, _, opened := testConsentEnv("", true)
	if err := ensureHostEscapeConsent(builder.Build(), env); err != nil || *opened != 0 {
		t.Errorf("--dind-allowed: want it to go on without asking; err=%v opened=%d", err, *opened)
	}
}

func TestKataForwardPorts(t *testing.T) {
	got := strings.Join(kataForwardPorts([]string{"8080:8080", "127.0.0.1:18080:80", "9000:8080", "5353:53/udp", "1000-1002:1000-1002"}), " ")
	if got != "8080 80" {
		t.Errorf("got %q, want %q", got, "8080 80")
	}
}

func TestSharesSidecarNetns(t *testing.T) {
	cases := []struct {
		name               string
		dind               bool
		isolation          string
		egress, wantShared bool
	}{
		{name: "plain booth"},
		{name: "dind", dind: true, wantShared: true},
		{name: "dind kata", dind: true, isolation: "kata", wantShared: false},
		{name: "egress", egress: true, wantShared: true},
	}
	for _, c := range cases {
		if got := sharesSidecarNetns(kataCtx(c.dind, c.isolation, c.egress)); got != c.wantShared {
			t.Errorf("%s: sharesSidecarNetns = %t, want %t", c.name, got, c.wantShared)
		}
	}
}

func TestConsent_DindKata_DoesNotAsk(t *testing.T) {
	resetApprovals(t)
	env, warnings, opened := testConsentEnv("", true)
	if err := ensureHostEscapeConsent(kataCtx(true, "kata", false), env); err != nil {
		t.Fatalf("a Kata sidecar shares nothing from this machine; should not refuse: %v", err)
	}
	if *opened != 0 || warnings.Len() != 0 {
		t.Fatalf("should not warn or ask; opened=%d warnings=%q", *opened, warnings.String())
	}
}

func TestDindWarning_PointsAtIsolation(t *testing.T) {
	host := hostescape.Format([]hostescape.Reason{{Kind: hostescape.KindDind, What: "--dind", Where: hostescape.WhereHost}})
	if !strings.Contains(host, "--dind-isolation kata") || !strings.Contains(host, "#dind-isolation") {
		t.Errorf("a --dind warning on Docker Engine should point at --dind-isolation:\n%s", host)
	}
	// In a VM-based engine Kata is not available, so there is nothing to point at.
	vm := hostescape.Format([]hostescape.Reason{{Kind: hostescape.KindDind, What: "--dind", Where: hostescape.WhereVM}})
	if strings.Contains(vm, "--dind-isolation") {
		t.Errorf("no --dind-isolation hint expected on a VM engine:\n%s", vm)
	}
}
