// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bytes"
	"io"
	"os"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
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

// exposedPortsCtx builds the AppContext exposedPublicPorts/CheckPublicPortsExposed need.
func exposedPortsCtx(public, okPublic, quiet bool, runArgs []string) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
		PortNumber: 13000,
	}
	builder.Config.Public = public
	builder.Config.OkPublic = okPublic
	builder.Config.Quiet = quiet
	if len(runArgs) > 0 {
		builder.RunArgs.Append(ilist.NewListFromSlice(runArgs))
	}
	return builder.Build()
}

// exposedPublicPorts is the pure decision half — this is what a test can drive
// directly for the refuse-unless-ok-public case, since CheckPublicPortsExposed
// itself calls os.Exit(1) there and cannot be called in-process.

func TestExposedPublicPorts_ReportsExtraPortOnPublicBooth(t *testing.T) {
	ports := exposedPublicPorts(exposedPortsCtx(true, false, false, []string{"-p", "18080:80"}))
	assert.Equal(t, []string{"18080"}, ports)
}

func TestExposedPublicPorts_NilWhenNotPublic(t *testing.T) {
	ports := exposedPublicPorts(exposedPortsCtx(false, false, false, []string{"-p", "18080:80"}))
	assert.Nil(t, ports)
}

func TestExposedPublicPorts_NilWhenNoExtraPortsPublished(t *testing.T) {
	ports := exposedPublicPorts(exposedPortsCtx(true, false, false, nil))
	assert.Nil(t, ports)
}

func TestExposedPublicPorts_ListsEachDistinctPortOnce(t *testing.T) {
	ports := exposedPublicPorts(exposedPortsCtx(true, false, false, []string{
		"-p", "18080:80", "-p", "19090:90", "-p", "18080:80", // repeat, should not double-list
	}))
	assert.ElementsMatch(t, []string{"18080", "19090"}, ports)
}

// captureCheckPublicPortsExposed runs CheckPublicPortsExposed and captures stderr —
// same pattern as TestPrintHomeVolumeWarning_* in booth_test.go. Only safe to call
// for cases that do not reach os.Exit(1): not public, no extra ports, or okPublic.
func captureCheckPublicPortsExposed(t *testing.T, public, okPublic, quiet bool, runArgs []string) string {
	t.Helper()

	oldStderr := os.Stderr
	reader, writer, err := os.Pipe()
	require.NoError(t, err)
	os.Stderr = writer

	ctx := exposedPortsCtx(public, okPublic, quiet, runArgs)

	CheckPublicPortsExposed(ctx)

	writer.Close()
	os.Stderr = oldStderr

	var buf bytes.Buffer
	io.Copy(&buf, reader)
	return buf.String()
}

func TestCheckPublicPortsExposed_SilentWhenNotPublic(t *testing.T) {
	out := captureCheckPublicPortsExposed(t, false, false, false, []string{"-p", "18080:80"})
	assert.Empty(t, out)
}

func TestCheckPublicPortsExposed_SilentWhenNoExtraPortsPublished(t *testing.T) {
	out := captureCheckPublicPortsExposed(t, true, false, false, nil)
	assert.Empty(t, out)
}

func TestCheckPublicPortsExposed_OkPublicWarnsRatherThanStayingSilent(t *testing.T) {
	out := captureCheckPublicPortsExposed(t, true, true, false, []string{"-p", "18080:80"})
	assert.Contains(t, out, "public")
	assert.Contains(t, out, "18080")
	assert.Contains(t, out, "13000") // the booth's own (protected) port, for contrast
}

func TestCheckPublicPortsExposed_OkPublicButQuietStaysSilent(t *testing.T) {
	out := captureCheckPublicPortsExposed(t, true, true, true, []string{"-p", "18080:80"})
	assert.Empty(t, out)
}

// The refuse-without-ok-public path (os.Exit(1)) cannot be called in-process — it
// is exercised for real, as a subprocess, by tests/dryrun/test040--public-exposed-port-warning.sh.
