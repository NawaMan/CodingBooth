// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"reflect"
	"strings"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// exposeModel models "svc" (with SVC_PORT) plus its expose extension, whose host-port
// param defaults to "${SVC_PORT}" so it follows the port the service listens on.
func exposeModel(svcPort, hostPort string) (model, treeItem, *tmpl.Template) {
	svc := &tmpl.Template{
		Name:       "svc",
		Params:     map[string]tmpl.Param{"SVC_PORT": {Default: "8080"}},
		ParamOrder: []string{"SVC_PORT"},
	}
	ext := &tmpl.Template{
		Name:       "expose",
		Params:     map[string]tmpl.Param{"SVC_HOST_PORT": {Default: "${SVC_PORT}"}},
		ParamOrder: []string{"SVC_HOST_PORT"},
	}
	m := model{paramValues: map[string]string{
		"svc:SVC_PORT":             svcPort,
		"svc/expose:SVC_HOST_PORT": hostPort,
	}}
	return m, treeItem{kind: kindExtension, template: svc, extension: ext}, ext
}

func TestParamDisplay_ResolvesReference(t *testing.T) {
	m, _, _ := exposeModel("8080", "${SVC_PORT}")

	display, follows := m.paramDisplay("${SVC_PORT}")
	if display != "8080" {
		t.Errorf("display = %q, want %q", display, "8080")
	}
	if !reflect.DeepEqual(follows, []string{"SVC_PORT"}) {
		t.Errorf("follows = %v, want [SVC_PORT]", follows)
	}
	if got := followsHint(follows); got != " (follows SVC_PORT)" {
		t.Errorf("followsHint = %q", got)
	}
}

func TestParamDisplay_TracksServicePortChange(t *testing.T) {
	// The point of the whole exercise: move the service port, and the host port shown
	// for the expose extension moves with it.
	m, _, _ := exposeModel("80", "${SVC_PORT}")

	display, _ := m.paramDisplay("${SVC_PORT}")
	if display != "80" {
		t.Errorf("display = %q, want %q", display, "80")
	}
}

func TestParamDisplay_PinnedValueShownAsIs(t *testing.T) {
	m, _, _ := exposeModel("80", "10080")

	display, follows := m.paramDisplay("10080")
	if display != "10080" || follows != nil {
		t.Errorf("display = %q, follows = %v; want 10080 / nil", display, follows)
	}
}

func TestParamDisplay_UnknownRefLeftRaw(t *testing.T) {
	// ${HOME} is not a param — it belongs to the shell at runtime, so it must not be
	// resolved away or reported as followed.
	m, _, _ := exposeModel("8080", "${SVC_PORT}")

	display, follows := m.paramDisplay("${HOME}/data")
	if display != "${HOME}/data" || follows != nil {
		t.Errorf("display = %q, follows = %v; want ${HOME}/data / nil", display, follows)
	}
}

func TestParamDisplay_CycleFallsBackToRaw(t *testing.T) {
	// A circular default must not hang or panic the TUI; the compiler reports it on save.
	m := model{paramValues: map[string]string{"svc:A": "${B}", "svc:B": "${A}"}}

	display, follows := m.paramDisplay("${A}")
	if display != "${A}" || follows != nil {
		t.Errorf("display = %q, follows = %v; want raw ${A} / nil", display, follows)
	}
}

func TestRenderParamFieldRow_ShowsResolvedNotRaw(t *testing.T) {
	m, item, ext := exposeModel("80", "${SVC_PORT}")

	row := m.renderParamFieldRow(ext, "SVC_HOST_PORT", paramKey(item, "SVC_HOST_PORT"), false)
	if !strings.Contains(row, "80") {
		t.Errorf("row should show the resolved port, got %q", row)
	}
	if strings.Contains(row, "${SVC_PORT}") {
		t.Errorf("row should not show the raw reference, got %q", row)
	}
	if !strings.Contains(row, "follows SVC_PORT") {
		t.Errorf("row should say what it follows, got %q", row)
	}
}

func TestRenderParamFieldRow_EditingShowsRawReference(t *testing.T) {
	// While editing, the reference itself is what the user is editing — hiding it would
	// mean they cannot keep the link, only overwrite it.
	m, item, ext := exposeModel("80", "${SVC_PORT}")
	pk := paramKey(item, "SVC_HOST_PORT")
	m.paramEditing = true
	m.paramEditKey = pk

	row := m.renderParamFieldRow(ext, "SVC_HOST_PORT", pk, true)
	if !strings.Contains(row, "${SVC_PORT}") {
		t.Errorf("edit mode should show the raw reference, got %q", row)
	}
}

func TestRenderParamFieldRow_FollowedValueIsNotCustom(t *testing.T) {
	// With suggests present, a followed value is not a hand-typed "(custom)" value.
	m, item, ext := exposeModel("80", "${SVC_PORT}")
	ext.Params["SVC_HOST_PORT"] = tmpl.Param{
		Default:  "${SVC_PORT}",
		Suggests: []string{"8080", "18080"},
	}

	row := m.renderParamFieldRow(ext, "SVC_HOST_PORT", paramKey(item, "SVC_HOST_PORT"), false)
	if strings.Contains(row, "(custom)") {
		t.Errorf("followed value should not be labelled custom, got %q", row)
	}
	if !strings.Contains(row, "follows SVC_PORT") {
		t.Errorf("row should say what it follows, got %q", row)
	}
}

func TestRenderParamValues_ResolvesReference(t *testing.T) {
	m, item, ext := exposeModel("80", "${SVC_PORT}")

	lines := m.renderParamValues(nil, item, ext)
	joined := strings.Join(lines, "\n")
	if !strings.Contains(joined, "SVC_HOST_PORT = 80 (follows SVC_PORT)") {
		t.Errorf("read-only view should resolve the reference, got %q", joined)
	}
}
