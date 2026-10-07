// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseSelectDSL_RecipeComments(t *testing.T) {
	parsed, err := ParseSelectDSL("# desk setup\npython:3.13 # pin\n  + uv\n")
	require.NoError(t, err)
	require.Len(t, parsed.Items, 1)
	assert.Equal(t, "python", parsed.Items[0].Name)
	assert.Equal(t, []string{"3.13"}, parsed.Items[0].Params)
	require.Len(t, parsed.Items[0].Extensions, 1)
	assert.Equal(t, "uv", parsed.Items[0].Extensions[0].Name)
}

func TestParseSelectDSL_HashInsideQuotesStays(t *testing.T) {
	parsed, err := ParseSelectDSL(`go+go-pkg:"foo#bar"`)
	require.NoError(t, err)
	require.Len(t, parsed.Items, 1)
	require.Len(t, parsed.Items[0].Extensions, 1)
	assert.Equal(t, []string{"foo#bar"}, parsed.Items[0].Extensions[0].Params)
}
