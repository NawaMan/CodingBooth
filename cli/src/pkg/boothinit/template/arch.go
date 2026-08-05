// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"runtime"
	"strings"
)

// HostArch reports the architecture a booth built here will be built for, using
// dpkg's names ("amd64", "arm64") so it matches what the setup scripts see via
// `dpkg --print-architecture`.
//
// Docker builds for the host architecture unless told otherwise, and CodingBooth
// never passes --platform, so the Go runtime's arch is the right answer: on
// Apple Silicon that is arm64, and the booth is an arm64 Linux container.
func HostArch() string {
	switch runtime.GOARCH {
	case "amd64", "386":
		return "amd64"
	case "arm64":
		return "arm64"
	default:
		return runtime.GOARCH
	}
}

// UnsupportedOn reports whether this template cannot install on the given
// architecture. Such a template still builds — its setup warns and skips rather
// than failing the build — but the tool will not be present in the booth.
func (t *Template) UnsupportedOn(arch string) bool {
	for _, a := range t.UnsupportedArch {
		if strings.EqualFold(strings.TrimSpace(a), arch) {
			return true
		}
	}
	return false
}
