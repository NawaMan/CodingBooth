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
		[]string{"-v", "booth-pgdata-{project}:/var/lib/postgresql"},
		[]string{"--volume", "~/data/{project}:/data:ro"},
		[]string{"-v", "booth-redisdata:/home/coder/.redis"},
		[]string{"-e", "NAME={project}"},
	)
	out, volumes := expandProjectVolumeGroups(in, "myproj")

	want := [][]string{
		{"-v", "booth-pgdata-myproj:/var/lib/postgresql"},
		{"--volume", "~/data/myproj:/data:ro"},
		{"-v", "booth-redisdata:/home/coder/.redis"},
		{"-e", "NAME={project}"}, // only volume sources are expanded
	}
	if got := flatten(out); !reflect.DeepEqual(got, want) {
		t.Fatalf("expanded = %v, want %v", got, want)
	}
	// Only the named volume is reported; a bind path has no volume to create.
	wantVolumes := []projectVolume{{pattern: "booth-pgdata-{project}", name: "booth-pgdata-myproj", target: "/var/lib/postgresql"}}
	if !reflect.DeepEqual(volumes, wantVolumes) {
		t.Fatalf("volumes = %+v, want %+v", volumes, wantVolumes)
	}
	// The input is not modified in place.
	if got := flatten(in)[0][1]; got != "booth-pgdata-{project}:/var/lib/postgresql" {
		t.Fatalf("input mutated: %s", got)
	}
}

func TestLegacyVolumeName(t *testing.T) {
	cases := map[string]string{
		"booth-pgdata-{project}":        "booth-pgdata",
		"booth-penpot-assets-{project}": "booth-penpot-assets",
		"{project}-pgdata":              "", // no "-{project}" suffix form: nothing it replaced
		"booth-pgdata":                  "",
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

var pgVolume = projectVolume{pattern: "booth-pgdata-{project}", name: "booth-pgdata-myproj", target: "/var/lib/postgresql"}

func TestEnsureProjectVolumes_NewVolumeWithLegacyData_Notices(t *testing.T) {
	engine := &fakeEngine{existing: map[string]bool{"booth-pgdata": true}}
	var stderr bytes.Buffer

	ensureProjectVolumes([]projectVolume{pgVolume}, "myproj", "docker", engine.ops(), &stderr)

	if !reflect.DeepEqual(engine.created, []string{"booth-pgdata-myproj"}) {
		t.Fatalf("created = %v", engine.created)
	}
	if !reflect.DeepEqual(engine.labels["booth-pgdata-myproj"], []string{"cb.project=myproj", "cb.volume=project"}) {
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
	ensureProjectVolumes([]projectVolume{pgVolume}, "myproj", "docker", engine.ops(), &stderr)
	if stderr.Len() != 0 || len(engine.created) != 1 {
		t.Fatalf("second start: notice %q, created %v", stderr.String(), engine.created)
	}
}

func TestEnsureProjectVolumes_NoLegacyData_Quiet(t *testing.T) {
	engine := &fakeEngine{existing: map[string]bool{}}
	var stderr bytes.Buffer
	ensureProjectVolumes([]projectVolume{pgVolume}, "myproj", "docker", engine.ops(), &stderr)
	if stderr.Len() != 0 {
		t.Fatalf("unexpected notice: %s", stderr.String())
	}
	if len(engine.created) != 1 {
		t.Fatalf("created = %v", engine.created)
	}
}
