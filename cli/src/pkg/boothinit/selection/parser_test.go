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
	assert.Equal(t, []ParsedExtension{{Name: "linter"}}, sel.Items[0].Extensions)
}

func TestParseSelectDSL_WithParamsAndExtension(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24+linter")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, []string{"1.24"}, sel.Items[0].Params)
	assert.Equal(t, []ParsedExtension{{Name: "linter"}}, sel.Items[0].Extensions)
}

func TestParseSelectDSL_MultipleExtensions(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24+linter+proxy")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, []ParsedExtension{{Name: "linter"}, {Name: "proxy"}}, sel.Items[0].Extensions)
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
	assert.Equal(t, []ParsedExtension{{Name: "linter"}}, sel.Items[0].Extensions)

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

// --- NormalizeInput with ~ ---

func TestNormalizeInput_SpacesAroundTilde(t *testing.T) {
	assert.Equal(t, "firebase~credential", NormalizeInput("firebase ~ credential"))
}

func TestNormalizeInput_SpacesAroundTildeWithExtensions(t *testing.T) {
	assert.Equal(t, "claude-code+accept-edits~credential", NormalizeInput("claude-code + accept-edits ~ credential"))
}

func TestNormalizeInput_TildeContinuationLine(t *testing.T) {
	input := "firebase\n  ~ credential"
	assert.Equal(t, "firebase~credential", NormalizeInput(input))
}

// --- ParseSelectDSL with ~ ---

func TestParseSelectDSL_WithExclude(t *testing.T) {
	sel, err := ParseSelectDSL("firebase~credential")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "firebase", sel.Items[0].Name)
	assert.Equal(t, []string{"credential"}, sel.Items[0].Excludes)
	assert.Empty(t, sel.Items[0].Extensions)
}

func TestParseSelectDSL_WithExtensionAndExclude(t *testing.T) {
	sel, err := ParseSelectDSL("claude-code+accept-edits~credential")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "claude-code", sel.Items[0].Name)
	assert.Equal(t, []ParsedExtension{{Name: "accept-edits"}}, sel.Items[0].Extensions)
	assert.Equal(t, []string{"credential"}, sel.Items[0].Excludes)
}

func TestParseSelectDSL_MultipleExcludes(t *testing.T) {
	sel, err := ParseSelectDSL("foo~bar~baz")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "foo", sel.Items[0].Name)
	assert.Equal(t, []string{"bar", "baz"}, sel.Items[0].Excludes)
}

func TestParseSelectDSL_EmptyExclude(t *testing.T) {
	_, err := ParseSelectDSL("firebase~")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "empty exclusion")
}

func TestParseSelectDSL_ExcludeInComplexDSL(t *testing.T) {
	sel, err := ParseSelectDSL("go:1.24+linter/firebase~credential/claude-code")
	require.NoError(t, err)
	require.Len(t, sel.Items, 3)
	assert.Equal(t, "go", sel.Items[0].Name)
	assert.Equal(t, []ParsedExtension{{Name: "linter"}}, sel.Items[0].Extensions)
	assert.Empty(t, sel.Items[0].Excludes)
	assert.Equal(t, "firebase", sel.Items[1].Name)
	assert.Equal(t, []string{"credential"}, sel.Items[1].Excludes)
	assert.Equal(t, "claude-code", sel.Items[2].Name)
	assert.Empty(t, sel.Items[2].Excludes)
}

// --- ParseSelectDSL with extension params ---

func TestParseSelectDSL_ExtensionWithParams(t *testing.T) {
	sel, err := ParseSelectDSL("deno+pkg:cowsay,figlet")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "deno", sel.Items[0].Name)
	require.Len(t, sel.Items[0].Extensions, 1)
	assert.Equal(t, "pkg", sel.Items[0].Extensions[0].Name)
	assert.Equal(t, []string{"cowsay", "figlet"}, sel.Items[0].Extensions[0].Params)
}

func TestParseSelectDSL_ExtensionWithSingleParam(t *testing.T) {
	sel, err := ParseSelectDSL("deno+pkg:cowsay")
	require.NoError(t, err)
	require.Len(t, sel.Items[0].Extensions, 1)
	assert.Equal(t, "pkg", sel.Items[0].Extensions[0].Name)
	assert.Equal(t, []string{"cowsay"}, sel.Items[0].Extensions[0].Params)
}

func TestParseSelectDSL_ExtensionEmptyParams(t *testing.T) {
	sel, err := ParseSelectDSL("deno+pkg:")
	require.NoError(t, err)
	assert.Equal(t, "pkg", sel.Items[0].Extensions[0].Name)
	assert.Empty(t, sel.Items[0].Extensions[0].Params)
}

func TestParseSelectDSL_MixedExtensionsWithAndWithoutParams(t *testing.T) {
	sel, err := ParseSelectDSL("deno+pkg:cowsay,figlet+vscode-ext")
	require.NoError(t, err)
	require.Len(t, sel.Items[0].Extensions, 2)
	assert.Equal(t, "pkg", sel.Items[0].Extensions[0].Name)
	assert.Equal(t, []string{"cowsay", "figlet"}, sel.Items[0].Extensions[0].Params)
	assert.Equal(t, "vscode-ext", sel.Items[0].Extensions[1].Name)
	assert.Empty(t, sel.Items[0].Extensions[1].Params)
}

func TestParseSelectDSL_TemplateParamsAndExtensionParams(t *testing.T) {
	sel, err := ParseSelectDSL("java:21+maven:4.0")
	require.NoError(t, err)
	require.Len(t, sel.Items, 1)
	assert.Equal(t, "java", sel.Items[0].Name)
	assert.Equal(t, []string{"21"}, sel.Items[0].Params)
	require.Len(t, sel.Items[0].Extensions, 1)
	assert.Equal(t, "maven", sel.Items[0].Extensions[0].Name)
	assert.Equal(t, []string{"4.0"}, sel.Items[0].Extensions[0].Params)
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

func TestReadSelectInput_ProjectRecipeBareName(t *testing.T) {
	project := t.TempDir()
	recipes := filepath.Join(project, ".booth", "recipes")
	require.NoError(t, os.MkdirAll(recipes, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(recipes, "fullstack.recipe"), []byte("go\npython\n"), 0644))

	result, err := ReadSelectInputWithProject("@fullstack", project)
	require.NoError(t, err)
	assert.Equal(t, "go\npython\n", result)

	// Explicit .recipe suffix also works
	result, err = ReadSelectInputWithProject("@fullstack.recipe", project)
	require.NoError(t, err)
	assert.Equal(t, "go\npython\n", result)
}

func TestReadSelectInput_ProjectRecipeMissing(t *testing.T) {
	project := t.TempDir()
	_, err := ReadSelectInputWithProject("@missing", project)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "recipe \"missing\" not found")
	assert.Contains(t, err.Error(), filepath.Join(project, ".booth", "recipes", "missing.recipe"))
}

func TestReadSelectInput_RelativePathStillWorks(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "custom.recipe")
	require.NoError(t, os.WriteFile(filePath, []byte("rust\n"), 0644))

	// Explicit path forms bypass .booth/recipes/
	result, err := ReadSelectInputWithProject("@"+filePath, t.TempDir())
	require.NoError(t, err)
	assert.Equal(t, "rust\n", result)
}

func TestNormalizeRecipeURL(t *testing.T) {
	assert.Equal(t, "https://codingbooth.io/r.recipe", normalizeRecipeURL("codingbooth.io/r.recipe"))
	assert.Equal(t, "https://codingbooth.io/r.recipe", normalizeRecipeURL("https://codingbooth.io/r.recipe"))
	assert.Equal(t, "http://example.com/x", normalizeRecipeURL("http://example.com/x"))
}

func TestIsPathShaped(t *testing.T) {
	assert.True(t, isPathShaped("/abs/path"))
	assert.True(t, isPathShaped("./rel"))
	assert.True(t, isPathShaped("../up"))
	assert.True(t, isPathShaped("~/home"))
	assert.True(t, isPathShaped("C:\\Windows\\r.recipe"))
	assert.True(t, isPathShaped("D:/booth/r.recipe"))
	assert.True(t, isPathShaped("https://example.com/r.recipe"))
	assert.False(t, isPathShaped("fullstack"))
	assert.False(t, isPathShaped("fullstack.recipe"))
	assert.False(t, isPathShaped("team/api"))
}

func TestEnsureRecipeSuffix(t *testing.T) {
	assert.Equal(t, "fullstack.recipe", ensureRecipeSuffix("fullstack"))
	assert.Equal(t, "fullstack.recipe", ensureRecipeSuffix("fullstack.recipe"))
	assert.Equal(t, "team/api.recipe", ensureRecipeSuffix("team/api"))
}

// --- "+" inside a param value (booth-relative ports, packages with a "+") ---

func TestParse_ExtensionParamCarriesRelativePort(t *testing.T) {
	// "+4567" is an offset from the booth port, resolved at container start. The "+" must
	// survive the extension split — it used to be read as an extension named "4567".
	parsed, err := ParseSelectDSL("rabbitmq+start+expose:+4567")
	require.NoError(t, err)
	require.Len(t, parsed.Items, 1)

	item := parsed.Items[0]
	assert.Equal(t, "rabbitmq", item.Name)
	require.Len(t, item.Extensions, 2)
	assert.Equal(t, "start", item.Extensions[0].Name)
	assert.Equal(t, "expose", item.Extensions[1].Name)
	assert.Equal(t, []string{"+4567"}, item.Extensions[1].Params)
}

func TestParse_RelativeAndAbsolutePortsCoexist(t *testing.T) {
	parsed, err := ParseSelectDSL("cloudbeaver:25.3.5,9000+expose:19000")
	require.NoError(t, err)

	item := parsed.Items[0]
	assert.Equal(t, []string{"25.3.5", "9000"}, item.Params)
	require.Len(t, item.Extensions, 1)
	assert.Equal(t, "expose", item.Extensions[0].Name)
	assert.Equal(t, []string{"19000"}, item.Extensions[0].Params, "a bare number stays an absolute host port")
}

func TestParse_ExtensionAfterRelativePortParam(t *testing.T) {
	// A "+" followed by a letter is still an extension, even inside a param list.
	parsed, err := ParseSelectDSL("rabbitmq+expose:+4567+start")
	require.NoError(t, err)

	item := parsed.Items[0]
	require.Len(t, item.Extensions, 2)
	assert.Equal(t, "expose", item.Extensions[0].Name)
	assert.Equal(t, []string{"+4567"}, item.Extensions[0].Params)
	assert.Equal(t, "start", item.Extensions[1].Name)
}

func TestParse_TemplateParamCarriesPlus(t *testing.T) {
	// Falls out of the same rule: a package name containing "+" used to be unparseable.
	parsed, err := ParseSelectDSL("apt-pkg:libstdc++6")
	require.NoError(t, err)

	item := parsed.Items[0]
	assert.Equal(t, "apt-pkg", item.Name)
	assert.Equal(t, []string{"libstdc++6"}, item.Params)
	assert.Empty(t, item.Extensions)
}

func TestParse_MalformedPlusStillErrors(t *testing.T) {
	// Before a ":" opens a param list, every "+" separates — so these keep reporting an
	// empty extension name rather than being swallowed into a template name.
	for _, dsl := range []string{"go++linter", "go+"} {
		_, err := ParseSelectDSL(dsl)
		require.Error(t, err, "%q must not parse", dsl)
		assert.Contains(t, err.Error(), "empty extension name", "%q", dsl)
	}
}
