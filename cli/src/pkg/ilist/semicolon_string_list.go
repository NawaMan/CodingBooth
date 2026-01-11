// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package ilist

import (
	"os"
	"strings"
)

type SemicolonStringList struct {
	List[string]
}

// expandEnv expands environment variables and tilde in a string.
// - ~ at the start of a string is expanded to $HOME
// - $VAR and ${VAR} are expanded to their environment values
func expandEnv(s string) string {
	// Expand ~ at the beginning of the string to $HOME
	if strings.HasPrefix(s, "~/") {
		s = "$HOME" + s[1:]
	} else if s == "~" {
		s = "$HOME"
	}
	// Expand environment variables
	return os.ExpandEnv(s)
}

func (s *SemicolonStringList) Decode(value string) error {
	if strings.TrimSpace(value) == "" {
		s.elements = nil
		return nil
	}

	parts := strings.Split(value, ";")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		out = append(out, expandEnv(p))
	}

	s.elements = out
	return nil
}

func (s *SemicolonStringList) Clone() SemicolonStringList {
	return SemicolonStringList{List: s.List.Clone()}
}

// UnmarshalTOML implements the toml.Unmarshaler interface.
// This allows TOML to decode both string values (semicolon-separated) and arrays into a SemicolonStringList.
// Environment variables ($VAR, ${VAR}) and tilde (~) are automatically expanded.
func (s *SemicolonStringList) UnmarshalTOML(data interface{}) error {
	switch v := data.(type) {
	case string:
		return s.Decode(v)
	case []interface{}:
		// Handle TOML array
		out := make([]string, 0, len(v))
		for _, item := range v {
			if str, ok := item.(string); ok {
				out = append(out, expandEnv(str))
			}
		}
		s.elements = out
		return nil
	default:
		return nil // Let TOML handle type errors
	}
}
