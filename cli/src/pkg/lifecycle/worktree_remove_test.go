// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/gitworktree"
	"github.com/stretchr/testify/assert"
)

func TestMatchBoothVolumes(t *testing.T) {
	volumes := []string{
		"booth-pgdata-feature-x", "booth-redisdata-feature-x", "cb-home-feature-x",
		"booth-pgdata-x",               // another booth, named x
		"booth-pgdata-other-feature-x", // another booth, whose name ends like this one
		"cb-home-feature-x-2",
		"booth-shared-cache", "feature-x",
	}
	assert.Equal(t,
		[]string{"booth-pgdata-feature-x", "booth-redisdata-feature-x", "cb-home-feature-x"},
		matchBoothVolumes(volumes, []string{"feature-x"}))
}

func TestRemovalRefusal(t *testing.T) {
	e := gitworktree.Entry{Path: "/r/w", Branch: "w"}
	running := []managedContainer{{Name: "w", State: "running"}}
	stopped := []managedContainer{{Name: "w", State: "exited"}}
	dirty := gitworktree.Loss{Changes: []string{"?? draft.txt"}}

	assert.Empty(t, removalRefusal(e, stopped, gitworktree.Loss{}, false), "a stopped booth goes with it")
	assert.Empty(t, removalRefusal(e, nil, gitworktree.Loss{BranchOnly: 3}, false),
		"commits only on the branch keep the branch, not the worktree")
	assert.Contains(t, removalRefusal(e, running, gitworktree.Loss{}, false), "booth w is running")
	assert.Contains(t, removalRefusal(e, nil, dirty, false), "1 uncommitted or untracked file")
	assert.Contains(t, removalRefusal(e, nil, gitworktree.Loss{HeadOnly: 1}, false), "detached HEAD")
	assert.Empty(t, removalRefusal(e, running, dirty, true), "--force goes ahead")
}

func TestDescribeLoss(t *testing.T) {
	e := gitworktree.Entry{Path: "/r/w", Branch: "w"}
	assert.Empty(t, describeLoss(e, nil, gitworktree.Loss{}, nil), "nothing to lose: no question")
	got := describeLoss(e, []managedContainer{{Name: "w", State: "running"}},
		gitworktree.Loss{Changes: []string{"?? draft.txt"}, BranchOnly: 2},
		[]engineVolume{{"docker", "booth-pgdata-w"}})
	for _, want := range []string{"?? draft.txt", "2 commit(s) only on branch w", "Running booth w", "Volume booth-pgdata-w"} {
		assert.Contains(t, got, want)
	}
}

func TestBoothNames(t *testing.T) {
	assert.Equal(t, []string{"feature-x", "custom"},
		boothNames([]managedContainer{{Name: "custom"}, {Name: "feature-x"}}, "feature-x"))
}
