// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// ExposedPort is one row of `booth expose list`, for callers outside this
// package (booth dash's port picker).
type ExposedPort struct {
	ContainerPort int
	HostIP        string
	HostPort      int
	Proto         string
	Kind          string // "front door", "published" or "tunnel"
	Live          bool   // the engine reports the binding right now
	Source        string
}

// URL is the address to open this port in a browser, or "" when it is not a
// TCP port bound on the host. A wildcard bind is opened on localhost. The
// front door on container port 10443 is the public TLS one, served over HTTPS.
func (p ExposedPort) URL() string {
	if p.HostPort <= 0 || (p.Proto != "" && p.Proto != "tcp") {
		return ""
	}
	host := p.HostIP
	switch host {
	case "", "0.0.0.0", "::", "[::]":
		host = "localhost"
	default:
		if strings.Contains(host, ":") && !strings.HasPrefix(host, "[") {
			host = "[" + host + "]"
		}
	}
	scheme := "http"
	if p.Kind == "front door" && p.ContainerPort == 10443 {
		scheme = "https"
	}
	return scheme + "://" + host + ":" + strconv.Itoa(p.HostPort)
}

// ExposedPorts lists what `booth expose list --name name --engine engine`
// lists, without printing.
func ExposedPorts(name, engine string) ([]ExposedPort, error) {
	target, err := inspectManagedContainer(name, docker.DockerFlags{Silent: true, Engine: engine})
	if err != nil {
		return nil, err
	}
	if target.State != "running" {
		return nil, fmt.Errorf("booth %q is not running", name)
	}
	target.Engine = engine
	boothDir := target.hostBoothDir()
	rows := buildExposeRows(readPortManifest(boothDir), readTunnels(boothDir),
		readLivePorts(engine, portOwner(engine, target.Name)))
	ports := make([]ExposedPort, 0, len(rows))
	for _, row := range rows {
		ports = append(ports, ExposedPort(row))
	}
	return ports, nil
}
