// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func mustParse(t *testing.T, raw string) PortMapping {
	t.Helper()
	m, ok := ParsePortMapping(raw)
	require.True(t, ok, "ParsePortMapping(%q) should parse", raw)
	return m
}

func TestParsePortMapping_Forms(t *testing.T) {
	m := mustParse(t, "18978:8978")
	assert.Equal(t, 18978, m.Host)
	assert.Equal(t, "8978", m.Container)
	assert.Equal(t, "", m.IP)
	assert.Equal(t, "tcp", m.Proto)
	assert.False(t, m.Relative)

	m = mustParse(t, "127.0.0.1:18978:8978")
	assert.Equal(t, "127.0.0.1", m.IP)
	assert.Equal(t, 18978, m.Host)

	m = mustParse(t, "5000:5000/udp")
	assert.Equal(t, "udp", m.Proto)

	_, ok := ParsePortMapping("8978")
	assert.False(t, ok, "a bare port is not a mapping")
}

func TestParsePortMapping_RelativeIsNotAnAbsolutePort(t *testing.T) {
	// strconv.Atoi("+4567") == 4567, so without the Relative flag an unresolved offset
	// would be compared against real ports as if it had already claimed 4567.
	m := mustParse(t, "+4567:5672")
	assert.True(t, m.Relative)
	assert.Equal(t, 4567, m.Host, "the offset itself")
	assert.Equal(t, "5672", m.Container)
}

func TestPortConflicts_SameHostPort(t *testing.T) {
	// The nginx+apache case: two templates, both defaulting to host 8080.
	conflicts := PortConflicts([]PortMapping{
		mustParse(t, "8080:80"),
		mustParse(t, "8080:8080"),
	})
	require.Len(t, conflicts, 1)
	assert.Equal(t, 8080, conflicts[0][0].Host)
}

func TestPortConflicts_IdenticalMappingIsNotAConflict(t *testing.T) {
	// Redundant, not conflicting — DedupePortMappings collapses it instead.
	assert.Empty(t, PortConflicts([]PortMapping{
		mustParse(t, "8978:8978"),
		mustParse(t, "8978:8978"),
	}))
}

func TestPortConflicts_SameContainerPortOnTwoHostPortsIsFine(t *testing.T) {
	// Docker allows this, so we must not reject it.
	assert.Empty(t, PortConflicts([]PortMapping{
		mustParse(t, "8978:8978"),
		mustParse(t, "19000:8978"),
	}))
}

func TestPortConflicts_DifferentProtocolsDoNotCollide(t *testing.T) {
	assert.Empty(t, PortConflicts([]PortMapping{
		mustParse(t, "5000:5000/tcp"),
		mustParse(t, "5000:5000/udp"),
	}))
}

func TestPortConflicts_PinnedAddressesDoNotCollide(t *testing.T) {
	// Two different interfaces can each bind the same port…
	assert.Empty(t, PortConflicts([]PortMapping{
		mustParse(t, "127.0.0.1:8978:8978"),
		mustParse(t, "192.168.1.5:8978:9000"),
	}))

	// …but a wildcard bind covers every interface, so it collides with a pinned one.
	conflicts := PortConflicts([]PortMapping{
		mustParse(t, "8978:8978"),
		mustParse(t, "127.0.0.1:8978:9000"),
	})
	assert.Len(t, conflicts, 1)
}

func TestPortConflicts_RelativeMappingIsNotCompared(t *testing.T) {
	// Until the booth port is known, "+4567" claims nothing. NormalizePortMappings runs
	// after ResolveRelativePorts, so a relative mapping should never reach the check —
	// but it must not produce a bogus conflict against port 4567 if one does.
	assert.Empty(t, PortConflicts([]PortMapping{
		mustParse(t, "+4567:5672"),
		mustParse(t, "4567:1234"),
	}))
}

func TestDedupePortMappings_CollapsesAcrossFlagForms(t *testing.T) {
	// "cloudbeaver+expose --expose 8978:8978": the template's -p and the user's --publish
	// are the same mapping, and docker refuses to bind one host port twice.
	args := []string{"-v", "/data:/data", "-p", "8978:8978", "--publish", "8978:8978"}
	got, removed := DedupePortMappings(args)
	assert.Equal(t, []string{"-v", "/data:/data", "-p", "8978:8978"}, got)
	assert.Equal(t, 1, removed)
}

func TestDedupePortMappings_KeepsDistinctMappings(t *testing.T) {
	args := []string{"-p", "8978:8978", "-p", "19000:8978", "-e", "X=1"}
	got, removed := DedupePortMappings(args)
	assert.Equal(t, args, got)
	assert.Equal(t, 0, removed)
}
