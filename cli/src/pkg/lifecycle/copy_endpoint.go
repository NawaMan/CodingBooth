// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"fmt"
	"strings"
)

type copyEndpoint struct {
	booth bool
	name  string
	path  string
}

func parseCopyEndpoint(value string) (copyEndpoint, error) {
	if value == "" {
		return copyEndpoint{}, fmt.Errorf("copy paths must not be empty")
	}
	// An explicit ./path, absolute path, or Windows drive/UNC path stays local,
	// even if a component contains ':'. A bare file:name needs the './' prefix.
	colon := strings.IndexByte(value, ':')
	separator := strings.IndexAny(value, `/\`)
	drive := colon == 1 && ((value[0] >= 'a' && value[0] <= 'z') || (value[0] >= 'A' && value[0] <= 'Z')) &&
		len(value) > 2 && (value[2] == '/' || value[2] == '\\')
	if colon < 0 || drive || (separator >= 0 && separator < colon) {
		return copyEndpoint{path: value}, nil
	}
	if colon == len(value)-1 {
		return copyEndpoint{}, fmt.Errorf("missing path after ':' in %q", value)
	}
	return copyEndpoint{booth: true, name: value[:colon], path: value[colon+1:]}, nil
}
