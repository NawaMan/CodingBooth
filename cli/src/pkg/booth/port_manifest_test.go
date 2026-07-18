// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

// manifestBuilder returns a builder with the fields buildPortManifest reads,
// with the given already-resolved run-args publishes.
func manifestBuilder(publishes ...string) *appctx.AppContextBuilder {
	runArgs := ilist.NewAppendableList[ilist.List[string]]()
	for _, p := range publishes {
		runArgs.Append(ilist.NewList("-p", p))
	}
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    runArgs,
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Name = "demo"
	builder.Config.ProjectName = "demo"
	builder.Config.Variant = "notebook"
	builder.Config.Code = nillable.NewNillableString(".")
	builder.PortNumber = 11000
	return builder
}

func findPublished(m PortManifest, containerPort int) (PublishedPort, bool) {
	for _, p := range m.Published {
		if p.ContainerPort == containerPort {
			return p, true
		}
	}
	return PublishedPort{}, false
}

func TestBuildPortManifest_FrontDoorAndPublishes(t *testing.T) {
	// Front door is loopback (non-public), plus a --expose app and a notebook
	// mapping whose +OFFSET was already resolved (11000+8888) upstream.
	ctx := manifestBuilder("13000:13000", "19888:18888").Build()

	m := buildPortManifest(ctx)

	if m.Booth != "demo" || m.Variant != "notebook" {
		t.Fatalf("unexpected identity: %+v", m)
	}

	front, ok := findPublished(m, 10000)
	if !ok {
		t.Fatal("front door (container 10000) missing")
	}
	if front.HostPort != 11000 || front.HostIP != "127.0.0.1" || front.Source != "booth front door" {
		t.Errorf("front door wrong: %+v", front)
	}

	app, ok := findPublished(m, 13000)
	if !ok || app.HostPort != 13000 || app.Source != "published (-p)" {
		t.Errorf("expose app wrong: %+v (ok=%v)", app, ok)
	}

	nb, ok := findPublished(m, 18888)
	if !ok || nb.HostPort != 19888 {
		t.Errorf("notebook mapping wrong: %+v (ok=%v)", nb, ok)
	}

	// Front door must be listed first.
	if len(m.Published) == 0 || m.Published[0].ContainerPort != 10000 {
		t.Errorf("front door should be first, got %+v", m.Published)
	}
}

func TestBuildPortManifest_PublicFrontDoorIs10443(t *testing.T) {
	b := manifestBuilder()
	b.Config.Public = true
	m := buildPortManifest(b.Build())

	front, ok := findPublished(m, 10443)
	if !ok {
		t.Fatalf("public front door (container 10443) missing: %+v", m.Published)
	}
	if front.HostIP != "" { // public binds every interface
		t.Errorf("public front door should not pin an IP, got %q", front.HostIP)
	}
}

func TestBuildPortManifest_DindOwnsPortNoFrontDoor(t *testing.T) {
	b := manifestBuilder()
	b.Config.Dind = true
	m := buildPortManifest(b.Build())

	if _, ok := findPublished(m, 10000); ok {
		t.Errorf("dind booth should not list a front door: %+v", m.Published)
	}
}

func TestBuildPortManifest_UnresolvedOffsetIsSkipped(t *testing.T) {
	// A +OFFSET that reached here unresolved is Relative and must not masquerade
	// as a concrete port.
	ctx := manifestBuilder("+300:1234").Build()
	m := buildPortManifest(ctx)

	if _, ok := findPublished(m, 1234); ok {
		t.Errorf("unresolved +OFFSET should be skipped: %+v", m.Published)
	}
}

func TestWritePortManifest_WritesFileWhenTmpExists(t *testing.T) {
	code := t.TempDir()
	if err := os.MkdirAll(filepath.Join(code, ".booth", ".tmp"), 0755); err != nil {
		t.Fatal(err)
	}

	b := manifestBuilder("13000:13000")
	b.Config.Code = nillable.NewNillableString(code)
	WritePortManifest(b.Build())

	data, err := os.ReadFile(filepath.Join(code, ".booth", ".tmp", PortManifestFile))
	if err != nil {
		t.Fatalf("manifest not written: %v", err)
	}
	var m PortManifest
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("manifest is not valid JSON: %v", err)
	}
	if m.Booth != "demo" {
		t.Errorf("unexpected booth: %q", m.Booth)
	}
	if _, ok := findPublished(m, 13000); !ok {
		t.Errorf("published port missing from written manifest: %+v", m.Published)
	}
}

func TestWritePortManifest_NoTmpDirIsNoOp(t *testing.T) {
	code := t.TempDir() // no .booth/.tmp created
	b := manifestBuilder()
	b.Config.Code = nillable.NewNillableString(code)
	WritePortManifest(b.Build())

	if _, err := os.Stat(filepath.Join(code, ".booth", ".tmp", PortManifestFile)); !os.IsNotExist(err) {
		t.Errorf("manifest should not be written without .booth/.tmp/, err=%v", err)
	}
}

func TestBuildPortManifest_UdpProtoPreserved(t *testing.T) {
	ctx := manifestBuilder("15000:5000/udp").Build()
	m := buildPortManifest(ctx)

	p, ok := findPublished(m, 5000)
	if !ok || p.Proto != "udp" {
		t.Errorf("udp proto not preserved: %+v (ok=%v)", p, ok)
	}
}
