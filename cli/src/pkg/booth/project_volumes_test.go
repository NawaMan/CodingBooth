// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bytes"
	"reflect"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func groupsOf(args ...[]string) *ilist.AppendableList[ilist.List[string]] {
	out := ilist.NewAppendableList[ilist.List[string]]()
	for _, a := range args {
		out.Append(ilist.NewListFromSlice(a))
	}
	return out
}

func flatten(args *ilist.AppendableList[ilist.List[string]]) [][]string {
	var out [][]string
	args.ToList().Range(func(_ int, g ilist.List[string]) bool {
		out = append(out, g.Slice())
		return true
	})
	return out
}

func TestExpandProjectVolumeGroups(t *testing.T) {
	in := groupsOf(
		[]string{"-v", "booth-pgdata-{name}:/var/lib/postgresql"},
		[]string{"-v", "shared-cache-{project}:/home/coder/.cache"},
		[]string{"--volume", "~/data/{project}:/data:ro"},
		[]string{"-v", "booth-redisdata:/home/coder/.redis"},
		[]string{"-e", "NAME={name}"},
	)
	out, volumes := expandProjectVolumeGroups(in, "myproj-12000", "myproj")

	want := [][]string{
		{"-v", "booth-pgdata-myproj-12000:/var/lib/postgresql"},
		{"-v", "shared-cache-myproj:/home/coder/.cache"},
		{"--volume", "~/data/myproj:/data:ro"},
		{"-v", "booth-redisdata:/home/coder/.redis"},
		{"-e", "NAME={name}"}, // only volume sources are expanded
	}
	if got := flatten(out); !reflect.DeepEqual(got, want) {
		t.Fatalf("expanded = %v, want %v", got, want)
	}
	// Only named volumes are reported; a bind path has no volume to create.
	wantVolumes := []projectVolume{
		{pattern: "booth-pgdata-{name}", name: "booth-pgdata-myproj-12000", target: "/var/lib/postgresql"},
		{pattern: "shared-cache-{project}", name: "shared-cache-myproj", target: "/home/coder/.cache"},
	}
	if !reflect.DeepEqual(volumes, wantVolumes) {
		t.Fatalf("volumes = %+v, want %+v", volumes, wantVolumes)
	}
	// The input is not modified in place.
	if got := flatten(in)[0][1]; got != "booth-pgdata-{name}:/var/lib/postgresql" {
		t.Fatalf("input mutated: %s", got)
	}
}

// The default booth of a folder is named after it, so {name} gives the same
// volume {project} would: one per project until a second booth appears.
func TestExpandProjectVolumeGroups_DefaultBoothMatchesProject(t *testing.T) {
	out, _ := expandProjectVolumeGroups(groupsOf([]string{"-v", "booth-pgdata-{name}:/var/lib/postgresql"}), "myproj", "myproj")
	if got := flatten(out)[0][1]; got != "booth-pgdata-myproj:/var/lib/postgresql" {
		t.Fatalf("expanded = %s", got)
	}
}

func TestLegacyVolumeName(t *testing.T) {
	cases := map[string]string{
		"booth-pgdata-{name}":        "booth-pgdata",
		"booth-pgdata-{project}":     "booth-pgdata",
		"booth-penpot-assets-{name}": "booth-penpot-assets",
		"{name}-pgdata":              "", // no "-{name}" suffix form: nothing it replaced
		"booth-pgdata":               "",
	}
	for pattern, want := range cases {
		if got := legacyVolumeName(pattern); got != want {
			t.Errorf("legacyVolumeName(%q) = %q, want %q", pattern, got, want)
		}
	}
}

type fakeEngine struct {
	existing map[string]bool
	created  []string
	labels   map[string][]string
}

func (f *fakeEngine) ops() volumeOps {
	return volumeOps{
		exists: func(name string) bool { return f.existing[name] },
		create: func(name string, labels []string) error {
			f.created = append(f.created, name)
			if f.labels == nil {
				f.labels = map[string][]string{}
			}
			f.labels[name] = labels
			f.existing[name] = true
			return nil
		},
	}
}

var pgVolume = projectVolume{pattern: "booth-pgdata-{name}", name: "booth-pgdata-myproj", target: "/var/lib/postgresql"}

func TestEnsureProjectVolumes_NewVolumeWithLegacyData_Notices(t *testing.T) {
	engine := &fakeEngine{existing: map[string]bool{"booth-pgdata": true}}
	var stderr bytes.Buffer

	ensureProjectVolumes([]projectVolume{pgVolume}, "myproj", "myproj", "docker", engine.ops(), &stderr)

	if !reflect.DeepEqual(engine.created, []string{"booth-pgdata-myproj"}) {
		t.Fatalf("created = %v", engine.created)
	}
	if !reflect.DeepEqual(engine.labels["booth-pgdata-myproj"], []string{"cb.project=myproj", "cb.volume=project", "cb.booth=myproj"}) {
		t.Fatalf("labels = %v", engine.labels["booth-pgdata-myproj"])
	}
	msg := stderr.String()
	for _, want := range []string{
		"booth-pgdata-myproj",
		"booth config --add-mount booth-pgdata:/var/lib/postgresql",
		"docker run --rm -v booth-pgdata:/from -v booth-pgdata-myproj:/to",
	} {
		if !strings.Contains(msg, want) {
			t.Errorf("notice missing %q:\n%s", want, msg)
		}
	}

	// Second start: the volume exists now, so no notice and no create.
	stderr.Reset()
	ensureProjectVolumes([]projectVolume{pgVolume}, "myproj", "myproj", "docker", engine.ops(), &stderr)
	if stderr.Len() != 0 || len(engine.created) != 1 {
		t.Fatalf("second start: notice %q, created %v", stderr.String(), engine.created)
	}
}

func TestEnsureProjectVolumes_NoLegacyData_Quiet(t *testing.T) {
	engine := &fakeEngine{existing: map[string]bool{}}
	var stderr bytes.Buffer
	ensureProjectVolumes([]projectVolume{pgVolume}, "myproj", "myproj", "docker", engine.ops(), &stderr)
	if stderr.Len() != 0 {
		t.Fatalf("unexpected notice: %s", stderr.String())
	}
	if len(engine.created) != 1 {
		t.Fatalf("created = %v", engine.created)
	}
}

// A second booth of the folder starts with an empty volume of its own; when the
// default booth already has data, say where it is and how to copy it — never
// suggest mounting it, which would put two servers on one data folder.
func TestEnsureProjectVolumes_SecondBooth_PointsAtDefaultBoothData(t *testing.T) {
	engine := &fakeEngine{existing: map[string]bool{"booth-pgdata-myproj": true, "booth-pgdata": true}}
	var stderr bytes.Buffer
	second := projectVolume{pattern: "booth-pgdata-{name}", name: "booth-pgdata-myproj-12000", target: "/var/lib/postgresql"}

	ensureProjectVolumes([]projectVolume{second}, "myproj-12000", "myproj", "docker", engine.ops(), &stderr)

	if !reflect.DeepEqual(engine.created, []string{"booth-pgdata-myproj-12000"}) {
		t.Fatalf("created = %v", engine.created)
	}
	if !reflect.DeepEqual(engine.labels["booth-pgdata-myproj-12000"], []string{"cb.project=myproj", "cb.volume=project", "cb.booth=myproj-12000"}) {
		t.Fatalf("labels = %v", engine.labels["booth-pgdata-myproj-12000"])
	}
	msg := stderr.String()
	if !strings.Contains(msg, "docker run --rm -v booth-pgdata-myproj:/from -v booth-pgdata-myproj-12000:/to") {
		t.Errorf("notice missing the copy command:\n%s", msg)
	}
	if strings.Contains(msg, "--add-mount") || strings.Contains(msg, "booth-pgdata:") {
		t.Errorf("notice must not point at the legacy volume or suggest sharing a mount:\n%s", msg)
	}
}

// A {project} volume is shared by every booth of the folder: no booth label,
// and no per-booth notice for a second booth.
func TestEnsureProjectVolumes_ProjectVolume_NoBoothLabel(t *testing.T) {
	engine := &fakeEngine{existing: map[string]bool{}}
	var stderr bytes.Buffer
	shared := projectVolume{pattern: "shared-cache-{project}", name: "shared-cache-myproj", target: "/home/coder/.cache"}

	ensureProjectVolumes([]projectVolume{shared}, "myproj-12000", "myproj", "docker", engine.ops(), &stderr)

	if !reflect.DeepEqual(engine.labels["shared-cache-myproj"], []string{"cb.project=myproj", "cb.volume=project"}) {
		t.Fatalf("labels = %v", engine.labels["shared-cache-myproj"])
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected notice: %s", stderr.String())
	}
}

func TestCollectCacheVolumes(t *testing.T) {
	in := groupsOf(
		[]string{"-v", "booth-cache-gomod:/home/coder/go/pkg/mod", "-e", "GOMODCACHE=/home/coder/go/pkg/mod"},
		[]string{"-v", "booth-cache-gomod:/home/coder/go/pkg/mod"},
		[]string{"-v", "booth-pgdata-{project}:/var/lib/postgresql"},
		[]string{"-v", "$HOME/.m2:/home/coder/.m2"},
		[]string{"-v", "booth-cache-npm:/home/coder/.npm"},
	)
	got := collectCacheVolumes(in)
	want := []cacheVolume{
		{name: "booth-cache-gomod", target: "/home/coder/go/pkg/mod"},
		{name: "booth-cache-npm", target: "/home/coder/.npm"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("volumes = %+v, want %+v", got, want)
	}
}

func TestEnsureCacheVolumes_LabelsAndSkipsExisting(t *testing.T) {
	engine := &fakeEngine{existing: map[string]bool{"booth-cache-npm": true}}
	ensureCacheVolumes([]cacheVolume{
		{name: "booth-cache-gomod", target: "/home/coder/go/pkg/mod"},
		{name: "booth-cache-gomod", target: "/home/coder/go/pkg/mod"},
		{name: "booth-cache-npm", target: "/home/coder/.npm"},
	}, engine.ops())
	if !reflect.DeepEqual(engine.created, []string{"booth-cache-gomod"}) {
		t.Fatalf("created = %v", engine.created)
	}
	if !reflect.DeepEqual(engine.labels["booth-cache-gomod"], []string{"cb.volume=cache"}) {
		t.Fatalf("labels = %v", engine.labels["booth-cache-gomod"])
	}
}
