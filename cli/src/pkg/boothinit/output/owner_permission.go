// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"fmt"
	"strconv"
	"strings"
)

// OwnerPermissionName is the generated file booth-entry reads at container start.
const OwnerPermissionName = "owner-permission.yaml"

// SerializeOwnerPermission renders .booth/owner-permission.yaml.
// An empty list renders nothing, so the file is not written.
func SerializeOwnerPermission(entries []OwnerPerm, command, adjustCommand string) string {
	if len(entries) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString(formatGeneratedHeader("#", command, adjustCommand))
	b.WriteString("# booth-entry applies each entry to that mount point on startup.\n")
	b.WriteString("# A directory entry covers that directory and every directory under it.\n")
	for _, e := range entries {
		fmt.Fprintf(&b, "- path: %s\n", strconv.Quote(e.Path))
		if e.User != "" {
			fmt.Fprintf(&b, "  user: %s\n", strconv.Quote(e.User))
		}
		if e.Group != "" {
			fmt.Fprintf(&b, "  group: %s\n", strconv.Quote(e.Group))
		}
		if e.Mode != "" {
			fmt.Fprintf(&b, "  mode: %s\n", strconv.Quote(e.Mode))
		}
	}
	return b.String()
}
