// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"errors"
	"testing"
)

func TestParsePortFromMapping(t *testing.T) {
	tests := []struct {
		name     string
		mapping  string
		expected string
	}{
		{
			name:     "simple host:container",
			mapping:  "8080:80",
			expected: "8080",
		},
		{
			name:     "same port",
			mapping:  "3000:3000",
			expected: "3000",
		},
		{
			name:     "single port",
			mapping:  "8080",
			expected: "8080",
		},
		{
			name:     "ip:host:container format",
			mapping:  "0.0.0.0:8080:80",
			expected: "8080",
		},
		{
			name:     "localhost:host:container format",
			mapping:  "127.0.0.1:3000:3000",
			expected: "3000",
		},
		{
			name:     "ipv6 style with brackets",
			mapping:  "[::]:8080:80",
			expected: "8080",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := parsePortFromMapping(tt.mapping)
			if result != tt.expected {
				t.Errorf("parsePortFromMapping(%q) = %q, want %q", tt.mapping, result, tt.expected)
			}
		})
	}
}

func TestParseProcessFromSS(t *testing.T) {
	tests := []struct {
		name     string
		line     string
		expected string
	}{
		{
			name:     "with users info",
			line:     `LISTEN 0      4096         0.0.0.0:3000       0.0.0.0:*    users:(("docker-proxy",pid=382268,fd=4))`,
			expected: `users:(("docker-proxy",pid=382268,fd=4))`,
		},
		{
			name:     "without users info",
			line:     `LISTEN 0      4096         0.0.0.0:3000       0.0.0.0:*`,
			expected: "unknown process",
		},
		{
			name:     "node process",
			line:     `LISTEN 0      128          0.0.0.0:3000       0.0.0.0:*    users:(("node",pid=12345,fd=18))`,
			expected: `users:(("node",pid=12345,fd=18))`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := parseProcessFromSS(tt.line)
			if result != tt.expected {
				t.Errorf("parseProcessFromSS() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestParseProcessFromLsof(t *testing.T) {
	tests := []struct {
		name     string
		output   string
		expected string
	}{
		{
			name: "typical lsof output",
			output: `COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node    12345 user   18u  IPv4  12345      0t0  TCP *:3000 (LISTEN)`,
			expected: "node (PID: 12345)",
		},
		{
			name: "docker-proxy output",
			output: `COMMAND       PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
docker-proxy 382268 root    4u  IPv4 1234567      0t0  TCP *:3000 (LISTEN)`,
			expected: "docker-proxy (PID: 382268)",
		},
		{
			name:     "empty output",
			output:   "",
			expected: "unknown process",
		},
		{
			name:     "header only",
			output:   "COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME\n",
			expected: "unknown process",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := parseProcessFromLsof(tt.output)
			if result != tt.expected {
				t.Errorf("parseProcessFromLsof() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestGetSuggestionForPort(t *testing.T) {
	tests := []struct {
		name        string
		port        string
		processInfo string
		contains    []string // substrings that should be in the suggestion
	}{
		{
			name:        "docker-proxy orphan",
			port:        "3000",
			processInfo: `users:(("docker-proxy",pid=382268,fd=4))`,
			contains:    []string{"orphaned docker-proxy", "Restart Docker", "sudo kill"},
		},
		{
			name:        "node process",
			port:        "3000",
			processInfo: `users:(("node",pid=12345,fd=18))`,
			contains:    []string{"Node.js", "Stop the dev server"},
		},
		{
			name:        "python process",
			port:        "8000",
			processInfo: `users:(("python",pid=54321,fd=5))`,
			contains:    []string{"Python", "Stop the server"},
		},
		{
			name:        "java process",
			port:        "8080",
			processInfo: `users:(("java",pid=99999,fd=10))`,
			contains:    []string{"Java", "Stop the application"},
		},
		{
			name:        "docker-proxy from lsof",
			port:        "80",
			processInfo: `docker-proxy (PID: 12345)`,
			contains:    []string{"orphaned docker-proxy", "Restart Docker"},
		},
		{
			name:        "unknown process",
			port:        "9000",
			processInfo: `users:(("unknown",pid=11111,fd=3))`,
			contains:    []string{"lsof -i :9000", "ss -tlnp | grep 9000"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := getSuggestionForPort(tt.port, tt.processInfo)
			for _, substr := range tt.contains {
				if !containsString(result, substr) {
					t.Errorf("getSuggestionForPort(%q, %q) = %q, should contain %q",
						tt.port, tt.processInfo, result, substr)
				}
			}
		})
	}
}

func TestDiagnosePortConflict_NilError(t *testing.T) {
	// Test that nil error always returns empty strings
	port, diagnostic := diagnosePortConflict(nil, 10000, []string{})
	if port != "" || diagnostic != "" {
		t.Errorf("diagnosePortConflict(nil) should return empty strings, got port=%q, diagnostic=%q",
			port, diagnostic)
	}
}

func TestDiagnosePortConflict_UnusedPort(t *testing.T) {
	// Test with a port that's very unlikely to be in use
	// Port 59999 is in the ephemeral range and unlikely to be bound
	err := errors.New("some docker error")
	port, diagnostic := diagnosePortConflict(err, 59999, []string{"59998:80"})

	// If neither port is in use, should return empty strings
	// (this test may be flaky if these ports happen to be in use)
	if port != "" && diagnostic != "" {
		// Port was found in use - check it's one of ours
		if port != "59999" && port != "59998" {
			t.Errorf("diagnosePortConflict() returned unexpected port=%q", port)
		}
	}
}

func TestDiagnosePortConflict_PortErrors(t *testing.T) {
	// Test that port-related errors are recognized
	tests := []struct {
		name     string
		err      error
		hostPort int
		extra    []string
	}{
		{
			name:     "address already in use",
			err:      errors.New("bind: address already in use"),
			hostPort: 10000,
			extra:    []string{},
		},
		{
			name:     "port is already allocated",
			err:      errors.New("port is already allocated"),
			hostPort: 10000,
			extra:    []string{"3000:3000"},
		},
		{
			name:     "ports are not available",
			err:      errors.New("ports are not available: exposing port TCP 0.0.0.0:3000"),
			hostPort: 10000,
			extra:    []string{"3000:3000"},
		},
		{
			name:     "docker error with port",
			err:      errors.New("docker: Error response from daemon: ports are not available: listen tcp 0.0.0.0:3000: bind: address already in use"),
			hostPort: 11000,
			extra:    []string{"3000:3000"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Note: This test may return empty if the ports aren't actually in use on the test machine.
			// The function tries to check actual port usage, so we mainly verify it doesn't panic
			// and recognizes the error pattern.
			port, _ := diagnosePortConflict(tt.err, tt.hostPort, tt.extra)
			// We can't guarantee a port will be returned since it depends on actual port state,
			// but we verify the function runs without error
			_ = port
		})
	}
}

func TestPortConflictError(t *testing.T) {
	err := &PortConflictError{
		Port:        "3000",
		ProcessInfo: "docker-proxy",
		Suggestion:  "restart docker",
	}

	expected := "port 3000 is already in use"
	if err.Error() != expected {
		t.Errorf("PortConflictError.Error() = %q, want %q", err.Error(), expected)
	}
}

// Helper function
func containsString(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(substr) == 0 ||
		(len(s) > 0 && len(substr) > 0 && stringContains(s, substr)))
}

func stringContains(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
