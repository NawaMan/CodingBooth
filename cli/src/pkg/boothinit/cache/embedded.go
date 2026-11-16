// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package cache

import (
	"archive/zip"
	"bytes"
	"embed"
	"strings"
)

// embedded holds templates.zip when build/cli-build.sh generated it
// (cli/src/cmd/templates-pack), and only README.md otherwise.
//
//go:embed embedded
var embedded embed.FS

const embeddedZip = "embedded/" + templateFile

// embeddedZipData returns the embedded catalog. A test replaces it.
var embeddedZipData = func() []byte {
	data, err := embedded.ReadFile(embeddedZip)
	if err != nil {
		return nil
	}
	return data
}

// EmbeddedVersion is the version whose catalog this binary carries: the zip
// comment templates-pack wrote. Empty when the binary was built without one.
func EmbeddedVersion() string {
	r := embeddedReader()
	if r == nil {
		return ""
	}
	return strings.TrimSpace(r.Comment)
}

// embeddedFor returns the embedded catalog when it is the one for version.
func embeddedFor(version string) *zip.Reader {
	r := embeddedReader()
	if r == nil || version == "" || strings.TrimSpace(r.Comment) != version {
		return nil
	}
	return r
}

func embeddedReader() *zip.Reader {
	data := embeddedZipData()
	if len(data) == 0 {
		return nil
	}
	r, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil
	}
	return r
}
