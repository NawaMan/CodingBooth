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
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// --dind-isolation kata (experimental): the DinD sidecar runs in its own Kata
// Containers VM instead of as a --privileged container on the host kernel, so a
// way out of the daemon lands in a throwaway VM that shares nothing from this
// machine. The booth itself is an ordinary container. See
// docs/BOOTH_SECURITY.md#dind-isolation for the findings behind each choice here.
const (
	// kataRuntime is the containerd shim name docker hands to containerd; it needs
	// containerd-shim-kata-v2 on containerd's PATH, and no daemon.json entry.
	kataRuntime = "io.containerd.kata.v2"
	kataShim    = "containerd-shim-kata-v2"

	// kataDindImage is docker:dind plus e2fsprogs (for the loop-mounted storage
	// disk below), built locally on first use. Bump the tag when the Dockerfile
	// changes.
	kataDindImage      = "codingbooth-dind-kata:1"
	kataDindDockerfile = "FROM docker:dind\nRUN apk add --no-cache e2fsprogs\n"

	// kataDindDiskSize is the sparse storage file for the sidecar's own images and
	// containers. Sparse: it takes only what is written.
	kataDindDiskSize = "64G"
)

// kataDindStartupScript runs as the sidecar's entrypoint, inside the VM, before
// dockerd. Each step answers one thing Kata does differently from runc:
//
//   - /sys and /sys/fs/cgroup arrive read-only (only --privileged makes them
//     writable, and Kata's --privileged passes the host's devices into the VM,
//     which is the exposure this mode exists to remove), so they are remounted —
//     the VM's own sysfs and cgroups, not the host's.
//   - Docker's embedded DNS (127.0.0.11) lives on the host side of the network
//     namespace and does not answer inside the VM, so the host's upstream
//     nameservers (DIND_NAMESERVERS, ";"-separated) replace it.
//   - overlayfs cannot use virtio-fs as its upper layer, and every docker volume
//     reaches the VM over virtio-fs, so /var/lib/docker is a sparse ext4 file on
//     the volume, loop-mounted inside the VM.
const kataDindStartupScript = `set -e
mount -o remount,rw /sys
mount -o remount,rw /sys/fs/cgroup
if [ -n "$DIND_NAMESERVERS" ]; then echo "$DIND_NAMESERVERS" | tr ';' '\n' > /etc/resolv.conf; fi
[ -f /dind-disk/docker.img ] || { truncate -s ` + kataDindDiskSize + ` /dind-disk/docker.img; mkfs.ext4 -q /dind-disk/docker.img; }
mount -o loop /dind-disk/docker.img /var/lib/docker
exec dockerd-entrypoint.sh`

// kataDindSidecarArgs is the `docker run` for the Kata sidecar. It publishes only
// the run-args ports (they belong to containers the sidecar runs); the booth is
// not in the sidecar's network namespace under Kata, so it publishes its own front
// door. memMiB/cpus of 0 leave Kata's defaults (2048 MiB, 1 CPU).
func kataDindSidecarArgs(dindName, dindNet, parentName string, extraPorts, nameservers []string, memMiB, cpus int) []string {
	args := []string{
		"run", "-d", "--rm",
		"--runtime", kataRuntime,
		// Everything below applies inside the VM only.
		"--cap-add", "ALL",
		"--security-opt", "apparmor=unconfined",
		"--security-opt", "seccomp=unconfined",
		"--security-opt", "systempaths=unconfined",
		"--name", dindName,
		"--network", dindNet,
		"--add-host", hostGatewayMapping,
		// Anonymous volume, removed with the sidecar (--rm), like docker:dind's own.
		"-v", "/dind-disk",
		"--label", "cb.managed=true",
		"--label", "cb.role=sidecar",
		"--label", "cb.parent=" + parentName,
		"--label", "cb.dind-isolation=kata",
	}
	if memMiB > 0 {
		args = append(args, "--annotation", "io.katacontainers.config.hypervisor.default_memory="+strconv.Itoa(memMiB))
	}
	if cpus > 0 {
		args = append(args, "--annotation", "io.katacontainers.config.hypervisor.default_vcpus="+strconv.Itoa(cpus))
	}
	for _, port := range extraPorts {
		args = append(args, "-p", port)
	}
	args = append(args,
		"-e", "DOCKER_TLS_CERTDIR=",
		"-e", "DIND_NAMESERVERS="+strings.Join(nameservers, ";"),
		"--entrypoint", "sh",
		kataDindImage, "-c", kataDindStartupScript,
	)
	return args
}

// kataDindVmSize reads --dind-vm-memory / --dind-vm-cpus (validated already).
func kataDindVmSize(ctx appctx.AppContext) (memMiB, cpus int) {
	if ctx.DindVmMemory() != "" {
		memMiB = appctx.DindVmMemoryMiB(ctx.DindVmMemory())
	}
	if ctx.DindVmCpus() != "" {
		cpus, _ = strconv.Atoi(ctx.DindVmCpus())
	}
	return memMiB, cpus
}

// upstreamNameservers reads the host's real resolvers. systemd-resolved's own
// file comes first: /etc/resolv.conf there names only its 127.0.0.53 stub, which
// the VM cannot reach. Loopback entries are dropped; with none left, public
// resolvers stand in.
func upstreamNameservers(readFile func(string) ([]byte, error)) []string {
	for _, path := range []string{"/run/systemd/resolve/resolv.conf", "/etc/resolv.conf"} {
		data, err := readFile(path)
		if err != nil {
			continue
		}
		var servers []string
		for _, line := range strings.Split(string(data), "\n") {
			fields := strings.Fields(line)
			if len(fields) < 2 || fields[0] != "nameserver" {
				continue
			}
			addr := fields[1]
			if strings.HasPrefix(addr, "127.") || addr == "::1" {
				continue
			}
			servers = append(servers, "nameserver "+addr)
		}
		if len(servers) > 0 {
			return servers
		}
	}
	return []string{"nameserver 1.1.1.1", "nameserver 8.8.8.8"}
}

// kataPreflight checks that this host can start a Kata sidecar, and says how to
// get there when it cannot.
func kataPreflight(goos string, exists func(string) bool, lookPath func(string) (string, error), dockerDesktop func() bool) error {
	const setup = "See docs/BOOTH_SECURITY.md#dind-isolation for the setup."
	if goos != "linux" {
		return fmt.Errorf("--dind-isolation kata needs Linux (Docker Engine with KVM); this is %s. %s", goos, setup)
	}
	if dockerDesktop() {
		return fmt.Errorf("--dind-isolation kata needs Docker Engine; Docker Desktop runs containers in its own VM, where Kata is not available. %s", setup)
	}
	if !exists("/dev/kvm") {
		return fmt.Errorf("--dind-isolation kata needs hardware virtualisation: /dev/kvm is missing (enable VT-x/AMD-V, or nested virtualisation in a VM). %s", setup)
	}
	if _, err := lookPath(kataShim); err != nil {
		return fmt.Errorf("--dind-isolation kata needs Kata Containers: %s is not on PATH (unpack the Kata release to /opt/kata, then: sudo ln -s /opt/kata/runtime-rs/bin/%s /usr/local/bin/). %s", kataShim, kataShim, setup)
	}
	return nil
}

// ensureKataDindImage builds kataDindImage when it is not there yet.
func ensureKataDindImage(ctx appctx.AppContext) error {
	flags := docker.DockerFlags{Dryrun: ctx.Dryrun(), Verbose: ctx.Verbose(), Silent: true, Engine: ctx.Engine()}
	if !ctx.Dryrun() {
		if _, err := docker.DockerOutput(flags, "image", ilist.NewList(ilist.NewList("inspect", kataDindImage))); err == nil {
			return nil
		}
	}
	dir, err := os.MkdirTemp("", "codingbooth-dind-kata-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(dir)
	if err := os.WriteFile(filepath.Join(dir, "Dockerfile"), []byte(kataDindDockerfile), 0o644); err != nil {
		return err
	}
	LogPrintf("Building %s (docker:dind + e2fsprogs, once)...\n", kataDindImage)
	return docker.Docker(flags, "build", ilist.NewList(ilist.NewList("-q", "-t", kataDindImage, dir)))
}

// prepareKataDind runs the preflight and makes sure the image is there.
func prepareKataDind(ctx appctx.AppContext) error {
	if !ctx.Dryrun() {
		exists := func(path string) bool { _, err := os.Stat(path); return err == nil }
		if err := kataPreflight(runtime.GOOS, exists, exec.LookPath, engineIsDockerDesktop); err != nil {
			return err
		}
	}
	return ensureKataDindImage(ctx)
}

// kataForwardPorts lists the container ports of the run-args publishes: the
// booth forwards localhost:<port> to the sidecar for each, so `curl localhost:8080`
// still reaches a container the sidecar runs (booth-entry, BOOTH_DIND_FORWARD).
func kataForwardPorts(extraPorts []string) []string {
	seen := map[string]bool{}
	var ports []string
	for _, mapping := range extraPorts {
		m, ok := ParsePortMapping(mapping)
		// socat forwards TCP; a udp publish is left to the sidecar's address.
		if !ok || m.Proto != "tcp" {
			continue
		}
		port := strings.TrimSuffix(m.Container, "/tcp")
		if n, err := strconv.Atoi(port); err != nil || n < 1 {
			continue
		}
		if !seen[port] {
			seen[port] = true
			ports = append(ports, port)
		}
	}
	return ports
}
