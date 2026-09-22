// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package profile

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func args(items ...string) []string { return items }

// whats returns the "what" of each collision, for compact assertions.
func whats(cs []Collision) []string {
	out := make([]string, 0, len(cs))
	for _, c := range cs {
		out = append(out, c.What)
	}
	return out
}

// ---------- env / label / build-arg ----------

func TestFindCollisions_EnvSameKeyDifferentValue(t *testing.T) {
	got := FindCollisions(args("-e", "LOG=info"), args("-e", "LOG=debug"))
	require.Len(t, got, 1)
	assert.Equal(t, "environment variable LOG", got[0].What)
	assert.Equal(t, "-e LOG=info", got[0].Earlier)
	assert.Equal(t, "-e LOG=debug", got[0].Later)
}

func TestFindCollisions_EnvIdenticalIsRedundantNotACollision(t *testing.T) {
	assert.Empty(t, FindCollisions(args("-e", "LOG=info"), args("-e", "LOG=info")))
}

func TestFindCollisions_EnvDifferentKeysDoNotCollide(t *testing.T) {
	assert.Empty(t, FindCollisions(args("-e", "A=1"), args("-e", "B=1")))
}

func TestFindCollisions_EnvPassthroughVersusAssignmentCollides(t *testing.T) {
	// "-e TOKEN" forwards the host value; "-e TOKEN=x" fixes one. They disagree.
	got := FindCollisions(args("-e", "TOKEN"), args("-e", "TOKEN=x"))
	assert.Equal(t, []string{"environment variable TOKEN"}, whats(got))
}

func TestFindCollisions_EnvFlagSpellingsAreOneThing(t *testing.T) {
	for name, later := range map[string][]string{
		"long":      args("--env", "LOG=debug"),
		"equals":    args("--env=LOG=debug"),
		"attached":  args("-eLOG=debug"),
		"short-sep": args("-e", "LOG=debug"),
	} {
		got := FindCollisions(args("-e", "LOG=info"), later)
		assert.Equal(t, []string{"environment variable LOG"}, whats(got), name)
	}
}

func TestFindCollisions_LabelAndBuildArg(t *testing.T) {
	got := FindCollisions(args("-l", "team=a"), args("--label", "team=b"))
	assert.Equal(t, []string{"label team"}, whats(got))

	got = FindCollisions(args("--build-arg", "NODE=18"), args("--build-arg", "NODE=20"))
	assert.Equal(t, []string{"build arg NODE"}, whats(got))
}

// ---------- volumes ----------

func TestFindCollisions_VolumeSameTargetDifferentSource(t *testing.T) {
	got := FindCollisions(args("-v", "/etc:/cfg"), args("-v", "/usr:/cfg"))
	require.Len(t, got, 1)
	assert.Equal(t, "mount target /cfg", got[0].What)
}

func TestFindCollisions_VolumeSameTargetDifferentOptionsCollides(t *testing.T) {
	got := FindCollisions(args("-v", "/etc:/cfg:ro"), args("-v", "/etc:/cfg"))
	assert.Equal(t, []string{"mount target /cfg"}, whats(got))
}

func TestFindCollisions_VolumeDifferentTargetsAndIdenticalDoNotCollide(t *testing.T) {
	assert.Empty(t, FindCollisions(args("-v", "/etc:/a"), args("-v", "/usr:/b")))
	assert.Empty(t, FindCollisions(args("-v", "/etc:/a"), args("-v", "/etc:/a")))
}

func TestFindCollisions_VolumeTargetIsNormalised(t *testing.T) {
	got := FindCollisions(args("-v", "/etc:/cfg/"), args("-v", "/usr:/cfg"))
	assert.Equal(t, []string{"mount target /cfg"}, whats(got), "a trailing slash is the same target")
}

func TestFindCollisions_VolumeNamedVolumeAndWindowsPaths(t *testing.T) {
	assert.Equal(t, []string{"mount target /data"},
		whats(FindCollisions(args("-v", "cache:/data"), args("-v", "/host:/data"))))
	assert.Equal(t, []string{"mount target /work"},
		whats(FindCollisions(args("-v", `C:\src:/work`), args("-v", `D:\other:/work`))),
		"a drive-letter colon is not the source/target separator")
	assert.Empty(t, FindCollisions(args("-v", `C:\src:/a`), args("-v", `D:\other:/b`)))
}

func TestFindCollisions_AnonymousVolumeClaimsNothing(t *testing.T) {
	assert.Empty(t, FindCollisions(args("-v", "/data"), args("-v", "/host:/data")))
}

// ---------- published ports ----------

func TestFindCollisions_PublishSameHostPortDifferentContainerPort(t *testing.T) {
	got := FindCollisions(args("-p", "39200:80"), args("-p", "39200:81"))
	assert.Equal(t, []string{"host port 39200/tcp"}, whats(got))
}

func TestFindCollisions_PublishSameContainerPortOnAnotherHostPort(t *testing.T) {
	// The overlay meant to move the base's port; instead both would be published.
	got := FindCollisions(args("-p", "39200:80"), args("-p", "39300:80"))
	assert.Equal(t, []string{"container port 80/tcp"}, whats(got))
}

func TestFindCollisions_PublishOnePairIsReportedOnce(t *testing.T) {
	// A wildcard bind covers 127.0.0.1, so these two clash on the host port — and they
	// also name the same container port. One pair of entries is one collision, not two.
	got := FindCollisions(args("-p", "8080:80"), args("-p", "127.0.0.1:8080:80"))
	require.Len(t, got, 1)
	assert.Equal(t, "host port 8080/tcp", got[0].What)
}

func TestFindCollisions_PublishIdenticalSpellingsAreRedundant(t *testing.T) {
	assert.Empty(t, FindCollisions(args("-p", "8080:80"), args("--publish", "8080:80/tcp")))
	assert.Empty(t, FindCollisions(args("-p", "8080:80"), args("-p", "0.0.0.0:8080:80")))
}

func TestFindCollisions_PublishProtocolsCoexist(t *testing.T) {
	assert.Empty(t, FindCollisions(args("-p", "5353:53/udp"), args("-p", "5353:53")))
}

func TestFindCollisions_PublishBindAddresses(t *testing.T) {
	// Different specific addresses can share a port; a wildcard covers every address.
	assert.Empty(t, FindCollisions(args("-p", "127.0.0.1:8080:80"), args("-p", "10.0.0.5:8080:81")))
	assert.Equal(t, []string{"host port 8080/tcp"},
		whats(FindCollisions(args("-p", "8080:80"), args("-p", "127.0.0.1:8080:81"))))
	assert.Equal(t, []string{"host port 8080/tcp"},
		whats(FindCollisions(args("-p", "127.0.0.1:8080:80"), args("-p", "127.0.0.1:8080:81"))))
}

func TestFindCollisions_PublishRelativeOffsetClaimsOnlyItsContainerPort(t *testing.T) {
	// "+OFFSET" is resolved against the booth port later, so its host side is not comparable.
	assert.Empty(t, FindCollisions(args("-p", "+80:80"), args("-p", "39200:81")))
	assert.Equal(t, []string{"container port 80/tcp"},
		whats(FindCollisions(args("-p", "+80:80"), args("-p", "+81:80"))))
}

func TestFindCollisions_PublishUnparseableFormsAreSkipped(t *testing.T) {
	assert.Empty(t, FindCollisions(args("-p", "8000-8010:8000-8010"), args("-p", "8000-8010:9000-9010")))
	assert.Empty(t, FindCollisions(args("-p", "80"), args("-p", "81")))
}

// ---------- scope of the check ----------

func TestFindCollisions_OnlyLaterAgainstEarlier(t *testing.T) {
	// A repeat inside one layer is that layer's own business, not a profile collision.
	assert.Empty(t, FindCollisions(nil, args("-e", "A=1", "-e", "A=2")))
	assert.Empty(t, FindCollisions(args("-e", "A=1", "-e", "A=2"), nil))
}

func TestFindCollisions_UnexaminedFlagsAreIgnored(t *testing.T) {
	assert.Empty(t, FindCollisions(args("--cpus", "2", "--network", "a"), args("--cpus", "4", "--network", "b")))
}

func TestFindCollisions_ReportsEveryCollision(t *testing.T) {
	got := FindCollisions(
		args("-e", "A=1", "-v", "/x:/t", "-p", "9000:80"),
		args("-e", "A=2", "-v", "/y:/t", "-p", "9001:80"),
	)
	assert.ElementsMatch(t,
		[]string{"environment variable A", "mount target /t", "container port 80/tcp"}, whats(got))
}

func TestFindCollisions_DanglingFlagIsSafe(t *testing.T) {
	assert.NotPanics(t, func() { FindCollisions(args("-e"), args("-p")) })
}
