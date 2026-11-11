// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import "bytes"

// Booth is one booth as `booth dash` shows it: the fields of `booth list`, plus
// the CodingBooth version that created it.
type Booth struct {
	Name      string
	Engine    string
	State     string // the engine's state: "running", "exited", "created", …
	Variant   string
	CodePath  string
	Port      string
	PortTLS   bool // Port serves HTTPS (a --public booth)
	CreatedAt string
	// StartedAt / FinishedAt: when the engine last started / stopped it
	// (RFC 3339), "" when it does not say.
	StartedAt  string
	FinishedAt string
	// BoothDir is the .booth directory the booth reads; "" means <CodePath>/.booth.
	BoothDir  string
	Version   string
	Daemon    bool
	KeepAlive bool
}

// Running reports whether the engine says the booth is running.
func (b Booth) Running() bool { return b.State == "running" }

// URL is the booth's page on this host, or "" when it publishes no port.
func (b Booth) URL() string {
	if b.Port == "" {
		return ""
	}
	scheme := "http"
	if b.PortTLS {
		scheme = "https"
	}
	return scheme + "://localhost:" + b.Port
}

// Snapshot lists the booths of engine (or, when engine is "", of every engine
// `booth list` would ask). It writes nothing: an engine that could not answer
// while others did comes back as a line in warnings, not on stderr, so a
// full-screen caller can show it without corrupting its screen.
func Snapshot(engine string) (booths []Booth, warnings []string, err error) {
	var stderr bytes.Buffer
	containers, err := managedContainersAcross(resolveLifecycleEngines("", engine), false, &stderr)
	warnings = nonEmptyLines(stderr.String())
	if err != nil {
		return nil, warnings, err
	}
	return boothsFrom(containers), warnings, nil
}

func boothsFrom(containers []managedContainer) []Booth {
	booths := make([]Booth, 0, len(containers))
	for _, c := range containers {
		booths = append(booths, Booth{
			Name: c.Name, Engine: c.Engine, State: c.State, Variant: c.Variant,
			CodePath: c.CodePath, Port: c.Port, PortTLS: c.PortTLS, CreatedAt: c.CreatedAt, Version: c.Version,
			StartedAt: c.StartedAt, FinishedAt: c.FinishedAt, BoothDir: c.BoothDir,
			Daemon: c.Daemon, KeepAlive: c.KeepAlive,
		})
	}
	return booths
}
