// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"reflect"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// aptItem builds a treeItem + template for a standalone variadic-param template
// (one variadic param, like apt-pkg's APT_PKGS).
func aptItem() (treeItem, *tmpl.Template) {
	t := &tmpl.Template{
		Name:       "apt-pkg",
		Params:     map[string]tmpl.Param{"APT_PKGS": {Default: "", Variadic: true}},
		ParamOrder: []string{"APT_PKGS"},
	}
	return treeItem{kind: kindTemplate, template: t}, t
}

func TestSplitJoinVariadic(t *testing.T) {
	m := &model{paramValues: map[string]string{}}
	pk := "apt-pkg:APT_PKGS"

	if got := m.splitVariadic(pk); got != nil {
		t.Fatalf("empty should split to nil, got %v", got)
	}

	// Blanks and surrounding spaces are dropped on read.
	m.paramValues[pk] = "htop, , jq ,"
	if got := m.splitVariadic(pk); !reflect.DeepEqual(got, []string{"htop", "jq"}) {
		t.Fatalf("split mismatch: %v", got)
	}

	// Join drops blanks and re-comma-joins.
	m.joinVariadic(pk, []string{"a", "", "  ", "b"})
	if got := m.paramValues[pk]; got != "a,b" {
		t.Fatalf("join mismatch: %q", got)
	}

	// Empty list removes the key entirely (round-trips as default).
	m.joinVariadic(pk, []string{"", " "})
	if _, ok := m.paramValues[pk]; ok {
		t.Fatalf("empty join should delete the key")
	}
}

func TestBuildParamRows(t *testing.T) {
	item, tpl := aptItem()
	m := &model{paramValues: map[string]string{"apt-pkg:APT_PKGS": "htop,jq"}}

	rows := m.buildParamRows(item, tpl)
	// Two value rows + one add row.
	if len(rows) != 3 {
		t.Fatalf("want 3 rows, got %d: %+v", len(rows), rows)
	}
	if rows[0].kind != paramRowVariadicValue || rows[0].valueIdx != 0 {
		t.Fatalf("row 0 = %+v", rows[0])
	}
	if rows[1].kind != paramRowVariadicValue || rows[1].valueIdx != 1 {
		t.Fatalf("row 1 = %+v", rows[1])
	}
	if rows[2].kind != paramRowVariadicAdd {
		t.Fatalf("row 2 = %+v", rows[2])
	}

	// Empty variadic param yields just the add row.
	m.paramValues["apt-pkg:APT_PKGS"] = ""
	rows = m.buildParamRows(item, tpl)
	if len(rows) != 1 || rows[0].kind != paramRowVariadicAdd {
		t.Fatalf("empty variadic should be a single add row, got %+v", rows)
	}
}

func TestVariadicAddCommit(t *testing.T) {
	pk := "apt-pkg:APT_PKGS"
	m := &model{paramValues: map[string]string{}}

	// Add "htop": begin on the add row (idx 0), commit.
	m.beginVariadicEdit(pk, 0, "", true)
	m.variadicEditBuf = "htop"
	m.commitVariadicEdit()
	if m.paramValues[pk] != "htop" {
		t.Fatalf("after first add: %q", m.paramValues[pk])
	}
	// Cursor should land back on the trailing add row (index 1 now).
	if m.paramCursorIdx != 1 {
		t.Fatalf("cursor should be on add row (1), got %d", m.paramCursorIdx)
	}

	// Add "jq" from the add row.
	m.beginVariadicEdit(pk, len(m.splitVariadic(pk)), "", true)
	m.variadicEditBuf = "jq"
	m.commitVariadicEdit()
	if m.paramValues[pk] != "htop,jq" {
		t.Fatalf("after second add: %q", m.paramValues[pk])
	}
}

func TestVariadicEditAndCancel(t *testing.T) {
	pk := "apt-pkg:APT_PKGS"
	m := &model{paramValues: map[string]string{pk: "htop,jq"}}

	// Edit value at index 0 → "vim".
	m.beginVariadicEdit(pk, 0, "htop", false)
	m.variadicEditBuf = "vim"
	m.commitVariadicEdit()
	if m.paramValues[pk] != "vim,jq" {
		t.Fatalf("after edit: %q", m.paramValues[pk])
	}

	// Begin adding a new value but cancel → unchanged.
	m.beginVariadicEdit(pk, len(m.splitVariadic(pk)), "", true)
	m.variadicEditBuf = "discarded"
	m.endVariadicEdit() // simulates ESC
	if m.paramValues[pk] != "vim,jq" {
		t.Fatalf("cancel should not add: %q", m.paramValues[pk])
	}
	if m.variadicEditing {
		t.Fatalf("variadicEditing should be cleared after cancel")
	}
}
