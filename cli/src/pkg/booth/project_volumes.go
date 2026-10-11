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

// Placeholders in the source of a run-args -v spec, replaced at run time so a
// template can name a volume after its booth instead of one name every booth on
// the machine shares. They are expanded here rather than when booth config writes
// the file, so the same committed config.toml follows the folder and the booth:
//
//   - {name}    -> the booth's final container name. The service templates use it
//     ("booth-pgdata-{name}"): a booth's default name is its folder name, so the
//     usual single booth of a project keeps one volume per project, while a second
//     booth of the same folder (--name, or the automatic <project>-<port> name)
//     gets its own and never shares a database folder with the first.
//   - {project} -> the project (folder) name, for a volume every booth of the
//     folder should share.
const (
	namePlaceholder    = "{name}"
	projectPlaceholder = "{project}"
)

// cacheVolumePrefix marks a machine-wide package-download volume
// ("booth-cache-gomod"). There is no {name} or {project}: every booth on this
// machine reuses the same downloads. The name is how the CLI knows to label it
// cb.volume=cache, so `docker volume ls --filter label=cb.volume=cache` lists
// the caches and `docker volume rm` resets one.
const cacheVolumePrefix = "booth-cache-"

// projectVolume is one named volume whose name came from a {name} or {project} pattern.
type projectVolume struct {
	pattern string // as written, e.g. booth-pgdata-{name}
	name    string // expanded, e.g. booth-pgdata-myproj
	target  string // container path
}

// perBooth reports whether the volume is named after its booth ({name}), not
// only after its project.
func (v projectVolume) perBooth() bool {
	return strings.Contains(v.pattern, namePlaceholder)
}

// scope names what the volume is per, for messages: "booth" or "project".
func (v projectVolume) scope() string {
	if v.perBooth() {
		return "booth"
	}
	return "project"
}

// expandProjectVolumeGroups replaces {name} and {project} in -v/--volume sources
// and reports the named volumes it produced (bind-mount paths are expanded but not
// reported: there is no volume to create).
func expandProjectVolumeGroups(args *ilist.AppendableList[ilist.List[string]], booth, project string) (*ilist.AppendableList[ilist.List[string]], []projectVolume) {
	out := ilist.NewAppendableList[ilist.List[string]]()
	if args == nil {
		return out, nil
	}
	replacer := strings.NewReplacer(namePlaceholder, booth, projectPlaceholder, project)
	var volumes []projectVolume
	args.ToList().Range(func(_ int, group ilist.List[string]) bool {
		items := append([]string(nil), group.Slice()...)
		for i := 0; i+1 < len(items); i++ {
			if !isVolumeFlag(items[i]) {
				continue
			}
			spec := items[i+1]
			source := volumeSource(spec)
			if !strings.Contains(source, namePlaceholder) && !strings.Contains(source, projectPlaceholder) {
				i++
				continue
			}
			expanded := replacer.Replace(source)
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

// legacyVolumeName is the machine-wide name a {name} or {project} pattern
// replaced: booth-pgdata-{name} -> booth-pgdata. Empty when the pattern has no
// such form.
func legacyVolumeName(pattern string) string {
	legacy := strings.ReplaceAll(pattern, "-"+namePlaceholder, "")
	legacy = strings.ReplaceAll(legacy, "-"+projectPlaceholder, "")
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

// ensureProjectVolumes creates each named volume that does not exist yet,
// labelled with its project (and booth, for a {name} volume) so it can be found
// and cleaned up later. A new volume starts empty; when older data sits next to
// it, say so once, at the moment the new volume is made:
//   - a booth not named after its folder, while the folder's default booth has
//     data: how to start from a copy of it;
//   - otherwise, the machine-wide volume from before: the two ways to keep it.
func ensureProjectVolumes(volumes []projectVolume, booth, project, engine string, ops volumeOps, stderr io.Writer) {
	for _, v := range volumes {
		if ops.exists(v.name) {
			continue
		}
		sibling := strings.NewReplacer(namePlaceholder, project, projectPlaceholder, project).Replace(v.pattern)
		if v.perBooth() && booth != project && ops.exists(sibling) {
			fmt.Fprintf(stderr,
				"Notice: booth %s has its own %s, which is new and empty;\n"+
					"        the data of booth %s (this folder's default) is in %s.\n"+
					"        To start from a copy, stop booth %s, then:\n"+
					"            %s run --rm -v %s:/from -v %s:/to alpine cp -a /from/. /to/\n",
				booth, v.name, project, sibling, project, engine, sibling, v.name)
		} else if legacy := legacyVolumeName(v.pattern); legacy != "" && ops.exists(legacy) {
			fmt.Fprintf(stderr,
				"Notice: %s is now one volume per %s. This booth uses %s, which is new and empty;\n"+
					"        data from before is still in %s (shared by every project on this machine).\n"+
					"        To keep using it:  booth config --add-mount %s:%s\n"+
					"        To copy it over:   %s run --rm -v %s:/from -v %s:/to alpine cp -a /from/. /to/\n",
				legacy, v.scope(), v.name, legacy, legacy, v.target, engine, legacy, v.name)
		}
		labels := []string{"cb.project=" + project, "cb.volume=project"}
		if v.perBooth() {
			labels = append(labels, "cb.booth="+booth)
		}
		_ = ops.create(v.name, labels)
	}
}

// cacheVolume is one machine-wide named volume (booth-cache-*).
type cacheVolume struct {
	name   string
	target string
}

// collectCacheVolumes reports booth-cache-* named volumes in -v/--volume specs.
// Bind mounts and per-project volumes are ignored: a cache name has no path
// separator and no {project}. The same name listed twice is reported once.
func collectCacheVolumes(args *ilist.AppendableList[ilist.List[string]]) []cacheVolume {
	if args == nil {
		return nil
	}
	var volumes []cacheVolume
	seen := map[string]bool{}
	args.ToList().Range(func(_ int, group ilist.List[string]) bool {
		items := group.Slice()
		for i := 0; i+1 < len(items); i++ {
			if !isVolumeFlag(items[i]) {
				continue
			}
			spec := items[i+1]
			i++
			source := volumeSource(spec)
			if isBindMountSource(source) || !strings.HasPrefix(source, cacheVolumePrefix) {
				continue
			}
			if seen[source] {
				continue
			}
			seen[source] = true
			volumes = append(volumes, cacheVolume{name: source, target: volumeTarget(spec)})
		}
		return true
	})
	return volumes
}

// ensureCacheVolumes creates each machine-wide cache volume that does not exist
// yet, labelled cb.volume=cache. It does not set cb.managed or cb.project:
// home-volume-list and prune key off cb.managed, and a cache is not one project's
// data. docker volume create is idempotent; the exists check keeps a second
// start quiet.
func ensureCacheVolumes(volumes []cacheVolume, ops volumeOps) {
	seen := map[string]bool{}
	for _, v := range volumes {
		if seen[v.name] || ops.exists(v.name) {
			seen[v.name] = true
			continue
		}
		seen[v.name] = true
		_ = ops.create(v.name, []string{"cb.volume=cache"})
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
