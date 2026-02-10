// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- NormalizeInput ---

func TestNormalizeInput_Simple(t *testing.T) {
	assert.Equal(t, "go/python", NormalizeInput("go/python"))
}

func TestNormalizeInput_Whitespace(t *testing.T) {
	assert.Equal(t, "go/python", NormalizeInput("  go   python  "))
}

func TestNormalizeInput_Newlines(t *testing.T) {
	assert.Equal(t, "go:1.24/java:21,corretto", NormalizeInput("go:1.24\njava:21,corretto"))
}

func TestNormalizeInput_MixedWhitespace(t *testing.T) {
	assert.Equal(t, "go/python/java", NormalizeInput("go\n  python\n\tjava\n"))
}

func TestNormalizeInput_Empty(t *testing.T) {
	assert.Equal(t, "", NormalizeInput("   "))
}

func TestNormalizeInput_PreservesSlash(t *testing.T) {
	assert.Equal(t, "go/python", NormalizeInput("go/python"))
}

func TestNormalizeInput_SpacesAroundPlus(t *testing.T) {
	assert.Equal(t, "java+maven+gradle", NormalizeInput("java + maven + gradle"))
}

func TestNormalizeInput_SpacesAroundPlusWithParams(t *testing.T) {
	assert.Equal(t, "java:25,openjdk+maven+vscode-ext", NormalizeInput("java:25,openjdk + maven + vscode-ext"))
}

func TestNormalizeInput_SpacesAroundPlusMultiline(t *testing.T) {
	assert.Equal(t, "go/java:25+maven", NormalizeInput("go\njava:25 + maven"))
}

func TestNormalizeInput_PlusContinuationLine(t *testing.T) {
	input := "go\njava:25,temurin\n  + maven"
	assert.Equal(t, "go/java:25,temurin+maven", NormalizeInput(input))
}

func TestNormalizeInput_MultipleContinuationLines(t *testing.T) {
	input := "java:25\n  + maven\n  + vscode-ext"
	assert.Equal(t, "java:25+maven+vscode-ext", NormalizeInput(input))
}

// --- ParseSelectDSL ---

func TestParseSelectDSL_SingleTemplate(t *testing.T) {
	sel, err := ParseSelectDSL("go")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Empty(t, sel.Items[0].Params)
	assert.Empty(t, sel.Items[0].Extensions)
}

func TestParseSelectDSL_WithParams(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, []string{"1.24"}, sel.Items[0].Params)
}

func TestParseSelectDSL_MultipleParams(t *testing.T) {
	sel, err := ParseSelectDSL("java:21,corretto")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "java", sel.Items[0].Name)
	assert.Equal(t, []string{"21", "corretto"}, sel.Items[0].Params)
}

func TestParseSelectDSL_WithExtension(t *testing.T) {
	sel, err := ParseSelectDSL("go+linter")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, []string{"linter"}, sel.Items[0].Extensions)
}

func TestParseSelectDSL_WithParamsAndExtension(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24+linter")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, []string{"1.24"}, sel.Items[0].Params)
	assert.Equal(t, []string{"linter"}, sel.Items[0].Extensions)
}

func TestParseSelectDSL_MultipleExtensions(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24+linter+proxy")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, []string{"linter", "proxy"}, sel.Items[0].Extensions)
}

func TestParseSelectDSL_MultipleTemplates(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24/python:3.12")
	require.NoError(t, err)
	require.Len(t, sel.Items, 2)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, []string{"1.24"}, sel.Items[0].Params)
	assert.Equal(t, "python", sel.Items[1].Name)
	assert.Equal(t, []string{"3.12"}, sel.Items[1].Params)
}

func TestParseSelectDSL_ComplexDSL(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24+linter/python:3.12/claude-code")
	require.NoError(t, err)
	require.Len(t, sel.Items, 3)

	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, []string{"1.24"}, sel.Items[0].Params)
	assert.Equal(t, []string{"linter"}, sel.Items[0].Extensions)

	assert.Equal(t, "python", sel.Items[1].Name)
	assert.Equal(t, []string{"3.12"}, sel.Items[1].Params)

	assert.Equal(t, "claude-code", sel.Items[2].Name)
	assert.Empty(t, sel.Items[2].Params)
}

func TestParseSelectDSL_HeredocInput(t *testing.T) {
	input := `
  go:1.24
  python:3.12
  claude-code
`
	sel, err := ParseSelectDSL(input)
	require.NoError(t, err)
	require.Len(t, sel.Items, 3)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, "python", sel.Items[1].Name)
	assert.Equal(t, "claude-code", sel.Items[2].Name)
}

func TestParseSelectDSL_EmptyColonParams(t *testing.T) {
	sel, err := ParseSelectDSL("go:")
	require.NoError(t, err)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Empty(t, sel.Items[0].Params)
}

func TestParseSelectDSL_EmptyInput(t *testing.T) {
	_, err := ParseSelectDSL("")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "empty selection")
}

func TestParseSelectDSL_WhitespaceOnly(t *testing.T) {
	_, err := ParseSelectDSL("   \n\n  ")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "empty selection")
}

func TestParseSelectDSL_EmptyExtension(t *testing.T) {
	_, err := ParseSelectDSL("go+")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "empty extension")
}

func TestParseSelectDSL_EmptyTemplateName(t *testing.T) {
	_, err := ParseSelectDSL(":1.24")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "empty template name")
}

// --- ReadSelectInput ---

func TestReadSelectInput_PlainString(t *testing.T) {
	result, err := ReadSelectInput("go/python")
	require.NoError(t, err)
	assert.Equal(t, "go/python", result)
}

func TestReadSelectInput_FromFile(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "selection.txt")
	require.NoError(t, os.WriteFile(filePath, []byte("go:1.24\npython:3.12\n"), 0644))

	result, err := ReadSelectInput("@" + filePath)
	require.NoError(t, err)
	assert.Equal(t, "go:1.24\npython:3.12\n", result)
}

func TestReadSelectInput_FileNotFound(t *testing.T) {
	_, err := ReadSelectInput("@/nonexistent/file.txt")
	assert.Error(t, err)
}

func TestReadSelectInput_FromURL(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "go:1.24\npython:3.12\n")
	}))
	defer server.Close()

	result, err := ReadSelectInput("@@" + server.URL)
	require.NoError(t, err)
	assert.Equal(t, "go:1.24\npython:3.12\n", result)
}

func TestReadSelectInput_URLNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.NotFound(w, r)
	}))
	defer server.Close()

	_, err := ReadSelectInput("@@" + server.URL + "/missing")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "HTTP 404")
}

func TestReadSelectInput_URLUnreachable(t *testing.T) {
	_, err := ReadSelectInput("@@http://127.0.0.1:1/nonexistent")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "fetching selection URL")
}
