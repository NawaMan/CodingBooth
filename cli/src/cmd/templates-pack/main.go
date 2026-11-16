// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// templates-pack writes the template catalog the CLI embeds
// (src/pkg/boothinit/cache/embedded/templates.zip): the repository's templates/
// tree, with the version it belongs to as the zip comment. build/cli-build.sh
// runs it before `go build`. The archive is deterministic (sorted, fixed times),
// so two builds of one tree embed the same bytes.
package main

import (
	"archive/zip"
	"bytes"
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

func main() {
	root := flag.String("root", "..", "repository root")
	out := flag.String("out", "src/pkg/boothinit/cache/embedded/templates.zip", "archive to write")
	version := flag.String("version", "", "version the catalog belongs to (default: <root>/version.txt)")
	flag.Parse()

	if err := run(*root, *out, *version); err != nil {
		fmt.Fprintln(os.Stderr, "templates-pack:", err)
		os.Exit(1)
	}
}

func run(root, out, version string) error {
	if version == "" {
		data, err := os.ReadFile(filepath.Join(root, "version.txt"))
		if err != nil {
			return err
		}
		version = strings.TrimSpace(string(data))
	}
	if version == "" {
		return fmt.Errorf("no version to stamp into the catalog")
	}

	// Tracked and untracked-but-not-ignored files, as git sees them.
	listed, err := exec.Command("git", "-C", root, "ls-files", "-co", "--exclude-standard", "-z", "--", "templates").Output()
	if err != nil {
		return fmt.Errorf("git ls-files: %w", err)
	}
	var files []string
	for _, p := range strings.Split(string(listed), "\x00") {
		if p == "" {
			continue
		}
		if info, err := os.Lstat(filepath.Join(root, p)); err != nil || !info.Mode().IsRegular() {
			continue // deleted in the work tree, or a symlink
		}
		files = append(files, p)
	}
	if len(files) == 0 {
		return fmt.Errorf("no files under %s", filepath.Join(root, "templates"))
	}
	sort.Strings(files)

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	if err := zw.SetComment(version); err != nil {
		return err
	}
	epoch := time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC) // the earliest time a zip can hold
	for _, p := range files {
		full := filepath.Join(root, p)
		info, err := os.Stat(full)
		if err != nil {
			return err
		}
		mode := os.FileMode(0644)
		if info.Mode()&0111 != 0 {
			mode = 0755
		}
		hdr := &zip.FileHeader{Name: p, Method: zip.Deflate, Modified: epoch}
		hdr.SetMode(mode)
		w, err := zw.CreateHeader(hdr)
		if err != nil {
			return err
		}
		f, err := os.Open(full)
		if err != nil {
			return err
		}
		_, err = io.Copy(w, f)
		f.Close()
		if err != nil {
			return err
		}
	}
	if err := zw.Close(); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(out), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(out, buf.Bytes(), 0644); err != nil {
		return err
	}
	fmt.Printf("templates-pack: %d files, %d bytes, version %s -> %s\n", len(files), buf.Len(), version, out)
	return nil
}
