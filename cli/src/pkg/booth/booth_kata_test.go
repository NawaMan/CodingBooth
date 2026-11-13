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
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func boothKataCtx(isolation string, runArgs ...string) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	if len(runArgs) > 0 {
		builder.RunArgs.Append(ilist.NewList[string](runArgs...))
	}
	builder.Config.BoothIsolation = isolation
	builder.Config.Engine = "docker"
	return builder.Build()
}

func joinArgs(args [][]string) string {
	var parts []string
	for _, arg := range args {
		parts = append(parts, strings.Join(arg, " "))
	}
	return strings.Join(parts, " ")
}

func TestKataBoothRunArgs_Defaults(t *testing.T) {
	line := joinArgs(kataBoothRunArgs("", "", "/x/booth-resolv.conf"))
	for _, want := range []string{
		"--runtime io.containerd.kata.v2",
		"--label cb.booth-isolation=kata",
		"-e BOOTH_ISOLATION=kata",
		// Kata's own 2 GB / 1 CPU is too small for most booths.
		"--annotation io.katacontainers.config.hypervisor.default_memory=4096",
		"--annotation io.katacontainers.config.hypervisor.default_vcpus=2",
		"-v /x/booth-resolv.conf:/etc/resolv.conf:ro",
	} {
		if !strings.Contains(line, want) {
			t.Errorf("missing %q:\n%s", want, line)
		}
	}
	// -m / --cpus add to Kata's default VM instead of sizing it; --privileged
	// fails under Kata.
	for _, unwanted := range []string{"--memory", "--cpus", "--privileged"} {
		if strings.Contains(line, unwanted) {
			t.Errorf("must not contain %q:\n%s", unwanted, line)
		}
	}
}

func TestKataBoothRunArgs_Sized(t *testing.T) {
	line := joinArgs(kataBoothRunArgs("8g", "4", ""))
	for _, want := range []string{
		"default_memory=8192",
		"default_vcpus=4",
	} {
		if !strings.Contains(line, want) {
			t.Errorf("missing %q:\n%s", want, line)
		}
	}
	if strings.Contains(line, "resolv.conf") {
		t.Errorf("no resolv.conf given, none must be mounted:\n%s", line)
	}
}

func TestKataBoothRefusals(t *testing.T) {
	cases := []struct {
		args []string
		want []string
	}{
		{args: nil},
		{args: []string{"-v", "/a:/a", "--device", "/dev/fuse", "--cap-add", "NET_ADMIN"}},
		{args: []string{"--privileged"}, want: []string{"--privileged"}},
		{args: []string{"--privileged=false"}},
		{args: []string{"--gpus", "all"}, want: []string{"--gpus"}},
		{args: []string{"--gpus=all"}, want: []string{"--gpus"}},
		{args: []string{"--network", "host"}, want: []string{"--network=host"}},
		{args: []string{"--net=host", "--pid=host", "--ipc", "host"}, want: []string{"--net=host", "--pid=host", "--ipc=host"}},
		{args: []string{"--network", "mynet"}},
		{args: []string{"--privileged", "--privileged"}, want: []string{"--privileged"}},
		{args: []string{"--device", "/dev/kvm"}, want: []string{"--device /dev/kvm"}},
		{args: []string{"--device=/dev/kvm:/dev/kvm:rwm"}, want: []string{"--device /dev/kvm"}},
		{args: []string{"--device", "/dev/dri"}},
	}
	for _, c := range cases {
		got := kataBoothRefusals(c.args)
		if strings.Join(got, ",") != strings.Join(c.want, ",") {
			t.Errorf("%v: refusals = %v, want %v", c.args, got, c.want)
		}
	}
}

func TestResolveBoothIsolation_Available(t *testing.T) {
	ctx, banner := resolveBoothIsolation(boothKataCtx("kata"), func() error { return nil })
	if !ctx.BoothKata() || banner != "" {
		t.Errorf("available: BoothKata=%v banner=%q", ctx.BoothKata(), banner)
	}
}

func TestResolveBoothIsolation_FallsBack(t *testing.T) {
	ctx, banner := resolveBoothIsolation(boothKataCtx("kata"), func() error { return errors.New("no /dev/kvm") })
	if ctx.BoothKata() {
		t.Errorf("fallback: booth must no longer be Kata")
	}
	if ctx.BoothIsolationUnavailable() != "no /dev/kvm" {
		t.Errorf("fallback: reason = %q", ctx.BoothIsolationUnavailable())
	}
	for _, want := range []string{"BOOTH ISOLATION (KATA)", "no /dev/kvm", "ORDINARY CONTAINER"} {
		if !strings.Contains(banner, want) {
			t.Errorf("banner missing %q:\n%s", want, banner)
		}
	}
}

func TestResolveBoothIsolation_NotAskedFor(t *testing.T) {
	called := false
	ctx, banner := resolveBoothIsolation(boothKataCtx(""), func() error { called = true; return nil })
	if called || banner != "" || ctx.BoothKata() {
		t.Errorf("not asked for: check called=%v banner=%q kata=%v", called, banner, ctx.BoothKata())
	}
}

func TestKataBoothPreflight_NamesBoothFlag(t *testing.T) {
	exists := func(string) bool { return false }
	lookPath := func(string) (string, error) { return "", os.ErrNotExist }
	err := kataBoothPreflight("docker", "linux", exists, lookPath, func() bool { return false })
	if err == nil {
		t.Fatal("no /dev/kvm: want an error")
	}
	msg := err.Error()
	if !strings.Contains(msg, "--booth-isolation kata") || strings.Contains(msg, "--dind-isolation") {
		t.Errorf("message should name --booth-isolation only: %s", msg)
	}
	if !strings.Contains(msg, "#booth-isolation") {
		t.Errorf("message should point at #booth-isolation: %s", msg)
	}
}

func TestKataBoothResolvConf(t *testing.T) {
	read := func(path string) ([]byte, error) {
		if path == "/run/systemd/resolve/resolv.conf" {
			return []byte("nameserver 192.168.2.1\nnameserver 127.0.0.53\n"), nil
		}
		return nil, os.ErrNotExist
	}
	if got := kataBoothResolvConf(read); got != "nameserver 192.168.2.1\n" {
		t.Errorf("resolv.conf = %q", got)
	}
}

func TestKataBoothSocketMounts(t *testing.T) {
	isSocket := func(path string) bool {
		return path == "/run/user/1000/pulse/native" || path == "/home/me/app.sock"
	}
	args := []string{
		"-v", "/run/user/1000/pulse/native:/run/pulse/native:ro",
		"-v", "/home/me/code:/code",
		"--volume=~/app.sock:/app.sock",
		"--mount", "type=bind,source=/run/user/1000/pulse/native,target=/x",
		"--mount", "type=volume,source=/run/user/1000/pulse/native,target=/y",
		"-v", "named:/data",
	}
	got := strings.Join(kataBoothSocketMounts(args, "/home/me", isSocket), ",")
	want := "/run/user/1000/pulse/native,~/app.sock,/run/user/1000/pulse/native"
	if got != want {
		t.Errorf("sockets = %q, want %q", got, want)
	}
	if got := kataBoothSocketMounts([]string{"-v", "/home/me/code:/code"}, "/home/me", isSocket); len(got) != 0 {
		t.Errorf("no sockets: got %v", got)
	}
}

func TestSetsNofileUlimit(t *testing.T) {
	cases := map[string]bool{
		"":                                      false,
		"--ulimit nproc=100":                    false,
		"--ulimit nofile=4096:4096":             true,
		"--ulimit=nofile=4096":                  true,
		"-v /a:/a --ulimit memlock=-1":          false,
		"--ulimit memlock=-1 --ulimit nofile=8": true,
	}
	for line, want := range cases {
		if got := setsNofileUlimit(strings.Fields(line)); got != want {
			t.Errorf("%q: got %v, want %v", line, got, want)
		}
	}
}

func TestSetupBoothIsolation_Nofile(t *testing.T) {
	t.Setenv("TMPDIR", t.TempDir())
	ctx, err := SetupBoothIsolation(boothKataCtx("kata"))
	if err != nil {
		t.Fatal(err)
	}
	if line := joinArgs(kataCommonArgs(ctx)); !strings.Contains(line, "--ulimit "+kataNofile) {
		t.Errorf("Kata booth must get --ulimit %s:\n%s", kataNofile, line)
	}
	ctx, err = SetupBoothIsolation(boothKataCtx("kata", "--ulimit", "nofile=4096:4096"))
	if err != nil {
		t.Fatal(err)
	}
	if line := joinArgs(kataCommonArgs(ctx)); strings.Contains(line, kataNofile) {
		t.Errorf("the user's own nofile must win:\n%s", line)
	}
}

func kataCommonArgs(ctx appctx.AppContext) [][]string {
	var out [][]string
	for _, group := range ctx.CommonArgs().Slice() {
		out = append(out, group.Slice())
	}
	return out
}

func TestKataDindVmSize(t *testing.T) {
	// --dind-isolation alone, unset: Kata's own default (0 = no annotation).
	plain := boothKataCtx("")
	if mem, cpus := kataDindVmSize(plain); mem != 0 || cpus != 0 {
		t.Errorf("dind-isolation only: got %d MiB / %d CPUs, want 0 / 0", mem, cpus)
	}
	// --booth-isolation kata, unset: the booth's default VM.
	if mem, cpus := kataDindVmSize(boothKataCtx("kata")); mem != 4096 || cpus != 2 {
		t.Errorf("booth-isolation: got %d MiB / %d CPUs, want 4096 / 2", mem, cpus)
	}
	// --dind-vm-* still win.
	builder := boothKataCtx("kata").ToBuilder()
	builder.Config.DindVmMemory = "8g"
	builder.Config.DindVmCpus = "4"
	if mem, cpus := kataDindVmSize(builder.Build()); mem != 8192 || cpus != 4 {
		t.Errorf("sized: got %d MiB / %d CPUs, want 8192 / 4", mem, cpus)
	}
}
