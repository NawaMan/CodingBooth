// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"bytes"
	"encoding/json"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

func TestBuildCatalog_TabsComeFromRegistry(t *testing.T) {
	auto := true
	linter := &tmpl.Template{
		Name:        "linter",
		DisplayName: "Go Linter",
		AutoSelect:  &auto,
	}
	goTmpl := &tmpl.Template{
		Name:        "go",
		DisplayName: "Go",
		DisplayDesc: "Go toolchain",
		Primary:     true,
		Params:      map[string]tmpl.Param{"GO_VERSION": {Default: "1.25.7", Suggests: []string{"1.24", "1.25.7"}}},
		ParamOrder:  []string{"GO_VERSION"},
		Extensions:  []*tmpl.Template{linter},
	}
	registry := &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{
			Name:        "languages",
			DisplayName: "Languages",
			Templates:   []*tmpl.Template{goTmpl},
		}},
		ByName: map[string]*tmpl.Template{"go": goTmpl},
	}

	catalog := BuildCatalog(registry, "amd64")
	if len(catalog.Categories) != 1 {
		t.Fatalf("categories = %d, want 1", len(catalog.Categories))
	}
	if catalog.Categories[0].DisplayName != "Languages" {
		t.Fatalf("tab = %q, want Languages", catalog.Categories[0].DisplayName)
	}
	if len(catalog.Categories[0].Templates) != 1 || catalog.Categories[0].Templates[0].Name != "go" {
		t.Fatalf("templates = %+v", catalog.Categories[0].Templates)
	}
	got := catalog.Categories[0].Templates[0]
	if !got.Primary {
		t.Fatal("go should be primary")
	}
	if len(got.Extensions) != 1 || got.Extensions[0].Name != "linter" || !got.Extensions[0].AutoSelect {
		t.Fatalf("extensions = %+v", got.Extensions)
	}
	if len(got.Params) != 1 || got.Params[0].Name != "GO_VERSION" || got.Params[0].Default != "1.25.7" {
		t.Fatalf("params = %+v", got.Params)
	}
}

func TestBuildCatalog_JSONAlwaysIncludesExtensions(t *testing.T) {
	bare := &tmpl.Template{Name: "sqlite", DisplayName: "SQLite"}
	registry := &tmpl.TemplateRegistry{
		Categories: []*tmpl.Category{{
			Name: "middlewares", DisplayName: "Middlewares",
			Templates: []*tmpl.Template{bare},
		}},
		ByName: map[string]*tmpl.Template{"sqlite": bare},
	}
	raw, err := json.Marshal(BuildCatalog(registry, "amd64"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(raw, []byte(`"extensions":[]`)) {
		t.Fatalf("JSON omitted extensions: %s", raw)
	}
}
