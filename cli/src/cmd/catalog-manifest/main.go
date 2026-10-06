// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// catalog-manifest generates and checks the catalog manifest
// (build/catalog-manifest.tsv). Run it through build/gen-catalog-manifest.sh and
// build/check-catalog-versions.sh. See docs/CATALOG_VERSIONING.md.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/catalog"
)

func usage() {
	fmt.Fprint(os.Stderr, `Usage:
  catalog-manifest generate [--root DIR] [--check]
      Write build/catalog-manifest.tsv. --check writes nothing and exits 1 when
      the committed manifest is stale or an item has no valid cb-version.

  catalog-manifest check [--root DIR] [--baseline REF] [--report]
      Compare the catalog against the manifest at the previous release tag
      (or REF). Exits 1 on a failure unless --report is given.
`)
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	code := 0
	switch os.Args[1] {
	case "generate":
		code, err = runGenerate(os.Args[2:])
	case "check":
		code, err = runCheck(os.Args[2:])
	case "-h", "--help", "help":
		usage()
	default:
		usage()
		code = 2
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "❌", err)
		code = 1
	}
	os.Exit(code)
}

func runGenerate(args []string) (int, error) {
	fs := flag.NewFlagSet("generate", flag.ExitOnError)
	root := fs.String("root", ".", "repository root")
	check := fs.Bool("check", false, "verify instead of writing")
	fs.Parse(args)

	items, err := catalog.Collect(*root)
	if err != nil {
		return 1, err
	}
	invalid := catalog.Check(nil, items, nil, nil)
	text := catalog.Format(items)
	path := filepath.Join(*root, catalog.ManifestPath)

	if *check {
		code := 0
		for _, f := range invalid {
			fmt.Println(f)
			code = 1
		}
		old, _ := os.ReadFile(path)
		if string(old) != text {
			fmt.Printf("FAIL  %s is stale — run build/gen-catalog-manifest.sh\n", catalog.ManifestPath)
			code = 1
		}
		if code == 0 {
			fmt.Printf("✅ %s is current (%d items)\n", catalog.ManifestPath, len(items))
		}
		return code, nil
	}

	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		return 1, err
	}
	fmt.Printf("✅ Wrote %s (%d items)\n", catalog.ManifestPath, len(items))
	for _, f := range invalid {
		fmt.Println(f)
	}
	if len(invalid) > 0 {
		return 1, nil
	}
	return 0, nil
}

func runCheck(args []string) (int, error) {
	fs := flag.NewFlagSet("check", flag.ExitOnError)
	root := fs.String("root", ".", "repository root")
	baseline := fs.String("baseline", "", "git ref of the baseline (default: previous release tag)")
	report := fs.Bool("report", false, "report only; never exit 1")
	fs.Parse(args)

	cur, err := catalog.Collect(*root)
	if err != nil {
		return 1, err
	}

	ref := *baseline
	if ref == "" {
		if ref, err = previousReleaseTag(*root); err != nil {
			return 1, err
		}
	}

	var base []catalog.Item
	if ref != "" {
		if text, err := gitShow(*root, ref, catalog.ManifestPath); err == nil {
			if base, err = catalog.Parse(text); err != nil {
				return 1, fmt.Errorf("baseline %s: %w", ref, err)
			}
			fmt.Printf("Baseline: %s (%d items)\n", ref, len(base))
		} else {
			fmt.Printf("Baseline: %s has no %s — first versioned release; checking cb-versions only\n", ref, catalog.ManifestPath)
		}
	} else {
		fmt.Println("Baseline: none found — checking cb-versions only")
	}

	baseParams := func(it catalog.Item) ([]string, bool) {
		text, err := gitShow(*root, ref, it.Path)
		if err != nil {
			return nil, false
		}
		p, err := catalog.TOMLParams([]byte(text))
		return p, err == nil
	}
	curParams := func(it catalog.Item) ([]string, bool) {
		data, err := os.ReadFile(filepath.Join(*root, it.Path))
		if err != nil {
			return nil, false
		}
		p, err := catalog.TOMLParams(data)
		return p, err == nil
	}

	findings := catalog.Check(base, cur, baseParams, curParams)

	// The committed manifest must match the tree, or the next release's baseline lies.
	committed, _ := os.ReadFile(filepath.Join(*root, catalog.ManifestPath))
	stale := string(committed) != catalog.Format(cur)

	sort.SliceStable(findings, func(a, b int) bool { return levelRank(findings[a].Level) < levelRank(findings[b].Level) })
	counts := map[catalog.Level]int{}
	for _, f := range findings {
		counts[f.Level]++
		fmt.Println(f)
	}
	if stale {
		fmt.Printf("FAIL  %s is stale — run build/gen-catalog-manifest.sh\n", catalog.ManifestPath)
		counts[catalog.Fail]++
	}
	fmt.Printf("\n%d fail, %d warn, %d info — %d items\n", counts[catalog.Fail], counts[catalog.Warn], counts[catalog.Info], len(cur))

	if counts[catalog.Fail] > 0 && !*report {
		return 1, nil
	}
	return 0, nil
}

func levelRank(l catalog.Level) int {
	switch l {
	case catalog.Fail:
		return 0
	case catalog.Warn:
		return 1
	}
	return 2
}

// previousReleaseTag is the highest MAJOR.MINOR.PATCH tag whose version is lower
// than the one in version.txt — the release users last got. Lower-than (not
// lower-or-equal) so a re-release of an already-tagged version still compares
// against the release before it. Reachability is not required: a release branch
// that has not been rebased onto the latest tag still compares against it, with
// a warning.
func previousReleaseTag(root string) (string, error) {
	raw, err := os.ReadFile(filepath.Join(root, "version.txt"))
	if err != nil {
		return "", err
	}
	curStr, _, _ := strings.Cut(strings.TrimSpace(string(raw)), "--")
	current, err := catalog.ParseSemver(curStr)
	if err != nil {
		return "", fmt.Errorf("version.txt: %w", err)
	}
	out, err := exec.Command("git", "-C", root, "tag", "--list").Output()
	if err != nil {
		return "", fmt.Errorf("listing tags: %w", err)
	}
	best, bestTag := catalog.Semver{}, ""
	for _, t := range strings.Fields(string(out)) {
		v, err := catalog.ParseSemver(t)
		if err != nil || v.Compare(current) >= 0 {
			continue
		}
		if bestTag == "" || v.Compare(best) > 0 {
			best, bestTag = v, t
		}
	}
	if bestTag != "" && exec.Command("git", "-C", root, "merge-base", "--is-ancestor", bestTag, "HEAD").Run() != nil {
		fmt.Printf("⚠️  %s is not an ancestor of HEAD — rebase onto it for a true comparison\n", bestTag)
	}
	return bestTag, nil
}

func gitShow(root, ref, path string) (string, error) {
	out, err := exec.Command("git", "-C", root, "show", ref+":"+path).Output()
	return string(out), err
}
