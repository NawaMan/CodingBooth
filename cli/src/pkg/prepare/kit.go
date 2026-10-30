// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package prepare

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"embed"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// kit holds kit.tar.gz when build/cli-build.sh generated it (cli/src/cmd/prepare-kit),
// and only README.md otherwise.
//
//go:embed kit
var kit embed.FS

// ErrNoKit means this binary was built without the kit; --source is then required.
var ErrNoKit = errors.New("this booth binary has no embedded prepare kit (built without build/cli-build.sh); use --source <CodingBooth checkout>")

// HasKit reports whether the kit is embedded.
func HasKit() bool {
	_, err := kit.Open("kit/kit.tar.gz")
	return err == nil
}

// ExtractKit unpacks the embedded kit into dir, keeping each file's mode.
func ExtractKit(dir string) error {
	data, err := kit.ReadFile("kit/kit.tar.gz")
	if err != nil {
		return ErrNoKit
	}
	return extractTarGz(bytes.NewReader(data), dir)
}

func extractTarGz(r io.Reader, dir string) error {
	gz, err := gzip.NewReader(r)
	if err != nil {
		return fmt.Errorf("prepare kit: %w", err)
	}
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return fmt.Errorf("prepare kit: %w", err)
		}
		name := filepath.Clean(hdr.Name)
		if filepath.IsAbs(name) || name == ".." || strings.HasPrefix(name, ".."+string(filepath.Separator)) {
			return fmt.Errorf("prepare kit: unsafe path %q", hdr.Name)
		}
		if hdr.Typeflag != tar.TypeReg {
			continue
		}
		dest := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
			return err
		}
		f, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(hdr.Mode)&0777)
		if err != nil {
			return err
		}
		_, err = io.Copy(f, tr)
		f.Close()
		if err != nil {
			return err
		}
	}
}

// CheckSource says whether dir looks like a CodingBooth checkout (or an extracted kit).
func CheckSource(dir string) error {
	for _, p := range []string{"variants/base/setups", "experiments/host-provision/base-provision.sh", "version.txt"} {
		if _, err := os.Stat(filepath.Join(dir, p)); err != nil {
			return fmt.Errorf("%s is not a CodingBooth checkout: missing %s", dir, p)
		}
	}
	return nil
}
