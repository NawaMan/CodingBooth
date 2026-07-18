// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// PortManifestFile is the name, under .booth/.tmp/, of the port manifest the run
// pipeline writes so that `booth expose list` (host) and `booth--expose list`
// (in-container) can report the same published ports from either side. It is a
// run-time artifact: written on every run, wiped with the rest of .booth/.tmp/.
const PortManifestFile = "ports.json"

// PortManifest records the ports a booth publishes to the host, as decided by the
// run pipeline. It is the host-authored half of the port picture; the live view
// (what is actually listening, and which process) is added by the reader from
// `docker port` on the host or `ss` inside the container.
type PortManifest struct {
	Booth     string          `json:"booth"`
	Variant   string          `json:"variant"`
	Published []PublishedPort `json:"published"`
}

// PublishedPort is one host:container mapping handed to `docker run -p`.
type PublishedPort struct {
	HostIP        string `json:"host_ip,omitempty"` // "" means every interface
	HostPort      int    `json:"host_port"`
	ContainerPort int    `json:"container_port"`
	Proto         string `json:"proto"`
	Source        string `json:"source"` // "booth front door" | "published (-p)"
}

// buildPortManifest assembles the manifest from an AppContext whose ports have
// already been resolved (i.e. after ResolveRelativePorts / NormalizePortMappings,
// so every -p host side is an absolute port). It mirrors the mapping collection
// in NormalizePortMappings: the run-args publishes plus the booth's own front
// door (unless a dind/egress sidecar owns the published port instead).
func buildPortManifest(ctx appctx.AppContext) PortManifest {
	manifest := PortManifest{
		Booth:   boothDisplayName(ctx),
		Variant: ctx.Variant(),
	}

	// Front door first, so the list reads top-down from the booth's own URL.
	if !ctx.Dind() && !ctx.Egress() {
		containerPort := 10000
		if ctx.Public() {
			containerPort = 10443
		}
		raw := formatPortMapping(ctx.Public(), ctx.PortNumber(), containerPort)
		if m, ok := ParsePortMapping(raw); ok {
			m.Source = "booth front door"
			if p, ok := toPublishedPort(m); ok {
				manifest.Published = append(manifest.Published, p)
			}
		}
	}

	for _, m := range collectPortMappings(ctx.RunArgs(), "published (-p)") {
		if p, ok := toPublishedPort(m); ok {
			manifest.Published = append(manifest.Published, p)
		}
	}

	return manifest
}

// toPublishedPort converts a parsed PortMapping into a manifest entry. A mapping
// whose host side is still relative (an unresolved +OFFSET) or whose container
// port is not a plain number is skipped — the manifest records concrete ports
// only.
func toPublishedPort(m PortMapping) (PublishedPort, bool) {
	if m.Relative {
		return PublishedPort{}, false
	}
	containerText := m.Container
	if slash := strings.Index(containerText, "/"); slash >= 0 {
		containerText = containerText[:slash]
	}
	containerPort, err := strconv.Atoi(containerText)
	if err != nil {
		return PublishedPort{}, false
	}
	return PublishedPort{
		HostIP:        m.IP,
		HostPort:      m.Host,
		ContainerPort: containerPort,
		Proto:         m.Proto,
		Source:        m.Source,
	}, true
}

// boothDisplayName is the booth's own name if set, else its project name — the
// same fallback ensureContainerNameAvailable uses to name the container.
func boothDisplayName(ctx appctx.AppContext) string {
	if name := ctx.Name(); name != "" {
		return name
	}
	return ctx.ProjectName()
}

// WritePortManifest writes .booth/.tmp/ports.json for the run. It must run after
// PrepareBoothTmp (which creates and clears .tmp/) so the manifest is not wiped,
// and after the port-resolution steps so the mappings it records are concrete.
// Failures are non-fatal: the manifest is a convenience for the expose-list
// readers, which fall back to `docker inspect` when it is absent.
func WritePortManifest(ctx appctx.AppContext) appctx.AppContext {
	if ctx.Dryrun() {
		return ctx
	}

	codePath := ctx.Code()
	if codePath == "" {
		return ctx
	}

	tmpDir := filepath.Join(codePath, ".booth", ".tmp")
	if info, err := os.Stat(tmpDir); err != nil || !info.IsDir() {
		// PrepareBoothTmp did not create .tmp/ (no .booth/ dir): nothing to write.
		return ctx
	}

	data, err := json.MarshalIndent(buildPortManifest(ctx), "", "  ")
	if err != nil {
		return ctx
	}

	os.WriteFile(filepath.Join(tmpDir, PortManifestFile), append(data, '\n'), 0644)
	return ctx
}
