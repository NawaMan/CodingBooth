// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"text/tabwriter"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// Expose is the host-side entry point for `booth expose <subcommand>`. Today the
// only subcommand is `list`, which reports the ports a booth publishes to the
// host by combining the run-time manifest (.booth/.tmp/ports.json), the live
// runtime tunnels (.booth/.tmp/tcp-tunnels/), and `docker port` to confirm what
// is actually bound.
func Expose(args []string, stdout io.Writer, stderr io.Writer) error {
	if len(args) == 0 {
		return commandExit(1, exposeUsage())
	}
	switch args[0] {
	case "list", "ls":
		return exposeList(args[1:], stdout, stderr)
	case "-h", "--help", "help":
		_, _ = fmt.Fprintln(stdout, exposeUsage())
		return nil
	default:
		return commandExit(1, fmt.Sprintf("Error: unknown expose subcommand %q.\n\n%s", args[0], exposeUsage()))
	}
}

func exposeUsage() string {
	return strings.TrimSpace(`
Usage: booth expose list [name] [--name NAME]

List the ports a booth publishes to the host — the booth front door, any
published (-p) ports, and any runtime tunnels created with booth--expose.

With no name, the booth for the current directory is used.`)
}

// publishedPort mirrors pkg/booth.PublishedPort for reading ports.json. It is
// duplicated rather than imported to keep pkg/lifecycle free of a dependency on
// the run pipeline.
type publishedPort struct {
	HostIP        string `json:"host_ip"`
	HostPort      int    `json:"host_port"`
	ContainerPort int    `json:"container_port"`
	Proto         string `json:"proto"`
	Source        string `json:"source"`
}

type portManifest struct {
	Booth     string          `json:"booth"`
	Variant   string          `json:"variant"`
	Published []publishedPort `json:"published"`
}

// livePort is one actual host binding as reported by `docker port`.
type livePort struct {
	IP       string
	HostPort int
}

// exposeRow is one line of the `booth expose list` table.
type exposeRow struct {
	ContainerPort int
	HostIP        string
	HostPort      int
	Proto         string
	Kind          string // "front door" | "published" | "tunnel"
	Live          bool
	Source        string
}

func exposeList(args []string, stdout io.Writer, stderr io.Writer) error {
	positional, flags := extractPositionalAndFlags(args)

	flagSet := flag.NewFlagSet("expose list", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	flagSet.SetOutput(stderr)
	if err := flagSet.Parse(flags); err != nil {
		return commandExit(2, "")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	// Resolve by name/positional if given, else by the current directory's booth.
	codePath := ""
	if *name == "" && len(positional) == 0 {
		if cwd, cwdErr := os.Getwd(); cwdErr == nil {
			codePath = cwd
		}
	}
	target, err := resolveSingleContainer(containers, *name, codePath, positional, stateRunning)
	if err != nil {
		return commandExit(1, err.Error())
	}

	manifest := readPortManifest(target.CodePath)
	tunnels := readTunnels(target.CodePath)
	live := readLivePorts(target.Name)

	rows := buildExposeRows(manifest, tunnels, live)
	printExposeRows(stdout, target, rows)
	return nil
}

// readPortManifest loads .booth/.tmp/ports.json, returning nil when it is absent
// or unreadable (an older booth, or one brought up by `docker start`). Callers
// fall back to the live `docker port` view in that case.
func readPortManifest(codePath string) *portManifest {
	if codePath == "" {
		return nil
	}
	path := filepath.Join(codePath, ".booth", ".tmp", "ports.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var m portManifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil
	}
	return &m
}

// readTunnels reads the runtime tunnel control files: filename is the container
// port, contents the external (host) port. Mirrors booth--expose / tcp_tunnel.go.
func readTunnels(codePath string) map[int]int {
	tunnels := make(map[int]int)
	if codePath == "" {
		return tunnels
	}
	dir := filepath.Join(codePath, ".booth", ".tmp", "tcp-tunnels")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return tunnels
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		containerPort, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			continue
		}
		externalPort, err := strconv.Atoi(strings.TrimSpace(string(data)))
		if err != nil {
			continue
		}
		tunnels[containerPort] = externalPort
	}
	return tunnels
}

// readLivePorts parses `docker port <name>`, whose lines look like
// "10000/tcp -> 127.0.0.1:11000". It is keyed by "<containerPort>/<proto>" so a
// manifest entry can be confirmed against what is actually bound right now.
func readLivePorts(containerName string) map[string][]livePort {
	live := make(map[string][]livePort)
	out, err := docker.DockerOutput(docker.DockerFlags{Silent: true}, "port", ilist.NewList(
		ilist.NewList(containerName),
	))
	if err != nil {
		return live
	}
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		key, lp, ok := parseDockerPortLine(line)
		if !ok {
			continue
		}
		live[key] = append(live[key], lp)
	}
	return live
}

// parseDockerPortLine parses one "10000/tcp -> 127.0.0.1:11000" line into a
// "<containerPort>/<proto>" key and its host binding.
func parseDockerPortLine(line string) (string, livePort, bool) {
	parts := strings.SplitN(line, " -> ", 2)
	if len(parts) != 2 {
		return "", livePort{}, false
	}
	containerSpec := strings.TrimSpace(parts[0]) // "10000/tcp"
	hostSpec := strings.TrimSpace(parts[1])      // "127.0.0.1:11000"

	proto := "tcp"
	containerPort := containerSpec
	if slash := strings.Index(containerSpec, "/"); slash >= 0 {
		containerPort = containerSpec[:slash]
		proto = containerSpec[slash+1:]
	}
	if _, err := strconv.Atoi(containerPort); err != nil {
		return "", livePort{}, false
	}

	ip, portText := splitHostPort(hostSpec)
	hostPort, err := strconv.Atoi(portText)
	if err != nil {
		return "", livePort{}, false
	}
	return containerPort + "/" + proto, livePort{IP: ip, HostPort: hostPort}, true
}

// splitHostPort splits "IP:PORT" keeping IPv6 (":" in the address) intact by
// splitting on the last colon.
func splitHostPort(spec string) (ip, port string) {
	idx := strings.LastIndex(spec, ":")
	if idx < 0 {
		return "", spec
	}
	return spec[:idx], spec[idx+1:]
}

// buildExposeRows merges the manifest, live docker bindings, and tunnels into the
// table rows. It is pure so the merge can be unit-tested without Docker. When the
// manifest is present it drives the published rows (carrying the source label),
// confirmed live against docker port; any live binding the manifest does not
// cover is still listed. When the manifest is absent, the live bindings are the
// source of published rows. Tunnels are always appended.
func buildExposeRows(manifest *portManifest, tunnels map[int]int, live map[string][]livePort) []exposeRow {
	var rows []exposeRow
	covered := make(map[string]bool) // "<containerPort>/<proto>" the manifest accounted for

	if manifest != nil {
		for _, p := range manifest.Published {
			proto := p.Proto
			if proto == "" {
				proto = "tcp"
			}
			key := strconv.Itoa(p.ContainerPort) + "/" + proto
			covered[key] = true

			kind := "published"
			if strings.Contains(p.Source, "front door") {
				kind = "front door"
			}
			rows = append(rows, exposeRow{
				ContainerPort: p.ContainerPort,
				HostIP:        p.HostIP,
				HostPort:      p.HostPort,
				Proto:         proto,
				Kind:          kind,
				Live:          liveHasPort(live, key, p.HostPort),
				Source:        p.Source,
			})
		}
	}

	// Live bindings not described by the manifest (older booth, or a mapping added
	// out of band). Sorted for deterministic output.
	var liveKeys []string
	for key := range live {
		if !covered[key] {
			liveKeys = append(liveKeys, key)
		}
	}
	sort.Strings(liveKeys)
	for _, key := range liveKeys {
		containerPort, proto := splitPortKey(key)
		source := "docker (live)"
		if manifest == nil {
			source = "published (-p)"
		}
		for _, lp := range dedupeBindings(live[key]) {
			rows = append(rows, exposeRow{
				ContainerPort: containerPort,
				HostIP:        lp.IP,
				HostPort:      lp.HostPort,
				Proto:         proto,
				Kind:          "published",
				Live:          true,
				Source:        source,
			})
		}
	}

	// Runtime tunnels, sorted by container port.
	var tunnelPorts []int
	for cp := range tunnels {
		tunnelPorts = append(tunnelPorts, cp)
	}
	sort.Ints(tunnelPorts)
	for _, cp := range tunnelPorts {
		rows = append(rows, exposeRow{
			ContainerPort: cp,
			HostIP:        "127.0.0.1",
			HostPort:      tunnels[cp],
			Proto:         "tcp",
			Kind:          "tunnel",
			Live:          true,
			Source:        "booth--expose",
		})
	}

	return rows
}

// dedupeBindings collapses the IPv4/IPv6 pair Docker emits for a wildcard bind
// (0.0.0.0 and [::] / :: on the same host port) into a single "0.0.0.0" row,
// while keeping distinct pinned addresses (e.g. 127.0.0.1) apart. Order of first
// appearance is preserved.
func dedupeBindings(bindings []livePort) []livePort {
	seen := make(map[string]bool)
	var out []livePort
	for _, lp := range bindings {
		ip := lp.IP
		if ip == "::" || ip == "[::]" {
			ip = "0.0.0.0"
		}
		key := ip + ":" + strconv.Itoa(lp.HostPort)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, livePort{IP: ip, HostPort: lp.HostPort})
	}
	return out
}

func liveHasPort(live map[string][]livePort, key string, hostPort int) bool {
	for _, lp := range live[key] {
		if lp.HostPort == hostPort {
			return true
		}
	}
	return false
}

func splitPortKey(key string) (int, string) {
	proto := "tcp"
	portText := key
	if slash := strings.Index(key, "/"); slash >= 0 {
		portText = key[:slash]
		proto = key[slash+1:]
	}
	port, _ := strconv.Atoi(portText)
	return port, proto
}

func printExposeRows(stdout io.Writer, target managedContainer, rows []exposeRow) {
	if len(rows) == 0 {
		_, _ = fmt.Fprintf(stdout, "Booth %q publishes no ports.\n", target.Name)
		return
	}

	writer := tabwriter.NewWriter(stdout, 0, 4, 2, ' ', 0)
	_, _ = fmt.Fprintln(writer, "CONTAINER\tHOST\tPROTO\tKIND\tLIVE\tSOURCE")
	for _, row := range rows {
		host := formatHostBinding(row.HostIP, row.HostPort)
		live := "yes"
		if !row.Live {
			live = "no"
		}
		_, _ = fmt.Fprintf(writer, "%d\t%s\t%s\t%s\t%s\t%s\n",
			row.ContainerPort, host, row.Proto, row.Kind, live, row.Source)
	}
	_ = writer.Flush()
}

func formatHostBinding(ip string, port int) string {
	if ip == "" {
		return "0.0.0.0:" + strconv.Itoa(port)
	}
	return ip + ":" + strconv.Itoa(port)
}
