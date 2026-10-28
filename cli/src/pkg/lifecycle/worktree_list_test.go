// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/gitworktree"
	"github.com/stretchr/testify/assert"
)

func TestJoinWorktreeBooths(t *testing.T) {
	entries := []gitworktree.Entry{
		{Path: "/r/main", Branch: "main"},
		{Path: "/r/wt/a", Branch: "feature/a"},
		{Path: "/r/wt/b", Branch: "b"},
		{Path: "/r/bare", Bare: true},
		{Path: "/r/gone", Branch: "gone", Prunable: true},
	}
	containers := []managedContainer{
		{Name: "feature-a", State: "running", Port: "10000", CodePath: "/r/wt/a"},
		{Name: "feature-a-2", State: "exited", CodePath: "/r/wt/a/"},
		{Name: "elsewhere", State: "running", CodePath: "/other"},
		{Name: "express", State: "running"},
	}
	rows := joinWorktreeBooths(entries, containers)

	assert.Len(t, rows, 4, "a bare entry is not a worktree to list")
	assert.True(t, rows[0].Main)
	assert.Empty(t, rows[0].Booths)
	assert.Equal(t, []worktreeRowBooth{
		{Name: "feature-a", State: "running", Port: "10000"},
		{Name: "feature-a-2", State: "exited"},
	}, rows[1].Booths, "every booth on the worktree, whatever the path spelling")
	assert.Empty(t, rows[2].Booths)
	assert.True(t, rows[3].Prunable)
}
