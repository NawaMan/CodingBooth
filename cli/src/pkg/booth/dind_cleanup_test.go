// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import "testing"

func TestIsBoothNetwork(t *testing.T) {
	cases := []struct {
		network, booth string
		want           bool
	}{
		{"appwrite-example-10000-net", "appwrite-example", true},
		{"appwrite-example-10000-egress-net", "appwrite-example", true},
		{"appwrite-example-50280-net", "appwrite-example", true}, // same booth, earlier port
		// A second booth from the same folder is auto-suffixed with its port; its
		// network must not be treated as the first booth's leftover, nor the reverse.
		{"appwrite-example-10001-10001-net", "appwrite-example", false},
		{"appwrite-example-10000-net", "appwrite-example-10001", false},
		{"appwrite-example-tools-10000-net", "appwrite-example", false},
		{"appwrite-example-net", "appwrite-example", false},
		{"appwrite-example-10000-netx", "appwrite-example", false},
		{"other-appwrite-example-10000-net", "appwrite-example", false},
		{"bridge", "appwrite-example", false},
	}
	for _, c := range cases {
		if got := isBoothNetwork(c.network, c.booth); got != c.want {
			t.Errorf("isBoothNetwork(%q, %q) = %v, want %v", c.network, c.booth, got, c.want)
		}
	}
}
