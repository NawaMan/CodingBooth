// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"strings"
	"testing"
)

func TestParseAllowlistPatterns(t *testing.T) {
	content := `
# comment
pypi.org
api.example.com # trailing

`
	patterns := parseAllowlistPatterns(content)
	if len(patterns) != 2 {
		t.Fatalf("expected 2 patterns, got %d", len(patterns))
	}
	if patterns[0] != `(^|.*\.)pypi\.org(:[0-9]+)?$` {
		t.Fatalf("unexpected first pattern: %q", patterns[0])
	}
	if patterns[1] != `(^|.*\.)api\.example\.com(:[0-9]+)?$` {
		t.Fatalf("unexpected second pattern: %q", patterns[1])
	}
}

func TestBuildEnvoyConfigFromPatterns(t *testing.T) {
	config := buildEnvoyConfigFromPatterns([]string{`(^|.*\.)pypi\.org(:[0-9]+)?$`})
	if !strings.Contains(config, "envoy.filters.http.rbac") {
		t.Fatalf("generated config missing RBAC filter")
	}
	if !strings.Contains(config, "pypi") {
		t.Fatalf("generated config missing allowlist pattern")
	}
	if !strings.Contains(config, "connect_config") {
		t.Fatalf("generated config missing CONNECT route configuration")
	}
}
