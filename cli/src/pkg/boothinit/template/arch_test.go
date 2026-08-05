// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- HostArch ---

func TestHostArch_UsesDpkgNames(t *testing.T) {
	// dpkg and Go agree on "amd64"/"arm64", which is the whole point of the
	// mapping: what HostArch returns is comparable to what a setup script sees
	// from `dpkg --print-architecture` without translation at the call site.
	switch runtime.GOARCH {
	case "amd64", "arm64":
		assert.Equal(t, runtime.GOARCH, HostArch())
	default:
		t.Skipf("no dpkg-name assertion for GOARCH %q", runtime.GOARCH)
	}
}

// --- UnsupportedOn ---

func TestUnsupportedOn_MatchesListedArch(t *testing.T) {
	tmpl := &Template{Name: "google-chrome", UnsupportedArch: []string{"arm64"}}
	assert.True(t, tmpl.UnsupportedOn("arm64"))
	assert.False(t, tmpl.UnsupportedOn("amd64"))
}

func TestUnsupportedOn_EmptyListSupportsEverything(t *testing.T) {
	tmpl := &Template{Name: "chromium"}
	assert.False(t, tmpl.UnsupportedOn("arm64"))
	assert.False(t, tmpl.UnsupportedOn("amd64"))
}

func TestUnsupportedOn_IgnoresCaseAndSurroundingSpace(t *testing.T) {
	// Hand-written template.toml files should not fail silently over " ARM64".
	tmpl := &Template{Name: "x", UnsupportedArch: []string{" ARM64 "}}
	assert.True(t, tmpl.UnsupportedOn("arm64"))
}

// --- loading from template.toml ---

func TestLoadTemplate_ReadsUnsupportedArchKeys(t *testing.T) {
	dir := t.TempDir()
	tmplDir := filepath.Join(dir, "google-chrome")
	require.NoError(t, os.MkdirAll(tmplDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "template.toml"), []byte(`
display-name = "Google Chrome"
unsupported-arch = ["arm64"]
unsupported-arch-note = "No linux/arm64 build. Use chromium."
`), 0o644))

	tmpl, err := loadTemplateDir(tmplDir, "google-chrome", "browsers", true)
	require.NoError(t, err)
	require.NotNil(t, tmpl)
	assert.Equal(t, []string{"arm64"}, tmpl.UnsupportedArch)
	assert.Equal(t, "No linux/arm64 build. Use chromium.", tmpl.UnsupportedArchNote)
	assert.True(t, tmpl.UnsupportedOn("arm64"))
}

func TestLoadTemplate_UnsupportedArchDefaultsToEmpty(t *testing.T) {
	dir := t.TempDir()
	tmplDir := filepath.Join(dir, "chromium")
	require.NoError(t, os.MkdirAll(tmplDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "template.toml"),
		[]byte(`display-name = "Chromium"`+"\n"), 0o644))

	tmpl, err := loadTemplateDir(tmplDir, "chromium", "browsers", true)
	require.NoError(t, err)
	require.NotNil(t, tmpl)
	assert.Empty(t, tmpl.UnsupportedArch)
	assert.False(t, tmpl.UnsupportedOn("arm64"))
}

// --- FormatTemplateDetail ---

func TestFormatTemplateDetail_ShowsArchWarningOnAffectedHost(t *testing.T) {
	tmpl := &Template{
		Name:                "google-chrome",
		DisplayName:         "Google Chrome",
		CategoryName:        "browsers",
		UnsupportedArch:     []string{HostArch()},
		UnsupportedArchNote: "No build here. Use chromium instead.",
	}
	var buf bytes.Buffer
	FormatTemplateDetail(&buf, tmpl, &TemplateRegistry{}, false)

	out := buf.String()
	assert.Contains(t, out, "Not available on "+HostArch())
	assert.Contains(t, out, "Use chromium instead.")
}

func TestFormatTemplateDetail_NoArchWarningWhenSupported(t *testing.T) {
	tmpl := &Template{
		Name:         "chromium",
		DisplayName:  "Chromium",
		CategoryName: "browsers",
		// Some architecture that is definitely not this host.
		UnsupportedArch: []string{"s390x"},
	}
	var buf bytes.Buffer
	FormatTemplateDetail(&buf, tmpl, &TemplateRegistry{}, false)

	assert.NotContains(t, buf.String(), "Not available on")
}

func TestFormatTemplateDetail_FallsBackWhenNoteMissing(t *testing.T) {
	// A template.toml that lists the arch but forgets the note still has to say
	// something useful rather than printing an empty warning block.
	tmpl := &Template{
		Name:            "google-chrome",
		DisplayName:     "Google Chrome",
		CategoryName:    "browsers",
		UnsupportedArch: []string{HostArch()},
	}
	var buf bytes.Buffer
	FormatTemplateDetail(&buf, tmpl, &TemplateRegistry{}, false)

	out := buf.String()
	assert.Contains(t, out, "Not available on "+HostArch())
	assert.Contains(t, out, "will not be installed")
}
