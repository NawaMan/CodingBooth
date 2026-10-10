// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"io"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// projectPlaceholder in the source of a run-args -v spec is replaced with the
// project name at run time, so a template can give each project its own named
// volume ("booth-pgdata-{project}") instead of one volume every project on the
// machine shares. It is expanded here rather than when booth config writes the
// file, so the same committed config.toml follows the folder: each clone and each
// worktree gets its own data.
const projectPlaceholder = "{project}"

// projectVolume is one named volume whose name came from a {project} pattern.
type projectVolume struct {
	pattern string // as written, e.g. booth-pgdata-{project}
	name    string // expanded, e.g. booth-pgdata-myproj
	target  string // container path
}

// expandProjectVolumeGroups replaces {project} in -v/--volume sources and reports
// the named volumes it produced (bind-mount paths are expanded but not reported:
// there is no volume to create).
func expandProjectVolumeGroups(args *ilist.AppendableList[ilist.List[string]], project string) (*ilist.AppendableList[ilist.List[string]], []projectVolume) {
	out := ilist.NewAppendableList[ilist.List[string]]()
	if args == nil {
		return out, nil
	}
	var volumes []projectVolume
	args.ToList().Range(func(_ int, group ilist.List[string]) bool {
		items := append([]string(nil), group.Slice()...)
		for i := 0; i+1 < len(items); i++ {
			if !isVolumeFlag(items[i]) {
				continue
			}
			spec := items[i+1]
			source := volumeSource(spec)
			if !strings.Contains(source, projectPlaceholder) {
				i++
				continue
			}
			expanded := strings.ReplaceAll(source, projectPlaceholder, project)
			items[i+1] = expanded + spec[len(source):]
			if !isBindMountSource(expanded) {
				volumes = append(volumes, projectVolume{pattern: source, name: expanded, target: volumeTarget(spec)})
			}
			i++
		}
		out.Append(ilist.NewListFromSlice(items))
		return true
	})
	return out, volumes
}

// legacyVolumeName is the machine-wide name a {project} pattern replaced:
// booth-pgdata-{project} -> booth-pgdata. Empty when the pattern has no such form.
func legacyVolumeName(pattern string) string {
	legacy := strings.ReplaceAll(pattern, "-"+projectPlaceholder, "")
	if legacy == pattern || strings.Contains(legacy, "{") || legacy == "" {
		return ""
	}
	return legacy
}

// volumeOps is the engine access ensureProjectVolumes needs, injectable for tests.
type volumeOps struct {
	exists func(name string) bool
	create func(name string, labels []string) error
}

// ensureProjectVolumes creates each per-project volume that does not exist yet,
// labelled with its project so it can be found and cleaned up later. When the
// machine-wide volume it replaces still exists, the new one starts empty while the
// old data sits next to it — say so once, at the moment the new volume is made,
// with the two ways to keep the old data.
func ensureProjectVolumes(volumes []projectVolume, project, engine string, ops volumeOps, stderr io.Writer) {
	for _, v := range volumes {
		if ops.exists(v.name) {
			continue
		}
		if legacy := legacyVolumeName(v.pattern); legacy != "" && ops.exists(legacy) {
			fmt.Fprintf(stderr,
				"Notice: %s is now one volume per project. This booth uses %s, which is new and empty;\n"+
					"        data from before is still in %s (shared by every project on this machine).\n"+
					"        To keep using it:  booth config --add-mount %s:%s\n"+
					"        To copy it over:   %s run --rm -v %s:/from -v %s:/to alpine cp -a /from/. /to/\n",
				legacy, v.name, legacy, legacy, v.target, engine, legacy, v.name)
		}
		_ = ops.create(v.name, []string{"cb.project=" + project, "cb.volume=project"})
	}
}

// engineVolumeOps talks to the booth's container engine.
func engineVolumeOps(ctx appctx.AppContext) volumeOps {
	flags := docker.DockerFlags{Silent: true, Engine: ctx.Engine()}
	return volumeOps{
		exists: func(name string) bool {
			_, err := docker.DockerOutput(flags, "volume", ilist.NewList(ilist.NewList("inspect", name)))
			return err == nil
		},
		create: func(name string, labels []string) error {
			args := ilist.NewAppendableList[ilist.List[string]]()
			args.Append(ilist.NewList("create"))
			for _, l := range labels {
				args.Append(ilist.NewList("--label", l))
			}
			args.Append(ilist.NewList(name))
			return docker.Docker(flags, "volume", args.ToList())
		},
	}
}
