// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// argvListKeys are list keys whose items are argv tokens — docker flags, a
// command and its arguments — rather than values. A comma is ordinary text in a
// token (`--mount type=bind,src=…`, `${X:-a,b}`), so these never split on one:
// each --set carries exactly one token, as before.
var argvListKeys = map[string]bool{
	"common-args": true,
	"build-args":  true,
	"run-args":    true,
	"cmds":        true,
}

// setKey returns the key of a raw --set entry ("key" or "key=value").
func setKey(set string) string {
	key, _, _ := strings.Cut(set, "=")
	return key
}

// splitsOnComma reports whether a --set value for key is a comma-separated list:
// a list key holding values (egress-allowlist, cache-*, shared-*), not tokens.
func splitsOnComma(key string) bool {
	spec, known := appctx.ConfigKeys()[key]
	return known && spec.Kind == appctx.KeyList && !argvListKeys[key]
}

// splitListValue splits a value-list --set value on commas, trimming each item
// and dropping empty ones. A key that does not split returns the value as is.
func splitListValue(key, value string) []string {
	if !splitsOnComma(key) || !strings.Contains(value, ",") {
		return []string{value}
	}
	var items []string
	for _, item := range strings.Split(value, ",") {
		if item = strings.TrimSpace(item); item != "" {
			items = append(items, item)
		}
	}
	return items
}

// expandSet normalises one raw --set entry into one entry per list item, so
// `--set egress-allowlist=a.com,b.com` is recorded in the header exactly as
// `--set egress-allowlist=a.com --set egress-allowlist=b.com` would be — and a
// regenerate from that header reads it back the same way.
func expandSet(set string) ([]string, error) {
	key, value, hasValue := strings.Cut(set, "=")
	if !hasValue {
		return []string{set}, nil
	}
	items := splitListValue(key, value)
	if len(items) == 0 {
		return nil, fmt.Errorf("--set %s: no values between the commas (use --unset %s to clear it)", set, key)
	}
	out := make([]string, len(items))
	for i, item := range items {
		out[i] = key + "=" + item
	}
	return out, nil
}

// mergeSets applies this run's --set entries onto the baseline's, key by key. A
// key given now replaces every baseline entry for it — a list key included, so
// `--set egress-allowlist=b.com` leaves just b.com — and takes the place of the
// first one, keeping the header's order stable. Keys not given now are kept.
//
// This used to replace the baseline wholesale whenever any --set was given, so
// one `--set` silently dropped every other setting recorded in the header.
func mergeSets(existing, cli []string) []string {
	if len(cli) == 0 {
		return existing
	}
	given := make(map[string][]string)
	var order []string
	for _, set := range cli {
		key := setKey(set)
		if _, seen := given[key]; !seen {
			order = append(order, key)
		}
		given[key] = append(given[key], set)
	}

	var out []string
	emitted := make(map[string]bool)
	for _, set := range existing {
		key := setKey(set)
		values, replaced := given[key]
		if !replaced {
			out = append(out, set)
			continue
		}
		if !emitted[key] {
			out = append(out, values...)
			emitted[key] = true
		}
	}
	for _, key := range order {
		if !emitted[key] {
			out = append(out, given[key]...)
		}
	}
	return out
}

// readBackLists returns the initFlags fields that hold a list key read back out of
// config.toml rather than from the header (see extractUserRunArgs).
func readBackLists(flags *initFlags) map[string]*[]string {
	return map[string]*[]string{
		"cache-files":  &flags.cacheFiles,
		"cache-dirs":   &flags.cacheDirs,
		"shared-files": &flags.sharedFiles,
		"shared-dirs":  &flags.sharedDirs,
	}
}

// dropReadBackForSets clears the read-back values of every list key this run sets,
// so the --set replaces them instead of being appended next to them. Paths a
// selected template declares come back from the template when it compiles.
func dropReadBackForSets(merged *initFlags, cli []string) {
	lists := readBackLists(merged)
	for _, set := range cli {
		if list, ok := lists[setKey(set)]; ok {
			*list = nil
		}
	}
}

// validateUnsets checks --unset keys up front, like --set keys: a key booth does not
// read is refused (with a suggestion), and so is unsetting a key this same run sets.
func validateUnsets(flags initFlags) error {
	schema := appctx.ConfigKeys()
	for _, key := range flags.unsets {
		if _, known := schema[key]; !known {
			msg := fmt.Sprintf("unknown --unset key %q: booth does not read that from config.toml", key)
			if suggestion := appctx.SuggestConfigKey(key); suggestion != "" {
				msg += fmt.Sprintf("\n       Did you mean %q?", suggestion)
			}
			return fmt.Errorf("%s", msg)
		}
		for _, set := range flags.sets {
			if setKey(set) == key {
				return fmt.Errorf("--set %s and --unset %s cannot be combined in the same run", key, key)
			}
		}
		dedicated := map[string]bool{
			"variant": flags.variant != "",
			"port":    flags.port != "",
			"cmds":    len(flags.cmds) > 0,
		}
		if dedicated[key] {
			flag := "--" + key
			if key == "cmds" {
				flag = "--cmd"
			}
			return fmt.Errorf("%s and --unset %s cannot be combined in the same run", flag, key)
		}
	}
	return nil
}

// applyUnsets removes each --unset key from the merged flags: its --set entries,
// the dedicated field that carries it (variant, port, cmds), and any values read
// back from config.toml. A key the booth does not hold is an error, like a
// --remove-* that matches nothing.
func applyUnsets(merged *initFlags, unsets []string) error {
	lists := readBackLists(merged)
	var unmatched []string
	for _, key := range unsets {
		matched := false

		kept := merged.sets[:0:0]
		for _, set := range merged.sets {
			if setKey(set) == key {
				matched = true
				continue
			}
			kept = append(kept, set)
		}
		merged.sets = kept

		switch key {
		case "variant":
			matched = matched || merged.variant != ""
			merged.variant = ""
		case "port":
			matched = matched || merged.port != ""
			merged.port = ""
		case "cmds":
			matched = matched || len(merged.cmds) > 0
			merged.cmds = nil
		}
		if list, ok := lists[key]; ok {
			matched = matched || len(*list) > 0
			*list = nil
		}

		if !matched {
			unmatched = append(unmatched, key)
		}
	}
	if len(unmatched) > 0 {
		return fmt.Errorf("--unset %s: the existing booth does not set it", strings.Join(unmatched, ", "))
	}
	return nil
}

// removeByKey drops every entry of base that one of removes names — by its key
// (the env KEY, the container port, the container path) or by the whole entry, so
// `--remove-env FOO=1` drops FOO=1 the same way `--add-env FOO=1` added it. A
// removal that matches nothing is an error: it is almost always a typo or a stale
// value, and carrying on would write a booth that still holds what the user meant
// to drop. When the key exists with a different value, the error says so.
func removeByKey(base, removes []string, keyFn func(string) string, flagName string) ([]string, error) {
	matched := make(map[string]bool, len(removes))
	var result []string
	for _, b := range base {
		dropped := false
		for _, r := range removes {
			if b == r || keyFn(b) == r {
				dropped = true
				matched[r] = true
			}
		}
		if !dropped {
			result = append(result, b)
		}
	}

	var problems []string
	for _, r := range removes {
		if matched[r] {
			continue
		}
		problem := fmt.Sprintf("--remove-%s %q did not match anything in the existing booth", flagName, r)
		for _, b := range base {
			if keyFn(b) == keyFn(r) {
				problem += fmt.Sprintf(" (it has %q)", b)
				break
			}
		}
		problems = append(problems, problem)
	}
	if len(problems) > 0 {
		return nil, fmt.Errorf("%s", strings.Join(problems, "\n       "))
	}
	return result, nil
}
