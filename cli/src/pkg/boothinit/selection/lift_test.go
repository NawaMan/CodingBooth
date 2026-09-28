// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func liftRegistry() *tmpl.TemplateRegistry {
	pkg := &tmpl.Template{
		Name:       "pkg",
		Params:     map[string]tmpl.Param{"PKGS": {Variadic: true}},
		ParamOrder: []string{"PKGS"},
	}
	goTmpl := &tmpl.Template{
		Name: "go",
		Params: map[string]tmpl.Param{
			"GO_VERSION": {Default: "1.26.8"},
			"GO_ARCH":    {Default: "amd64"},
		},
		ParamOrder: []string{"GO_VERSION", "GO_ARCH"},
		Extensions: []*tmpl.Template{pkg},
	}
	return &tmpl.TemplateRegistry{ByName: map[string]*tmpl.Template{"go": goTmpl}}
}

func lift(t *testing.T, dsl string, args map[string]string) (string, bool) {
	t.Helper()
	parsed, err := ParseSelectDSL(dsl)
	require.NoError(t, err)
	changed := LiftParams(parsed, liftRegistry(), args)
	return SerializeSelection(parsed), changed
}

func TestLiftParams_ExplicitParamTakesTheArgValue(t *testing.T) {
	got, changed := lift(t, "go:1.25", map[string]string{"GO_VERSION": "1.26.1", "GO_ARCH": "amd64"})
	assert.True(t, changed)
	assert.Equal(t, "go:1.26.1", got)
}

func TestLiftParams_MatchingArgsChangeNothing(t *testing.T) {
	got, changed := lift(t, "go:1.25", map[string]string{"GO_VERSION": "1.25"})
	assert.False(t, changed)
	assert.Equal(t, "go:1.25", got)
}

// An unset param already follows the Boothfile through the resolver's overrides;
// writing it into the selection would turn a followed value into a pin.
func TestLiftParams_UnsetParamIsLeftToTheResolver(t *testing.T) {
	got, changed := lift(t, "go", map[string]string{"GO_VERSION": "1.26.1"})
	assert.False(t, changed)
	assert.Equal(t, "go", got)
}

func TestLiftParams_ExtensionVariadicComparesCanonically(t *testing.T) {
	got, changed := lift(t, "go+pkg:b,a", map[string]string{"PKGS": "a,b"})
	assert.False(t, changed, "the arg holds the sorted join; b,a is the same list")
	assert.Equal(t, "go+pkg:b,a", got)

	got, changed = lift(t, "go+pkg:b,a", map[string]string{"PKGS": "a,b,c"})
	assert.True(t, changed)
	assert.Equal(t, "go+pkg:a,b,c", got)
}
