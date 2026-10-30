// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// prepare-kit writes the kit `booth prepare` embeds (src/pkg/prepare/kit/kit.tar.gz):
// what the base image copies in (setups, entry scripts, docs markdown), every
// variant's Dockerfile, and the replay scripts under experiments/host-provision/.
// build/cli-build.sh runs it before `go build`. The archive is deterministic
// (sorted, fixed times and owners), so two builds of one tree embed the same bytes.
package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Tracked and untracked-but-not-ignored files under these, as git sees them.
var roots = []string{"variants", "experiments/host-provision", "docs", "README.md", "LICENSE", "version.txt"}

// keep says whether a repo-relative path belongs in the kit. docs/ is the image's
// share of it: the markdown and the favicon (docker-build.sh StageDocsForBase).
func keep(p string) bool {
	switch {
	case strings.HasPrefix(p, "variants/base/_stage/"):
		return false
	case strings.HasPrefix(p, "experiments/host-provision/.out/"):
		return false
	case strings.HasPrefix(p, "docs/"):
		return strings.HasSuffix(p, ".md") || p == "docs/favicon.png"
	}
	return true
}

func main() {
	root := flag.String("root", "..", "repository root")
	out := flag.String("out", "src/pkg/prepare/kit/kit.tar.gz", "archive to write")
	flag.Parse()

	if err := run(*root, *out); err != nil {
		fmt.Fprintln(os.Stderr, "prepare-kit:", err)
		os.Exit(1)
	}
}

func run(root, out string) error {
	args := append([]string{"-C", root, "ls-files", "-co", "--exclude-standard", "-z", "--"}, roots...)
	listed, err := exec.Command("git", args...).Output()
	if err != nil {
		return fmt.Errorf("git ls-files: %w", err)
	}
	var files []string
	for _, p := range strings.Split(string(listed), "\x00") {
		if p == "" || !keep(p) {
			continue
		}
		if info, err := os.Lstat(filepath.Join(root, p)); err != nil || !info.Mode().IsRegular() {
			continue // deleted in the work tree, or a symlink
		}
		files = append(files, p)
	}
	sort.Strings(files)

	var buf bytes.Buffer
	gz, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	tw := tar.NewWriter(gz)
	epoch := time.Unix(0, 0)
	for _, p := range files {
		full := filepath.Join(root, p)
		info, err := os.Stat(full)
		if err != nil {
			return err
		}
		mode := int64(0644)
		if info.Mode()&0111 != 0 {
			mode = 0755
		}
		hdr := &tar.Header{Name: p, Mode: mode, Size: info.Size(), ModTime: epoch, Typeflag: tar.TypeReg, Format: tar.FormatPAX}
		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}
		f, err := os.Open(full)
		if err != nil {
			return err
		}
		_, err = io.Copy(tw, f)
		f.Close()
		if err != nil {
			return err
		}
	}
	if err := tw.Close(); err != nil {
		return err
	}
	if err := gz.Close(); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(out), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(out, buf.Bytes(), 0644); err != nil {
		return err
	}
	fmt.Printf("prepare-kit: %d files, %d bytes -> %s\n", len(files), buf.Len(), out)
	return nil
}
