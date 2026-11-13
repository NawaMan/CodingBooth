// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// --booth-isolation kata (experimental): the booth itself runs in its own Kata
// Containers VM instead of as an ordinary container on the host kernel. It is
// the same `docker run` with Kata's runtime, so the image, the coder user, the
// code mount (virtio-fs) and the published port are unchanged; a way out of the
// container lands in the VM. See docs/BOOTH_SECURITY.md#booth-isolation.
const (
	// The booth's VM when --vm-memory / --vm-cpus are not given. Kata's own
	// default (2 GB, 1 CPU) is too small to build or run most examples.
	kataBoothDefaultMemory = "4g"
	kataBoothDefaultCpus   = "2"
)

// ResolveBoothIsolation settles, before anything is asked, built or started,
// whether a requested --booth-isolation kata can run on this machine. When it
// cannot (macOS, Windows, Docker Desktop, no /dev/kvm, Kata not installed), the
// booth runs as an ordinary container — never silently: a banner says so. When
// it can, run-args that cannot work inside a Kata VM are refused here, before
// anything is built.
func ResolveBoothIsolation(ctx appctx.AppContext) (appctx.AppContext, error) {
	exists := func(path string) bool { _, err := os.Stat(path); return err == nil }
	check := func() error {
		return kataBoothPreflight(ctx.Engine(), runtime.GOOS, exists, exec.LookPath, engineIsDockerDesktop)
	}
	ctx, banner := resolveBoothIsolation(ctx, check)
	if banner != "" {
		fmt.Fprint(os.Stderr, banner)
	}
	if !ctx.BoothKata() {
		return ctx, nil
	}
	if memory := ctx.VmMemory(); memory != "" && appctx.DindVmMemoryMiB(memory) < 256 {
		return ctx, fmt.Errorf("invalid vm-memory %q (expected a size like 4g or 4096m, at least 256m)", memory)
	}
	if cpus := ctx.VmCpus(); cpus != "" {
		if n, err := strconv.Atoi(cpus); err != nil || n < 1 {
			return ctx, fmt.Errorf("invalid vm-cpus %q (expected a whole number of CPUs, 1 or more)", cpus)
		}
	}
	if refused := kataBoothRefusals(flattenUserArgs(ctx)); len(refused) > 0 {
		return ctx, fmt.Errorf("--booth-isolation kata cannot run a booth with %s: a Kata VM does not support %s. Remove %s, or run without --booth-isolation. See docs/BOOTH_SECURITY.md#booth-isolation",
			strings.Join(refused, ", "), pluralIt(len(refused)), pluralIt(len(refused)))
	}
	return ctx, nil
}

func pluralIt(n int) string {
	if n == 1 {
		return "it"
	}
	return "them"
}

func resolveBoothIsolation(ctx appctx.AppContext, check func() error) (appctx.AppContext, string) {
	if !ctx.BoothKata() {
		return ctx, ""
	}
	err := check()
	if err == nil {
		return ctx, ""
	}
	builder := ctx.ToBuilder()
	builder.Config.BoothIsolation = ""
	builder.Config.BoothIsolationUnavailable = err.Error()
	ctx = builder.Build()
	return ctx, kataBoothFallbackBanner(ctx.BoothIsolationUnavailable())
}

// kataBoothPreflight is kataPreflight worded for the booth.
func kataBoothPreflight(engine, goos string, exists func(string) bool, lookPath func(string) (string, error), dockerDesktop func() bool) error {
	err := kataPreflight(engine, goos, exists, lookPath, dockerDesktop)
	if err == nil {
		return nil
	}
	msg := strings.ReplaceAll(err.Error(), "--dind-isolation kata", "--booth-isolation kata")
	msg = strings.ReplaceAll(msg, "#dind-isolation", "#booth-isolation")
	return fmt.Errorf("%s", msg)
}

// kataBoothFallbackBanner says the booth is not in a VM after all. An ordinary
// container is what every other booth is, so it goes on without asking.
func kataBoothFallbackBanner(reason string) string {
	return "\n" +
		"⚠️ ⚠️ ⚠️  BOOTH ISOLATION (KATA) WAS ASKED FOR, BUT IS NOT AVAILABLE ON THIS MACHINE  ⚠️ ⚠️ ⚠️\n" +
		"    " + reason + "\n" +
		"    Going on as an ORDINARY CONTAINER instead — not a Kata VM.\n"
}

// kataBoothRefusals lists the run-args a Kata VM cannot honour: --privileged
// (Kata then tries to pass every host device into the VM, and fails), GPUs, and
// the host's network, PID or IPC namespace (the VM has its own kernel, so there
// is no host namespace to join).
func kataBoothRefusals(args []string) []string {
	var refused []string
	seen := map[string]bool{}
	add := func(what string) {
		if !seen[what] {
			seen[what] = true
			refused = append(refused, what)
		}
	}
	for i := 0; i < len(args); i++ {
		flag, value, hasValue := strings.Cut(args[i], "=")
		next := func() string {
			if hasValue {
				return value
			}
			if i+1 < len(args) {
				i++
				return args[i]
			}
			return ""
		}
		switch flag {
		case "--privileged":
			if !hasValue || strings.EqualFold(value, "true") {
				add("--privileged")
			}
		case "--gpus":
			next()
			add("--gpus")
		case "--network", "--net", "--pid", "--ipc":
			if v := next(); v == "host" {
				add(flag + "=host")
			}
		}
	}
	return refused
}

// kataBoothRunArgs is what --booth-isolation kata adds to the booth's own
// `docker run`: Kata's runtime, the VM's size (Kata reads it from annotations;
// -m/--cpus would only add to its default), and a resolv.conf naming the host's
// real resolvers — Docker's embedded DNS (127.0.0.11), which a booth on a
// user-defined network (the DinD network) is given, does not answer inside the VM.
func kataBoothRunArgs(memory, cpus, resolvConf string) [][]string {
	if memory == "" {
		memory = kataBoothDefaultMemory
	}
	if cpus == "" {
		cpus = kataBoothDefaultCpus
	}
	args := [][]string{
		{"--runtime", kataRuntime},
		{"--label", "cb.booth-isolation=kata"},
		{"-e", "BOOTH_ISOLATION=kata"},
	}
	if mib := appctx.DindVmMemoryMiB(memory); mib > 0 {
		args = append(args, []string{"--annotation", "io.katacontainers.config.hypervisor.default_memory=" + strconv.Itoa(mib)})
	}
	if n, err := strconv.Atoi(cpus); err == nil && n > 0 {
		args = append(args, []string{"--annotation", "io.katacontainers.config.hypervisor.default_vcpus=" + strconv.Itoa(n)})
	}
	if resolvConf != "" {
		args = append(args, []string{"-v", resolvConf + ":/etc/resolv.conf:ro"})
	}
	return args
}

// kataBoothResolvConf is the resolv.conf the booth's VM gets: the host's real
// resolvers (upstreamNameservers, as the Kata DinD sidecar uses).
func kataBoothResolvConf(readFile func(string) ([]byte, error)) string {
	return strings.Join(upstreamNameservers(readFile), "\n") + "\n"
}

// writeKataBoothResolvConf writes that resolv.conf where the booth can mount it:
// .booth/.tmp/ when the project has a .booth/, else the system temp directory.
func writeKataBoothResolvConf(ctx appctx.AppContext) (string, error) {
	dir := os.TempDir()
	name := "codingbooth-resolv-" + ctx.Name() + ".conf"
	if boothDir := hostBoothDir(ctx); boothDir != "" {
		if info, err := os.Stat(filepath.Join(boothDir, ".tmp")); err == nil && info.IsDir() {
			dir, name = filepath.Join(boothDir, ".tmp"), "booth-resolv.conf"
		}
	}
	// Written under --dryrun too: it is a scratch file, and the run it shows mounts it.
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(kataBoothResolvConf(os.ReadFile)), 0o644); err != nil {
		return "", err
	}
	return path, nil
}

// SetupBoothIsolation adds kataBoothRunArgs to the booth's run. It runs after
// SetupDind, so a booth on the DinD network is covered too.
func SetupBoothIsolation(ctx appctx.AppContext) (appctx.AppContext, error) {
	if !ctx.BoothKata() {
		return ctx, nil
	}
	resolvConf, err := writeKataBoothResolvConf(ctx)
	if err != nil {
		return ctx, fmt.Errorf("--booth-isolation kata: cannot write the booth's resolv.conf: %w", err)
	}
	builder := ctx.ToBuilder()
	for _, arg := range kataBoothRunArgs(ctx.VmMemory(), ctx.VmCpus(), resolvConf) {
		builder.CommonArgs.Append(ilist.NewList[string](arg...))
	}
	return builder.Build(), nil
}
