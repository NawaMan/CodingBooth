// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package compiler

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCompile_OwnerPermissionMergedAndConflict(t *testing.T) {
	pip := &tmpl.Template{Name: "pip-cache", OwnerPerms: []tmpl.OwnerPerm{{
		Path: "/opt/pip-cache", User: "coder", Group: "coder", Mode: "1777",
	}}}
	same := &tmpl.Template{Name: "other", OwnerPerms: []tmpl.OwnerPerm{{
		Path: "/opt/pip-cache", User: "coder", Group: "coder", Mode: "1777",
	}}}
	out, err := Compile(&selection.ResolvedSelection{Templates: []selection.SelectedTemplate{{
		Template:   &tmpl.Template{Name: "python"},
		Extensions: []selection.SelectedExtension{{Extension: pip}, {Extension: same}},
	}}})
	require.NoError(t, err)
	require.Len(t, out.OwnerPerms, 1)
	assert.Equal(t, output.OwnerPerm{Path: "/opt/pip-cache", User: "coder", Group: "coder", Mode: "1777"}, out.OwnerPerms[0])

	clash := &tmpl.Template{Name: "other", OwnerPerms: []tmpl.OwnerPerm{{
		Path: "/opt/pip-cache", User: "root", Group: "root", Mode: "0755",
	}}}
	_, err = Compile(&selection.ResolvedSelection{Templates: []selection.SelectedTemplate{{
		Template:   &tmpl.Template{Name: "python"},
		Extensions: []selection.SelectedExtension{{Extension: pip}, {Extension: clash}},
	}}})
	assert.ErrorContains(t, err, "conflicting owner-permission")
}
