// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package ilist

import (
	"fmt"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/shellexpand"
)

type SemicolonStringList struct {
	List[string]
}

// ExpandEnv expands a single string with booth's bash-like rules. See
// docs/BOOTH_VARS.md for the rule set. Returns an error for unsupported
// operators, unterminated quotes, ${VAR:?} on unset values, etc.
func ExpandEnv(s string) (string, error) {
	return shellexpand.Expand(s, shellexpand.DefaultLookup, shellexpand.SourceRef{})
}

// ExpandEnvWithSource is like ExpandEnv but annotates errors with src so
// callers can report which TOML field or env var produced the failure.
func ExpandEnvWithSource(s string, src shellexpand.SourceRef) (string, error) {
	return shellexpand.Expand(s, shellexpand.DefaultLookup, src)
}

func (s *SemicolonStringList) Decode(value string) error {
	if strings.TrimSpace(value) == "" {
		s.elements = nil
		return nil
	}

	parts := strings.Split(value, ";")
	out := make([]string, 0, len(parts))
	idx := -1
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		idx++
		expanded, err := ExpandEnvWithSource(p, shellexpand.SourceRef{Field: fmt.Sprintf("[%d]", idx)})
		if err != nil {
			return err
		}
		out = append(out, expanded)
	}

	s.elements = out
	return nil
}

func (s *SemicolonStringList) Clone() SemicolonStringList {
	return SemicolonStringList{List: s.List.Clone()}
}

// UnmarshalTOML implements the toml.Unmarshaler interface.
// This allows TOML to decode both string values (semicolon-separated) and arrays into a SemicolonStringList.
// Environment variables ($VAR, ${VAR}) and tilde (~) are automatically expanded per docs/BOOTH_VARS.md.
func (s *SemicolonStringList) UnmarshalTOML(data interface{}) error {
	switch v := data.(type) {
	case string:
		return s.Decode(v)
	case []interface{}:
		// Handle TOML array
		out := make([]string, 0, len(v))
		for i, item := range v {
			if str, ok := item.(string); ok {
				expanded, err := ExpandEnvWithSource(str, shellexpand.SourceRef{Field: fmt.Sprintf("[%d]", i)})
				if err != nil {
					return err
				}
				out = append(out, expanded)
			}
		}
		s.elements = out
		return nil
	default:
		return nil // Let TOML handle type errors
	}
}
