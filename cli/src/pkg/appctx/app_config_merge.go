// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"github.com/BurntSushi/toml"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// MergeProfileToml loads a profile config.toml on top of an existing
// AppConfig. Semantics:
//
//   - Scalar fields present in the profile overwrite the accumulator.
//     Scalars absent from the profile are left unchanged (this is the
//     BurntSushi/toml decoder's default behavior).
//
//   - List-of-flags fields — CommonArgs, BuildArgs, RunArgs — are
//     concat-and-dedup merged with the accumulator's current values
//     when the profile defines them. Dedup is paired-flag aware so
//     "-v a:a" and "-v b:b" both survive while "-v a:a -v a:a"
//     collapses. Arrays absent from the profile leave the accumulator
//     unchanged.
//
//   - Cmds is treated like a scalar: when present in the profile it
//     REPLACES the accumulator's cmds entirely (later wins). This
//     mirrors the existing CLI rule at parseArgs(): the "--" terminator
//     replaces existing cmds rather than appending. Cmds represents one
//     logical command expressed as argv tokens, so concatenating two
//     commands has no useful meaning.
//
// Use this for profile overlays. For the base TOML load (no merging
// concerns), use ReadFromToml.
func MergeProfileToml(path string, config *AppConfig) error {
	snapCommonArgs := config.CommonArgs.Clone()
	snapBuildArgs := config.BuildArgs.Clone()
	snapRunArgs := config.RunArgs.Clone()

	md, err := toml.DecodeFile(path, config)
	if err != nil {
		return err
	}

	if md.IsDefined("common-args") {
		config.CommonArgs = mergeSemicolonList(snapCommonArgs, config.CommonArgs)
	}
	if md.IsDefined("build-args") {
		config.BuildArgs = mergeSemicolonList(snapBuildArgs, config.BuildArgs)
	}
	if md.IsDefined("run-args") {
		config.RunArgs = mergeSemicolonList(snapRunArgs, config.RunArgs)
	}
	// Cmds intentionally not merged — TOML decode already replaced it
	// when the profile defined cmds, which is what we want.

	return nil
}

func mergeSemicolonList(prev, next ilist.SemicolonStringList) ilist.SemicolonStringList {
	combined := append([]string(nil), prev.Slice()...)
	combined = append(combined, next.Slice()...)
	return ilist.SemicolonStringList{List: ilist.NewListFromSlice(dedupDockerArgs(combined))}
}

// dedupDockerArgs removes duplicate flag/value pairs from a docker-style
// arg slice, preserving order. Mirrors the dedup logic in
// cli/src/pkg/boothinit/compiler/compiler.go so profile merges and
// template merges share semantics.
func dedupDockerArgs(items []string) []string {
	if len(items) == 0 {
		return nil
	}
	pairedFlags := map[string]bool{
		"-v": true, "-e": true, "-p": true, "-l": true,
		"--volume": true, "--env": true, "--publish": true,
	}
	seen := make(map[string]bool, len(items))
	result := make([]string, 0, len(items))
	for i := 0; i < len(items); i++ {
		if pairedFlags[items[i]] && i+1 < len(items) {
			pair := items[i] + "\x00" + items[i+1]
			if !seen[pair] {
				seen[pair] = true
				result = append(result, items[i], items[i+1])
			}
			i++ // skip value
		} else {
			if !seen[items[i]] {
				seen[items[i]] = true
				result = append(result, items[i])
			}
		}
	}
	return result
}
