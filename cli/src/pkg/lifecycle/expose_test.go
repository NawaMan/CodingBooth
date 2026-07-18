// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import "testing"

func TestParseDockerPortLine(t *testing.T) {
	tests := []struct {
		line    string
		wantKey string
		wantIP  string
		wantHP  int
		wantOK  bool
	}{
		{"10000/tcp -> 127.0.0.1:11000", "10000/tcp", "127.0.0.1", 11000, true},
		{"18888/tcp -> 0.0.0.0:19888", "18888/tcp", "0.0.0.0", 19888, true},
		{"53/udp -> 0.0.0.0:1053", "53/udp", "0.0.0.0", 1053, true},
		{"10000/tcp -> [::]:11000", "10000/tcp", "[::]", 11000, true},
		{"garbage", "", "", 0, false},
	}
	for _, tt := range tests {
		key, lp, ok := parseDockerPortLine(tt.line)
		if ok != tt.wantOK {
			t.Errorf("%q: ok=%v want %v", tt.line, ok, tt.wantOK)
			continue
		}
		if !ok {
			continue
		}
		if key != tt.wantKey || lp.IP != tt.wantIP || lp.HostPort != tt.wantHP {
			t.Errorf("%q: got (%q,%q,%d) want (%q,%q,%d)",
				tt.line, key, lp.IP, lp.HostPort, tt.wantKey, tt.wantIP, tt.wantHP)
		}
	}
}

func rowFor(rows []exposeRow, containerPort int, kind string) (exposeRow, bool) {
	for _, r := range rows {
		if r.ContainerPort == containerPort && r.Kind == kind {
			return r, true
		}
	}
	return exposeRow{}, false
}

func TestBuildExposeRows_ManifestDrivesAndConfirmsLive(t *testing.T) {
	manifest := &portManifest{
		Booth:   "demo",
		Variant: "notebook",
		Published: []publishedPort{
			{HostIP: "127.0.0.1", HostPort: 11000, ContainerPort: 10000, Proto: "tcp", Source: "booth front door"},
			{HostIP: "0.0.0.0", HostPort: 19888, ContainerPort: 18888, Proto: "tcp", Source: "published (-p)"},
		},
	}
	live := map[string][]livePort{
		// Front door is mapped but nothing bound it — the "declared but down" case.
		"18888/tcp": {{IP: "0.0.0.0", HostPort: 19888}},
	}

	rows := buildExposeRows(manifest, map[int]int{}, live)

	front, ok := rowFor(rows, 10000, "front door")
	if !ok {
		t.Fatal("front door row missing")
	}
	if front.Live {
		t.Errorf("front door has no live binding; should be Live=false: %+v", front)
	}

	nb, ok := rowFor(rows, 18888, "published")
	if !ok || !nb.Live {
		t.Errorf("notebook row should be live: %+v (ok=%v)", nb, ok)
	}
}

func TestBuildExposeRows_NoManifestFallsBackToLive(t *testing.T) {
	live := map[string][]livePort{
		"13000/tcp": {{IP: "0.0.0.0", HostPort: 13000}},
	}
	rows := buildExposeRows(nil, map[int]int{}, live)

	r, ok := rowFor(rows, 13000, "published")
	if !ok || !r.Live || r.Source != "published (-p)" || r.HostPort != 13000 {
		t.Errorf("live fallback row wrong: %+v (ok=%v)", r, ok)
	}
}

func TestBuildExposeRows_CollapsesIPv4IPv6WildcardPair(t *testing.T) {
	live := map[string][]livePort{
		"13000/tcp": {{IP: "0.0.0.0", HostPort: 13000}, {IP: "[::]", HostPort: 13000}},
	}
	rows := buildExposeRows(nil, map[int]int{}, live)

	count := 0
	for _, r := range rows {
		if r.ContainerPort == 13000 {
			count++
			if r.HostIP != "0.0.0.0" {
				t.Errorf("collapsed row should be 0.0.0.0, got %q", r.HostIP)
			}
		}
	}
	if count != 1 {
		t.Errorf("expected 1 row for the wildcard pair, got %d", count)
	}
}

func TestBuildExposeRows_TunnelsAppended(t *testing.T) {
	rows := buildExposeRows(nil, map[int]int{5432: 15432}, map[string][]livePort{})

	r, ok := rowFor(rows, 5432, "tunnel")
	if !ok {
		t.Fatal("tunnel row missing")
	}
	if r.HostIP != "127.0.0.1" || r.HostPort != 15432 || r.Source != "booth--expose" {
		t.Errorf("tunnel row wrong: %+v", r)
	}
}

func TestBuildExposeRows_LivePortNotInManifestStillListed(t *testing.T) {
	manifest := &portManifest{Published: []publishedPort{
		{HostIP: "127.0.0.1", HostPort: 11000, ContainerPort: 10000, Proto: "tcp", Source: "booth front door"},
	}}
	live := map[string][]livePort{
		"10000/tcp": {{IP: "127.0.0.1", HostPort: 11000}},
		"9000/tcp":  {{IP: "0.0.0.0", HostPort: 9000}}, // out-of-band mapping
	}
	rows := buildExposeRows(manifest, map[int]int{}, live)

	r, ok := rowFor(rows, 9000, "published")
	if !ok || r.Source != "docker (live)" {
		t.Errorf("uncovered live mapping should be listed as docker (live): %+v (ok=%v)", r, ok)
	}
}
