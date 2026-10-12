// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/internal/hostskip"
)

const fingerprintTestDockerfile = `# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

COPY .booth/setups/ /opt/codingbooth/project-setups/
RUN <<'CB_EOF'
COPY not-a-real-instruction /nowhere
CB_EOF
COPY .booth/Boothfile rust-toolchai[n] rust-toolchain.tom[l] /tmp/cb-rust-toolchain/
`

var fingerprintTestFlags = []string{
	"-t", "codingbooth-local:demo-base-0.80.0",
	"--label", "cb.managed=true",
	"--build-arg", "BOOTH_VARIANT_TAG=base",
	"--build-arg", "BOOTH_VERSION_TAG=0.80.0",
}

func fingerprintTestContext(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	writeTestFile(t, dir, ".booth/setups/demo--setup.sh", "echo demo\n")
	writeTestFile(t, dir, ".booth/Boothfile", "# syntax=codingbooth/boothfile:1\n")
	return dir
}

func writeTestFile(t *testing.T, dir string, rel string, content string) {
	t.Helper()
	path := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

type fakeImages map[string]string

func (images fakeImages) resolve(ref string) (string, bool) {
	id, ok := images[ref]
	return id, ok
}

var fingerprintTestImages = fakeImages{"nawaman/codingbooth:base-0.80.0": "sha256:base1"}

func fingerprintOf(t *testing.T, dockerfile string, flags []string, dir string, images fakeImages) string {
	t.Helper()
	fingerprint, reason := ComputeBuildFingerprint(BuildFingerprintInput{
		Dockerfile: dockerfile,
		BuildFlags: flags,
		ContextDir: dir,
		ImageID:    images.resolve,
	})
	if reason != "" {
		t.Fatalf("expected a fingerprint, got reason: %s", reason)
	}
	return fingerprint
}

func noFingerprint(t *testing.T, dockerfile string, dir string, images fakeImages, wantReason string) {
	t.Helper()
	fingerprint, reason := ComputeBuildFingerprint(BuildFingerprintInput{
		Dockerfile: dockerfile,
		BuildFlags: fingerprintTestFlags,
		ContextDir: dir,
		ImageID:    images.resolve,
	})
	if fingerprint != "" {
		t.Fatalf("expected no fingerprint, got %s", fingerprint)
	}
	if !strings.Contains(reason, wantReason) {
		t.Fatalf("reason %q does not mention %q", reason, wantReason)
	}
}

func TestBuildFingerprint_Stable(t *testing.T) {
	dir := fingerprintTestContext(t)
	first := fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, dir, fingerprintTestImages)
	second := fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, dir, fingerprintTestImages)
	if first != second || len(first) != 64 {
		t.Fatalf("expected two equal 64-char fingerprints, got %q and %q", first, second)
	}
}

func TestBuildFingerprint_ChangesWithEachInput(t *testing.T) {
	dir := fingerprintTestContext(t)
	base := fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, dir, fingerprintTestImages)

	cases := map[string]func(t *testing.T) string{
		"dockerfile text": func(t *testing.T) string {
			return fingerprintOf(t, fingerprintTestDockerfile+"RUN echo more\n", fingerprintTestFlags, dir, fingerprintTestImages)
		},
		"build arg": func(t *testing.T) string {
			flags := append(append([]string(nil), fingerprintTestFlags...), "--build-arg", "EXTRA=1")
			return fingerprintOf(t, fingerprintTestDockerfile, flags, dir, fingerprintTestImages)
		},
		"base image rebuilt under the same tag": func(t *testing.T) string {
			images := fakeImages{"nawaman/codingbooth:base-0.80.0": "sha256:base2"}
			return fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, dir, images)
		},
		"setup script edited": func(t *testing.T) string {
			changed := fingerprintTestContext(t)
			writeTestFile(t, changed, ".booth/setups/demo--setup.sh", "echo changed\n")
			return fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, changed, fingerprintTestImages)
		},
		"setup script added": func(t *testing.T) string {
			changed := fingerprintTestContext(t)
			writeTestFile(t, changed, ".booth/setups/other--setup.sh", "echo other\n")
			return fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, changed, fingerprintTestImages)
		},
		"optional glob source appears": func(t *testing.T) string {
			changed := fingerprintTestContext(t)
			writeTestFile(t, changed, "rust-toolchain.toml", "[toolchain]\nchannel = \"stable\"\n")
			return fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, changed, fingerprintTestImages)
		},
		"setup script mode": func(t *testing.T) string {
			// The mode is part of the fingerprint, so only a host with modes
			// can change it (see internal/hostskip).
			hostskip.NoUnixModes(t)
			changed := fingerprintTestContext(t)
			if err := os.Chmod(filepath.Join(changed, ".booth/setups/demo--setup.sh"), 0o755); err != nil {
				t.Fatal(err)
			}
			return fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, changed, fingerprintTestImages)
		},
	}
	for name, compute := range cases {
		t.Run(name, func(t *testing.T) {
			if compute(t) == base {
				t.Fatalf("fingerprint did not change")
			}
		})
	}
}

func TestBuildFingerprint_IgnoresFilesNotCopied(t *testing.T) {
	dir := fingerprintTestContext(t)
	base := fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, dir, fingerprintTestImages)
	writeTestFile(t, dir, "src/main.go", "package main\n")
	if fingerprintOf(t, fingerprintTestDockerfile, fingerprintTestFlags, dir, fingerprintTestImages) != base {
		t.Fatal("a file outside the COPY sources changed the fingerprint")
	}
}

func TestBuildFingerprint_HeredocBodyIsNotAnInstruction(t *testing.T) {
	// The heredoc body holds "COPY not-a-real-instruction"; were it parsed, the
	// missing source would still hash fine, so assert on the parse directly.
	for _, inst := range parseDockerfileInstructions(fingerprintTestDockerfile) {
		for _, arg := range inst.args {
			if arg == "not-a-real-instruction" {
				t.Fatalf("heredoc body parsed as %s instruction", inst.keyword)
			}
		}
	}
}

func TestBuildFingerprint_BaseImageMissingLocally(t *testing.T) {
	noFingerprint(t, fingerprintTestDockerfile, fingerprintTestContext(t), fakeImages{}, "not present locally")
}

func TestBuildFingerprint_CopyFromImageIsResolved(t *testing.T) {
	dir := fingerprintTestContext(t)
	dockerfile := "FROM busybox AS tools\nFROM nawaman/codingbooth:base-0.80.0\nCOPY --from=tools /bin/sh /x\nCOPY --from=alpine:3 /bin/sh /y\n"
	images := fakeImages{"busybox": "sha256:b", "nawaman/codingbooth:base-0.80.0": "sha256:c", "alpine:3": "sha256:a1"}
	first := fingerprintOf(t, dockerfile, nil, dir, images)
	images["alpine:3"] = "sha256:a2"
	if fingerprintOf(t, dockerfile, nil, dir, images) == first {
		t.Fatal("a changed COPY --from image did not change the fingerprint")
	}
	delete(images, "alpine:3")
	noFingerprint(t, dockerfile, dir, images, "alpine:3")
}

func TestBuildFingerprint_JSONFormSources(t *testing.T) {
	dir := fingerprintTestContext(t)
	dockerfile := "FROM nawaman/codingbooth:base-0.80.0\nCOPY --chown=coder [\".booth/setups/\", \"/opt/x/\"]\n"
	first := fingerprintOf(t, dockerfile, nil, dir, fingerprintTestImages)
	writeTestFile(t, dir, ".booth/setups/demo--setup.sh", "echo changed\n")
	if fingerprintOf(t, dockerfile, nil, dir, fingerprintTestImages) == first {
		t.Fatal("JSON-form COPY source change did not change the fingerprint")
	}
}

func TestBuildFingerprint_SymlinkedSourceRootIsFollowed(t *testing.T) {
	hostskip.NoSymlinks(t)

	dir := fingerprintTestContext(t)
	writeTestFile(t, dir, "real/config.txt", "one\n")
	if err := os.Symlink("real", filepath.Join(dir, "linked")); err != nil {
		t.Fatal(err)
	}
	dockerfile := "FROM nawaman/codingbooth:base-0.80.0\nCOPY linked /x\n"
	first := fingerprintOf(t, dockerfile, nil, dir, fingerprintTestImages)
	writeTestFile(t, dir, "real/config.txt", "two\n")
	if fingerprintOf(t, dockerfile, nil, dir, fingerprintTestImages) == first {
		t.Fatal("content behind a symlinked source did not change the fingerprint")
	}
}

func TestBuildFingerprint_FallsBackToBuilding(t *testing.T) {
	dir := fingerprintTestContext(t)
	from := "FROM nawaman/codingbooth:base-0.80.0\n"
	cases := map[string][2]string{
		"remote ADD":            {from + "ADD https://example.com/tool.tgz /opt/\n", "remote source"},
		"git ADD":               {from + "ADD git@github.com:me/repo.git /opt/\n", "remote source"},
		"bind mount":            {from + "RUN --mount=type=bind,source=.,target=/src make\n", "bind-mounts"},
		"default mount type":    {from + "RUN --mount=target=/src make\n", "bind-mounts"},
		"outside the context":   {from + "COPY ../secret /x\n", "outside the build context"},
		"unresolved variable":   {from + "COPY ${UNSET_DIR}/x /x\n", "UNSET_DIR"},
		"undecodable JSON form": {from + "COPY [\"a\", /x\n", "cannot parse"},
	}
	for name, testCase := range cases {
		t.Run(name, func(t *testing.T) {
			noFingerprint(t, testCase[0], dir, fingerprintTestImages, testCase[1])
		})
	}
}

func TestBuildFingerprint_NonContextMountsAreFine(t *testing.T) {
	dir := fingerprintTestContext(t)
	dockerfile := "FROM nawaman/codingbooth:base-0.80.0\nRUN --mount=type=cache,target=/root/.cache make\nRUN --mount=type=bind,from=builder,target=/b ls\nRUN [ -f /etc/hosts ] && echo ok\n"
	fingerprintOf(t, dockerfile, nil, dir, fingerprintTestImages)
}

func TestBuildFingerprint_SizeCap(t *testing.T) {
	dir := fingerprintTestContext(t)
	for index := 0; index <= fingerprintMaxFiles; index++ {
		writeTestFile(t, dir, filepath.Join("many", fmt.Sprintf("file-%d", index)), "")
	}
	noFingerprint(t, "FROM nawaman/codingbooth:base-0.80.0\nCOPY . /src\n", dir, fingerprintTestImages, "more than")
}

func TestBuildFingerprint_ArgDefaultsAndOverrides(t *testing.T) {
	dir := fingerprintTestContext(t)
	images := fakeImages{
		"nawaman/codingbooth:base-latest":       "sha256:latest",
		"nawaman/codingbooth:codeserver-0.80.0": "sha256:cs",
	}
	// No build args: the ARG defaults pick base-latest.
	fingerprintOf(t, fingerprintTestDockerfile, nil, dir, images)
	// Build args override the defaults.
	flags := []string{"--build-arg", "BOOTH_VARIANT_TAG=codeserver", "--build-arg=BOOTH_VERSION_TAG=0.80.0"}
	fingerprintOf(t, fingerprintTestDockerfile, flags, dir, images)
}
