package ilist

import (
	"testing"
)

// TestSnapshotImmutability verifies that mutations to a builder don't affect prior snapshots.
func TestSnapshotImmutability(t *testing.T) {
	builder := NewAppendableList[string]()
	builder.Append("arg1", "arg2")
	snapshot := builder.Snapshot()

	// Mutate builder
	builder.Append("arg3")

	// Verify snapshot is unchanged
	if snapshot.Length() != 2 {
		t.Errorf("snapshot.Length() = %d, want 2", snapshot.Length())
	}
}

// TestNewAppendableListFromDeepCopy verifies that NewAppendableListFrom doesn't share backing array.
func TestNewAppendableListFromDeepCopy(t *testing.T) {
	external := []int{10, 20, 30}
	builder := NewAppendableListFrom(external...)
	external[0] = 999

	// Verify builder wasn't affected by external mutation
	if v, ok := builder.Snapshot().Get(0); !ok || v != 10 {
		t.Errorf("builder Get(0) = %v, %v, want 10, true", v, ok)
	}
}

// TestExtendBySliceDeepCopy verifies that ExtendBySlice performs a deep copy.
func TestExtendBySliceDeepCopy(t *testing.T) {
	builder := NewAppendableList[string]()
	builder.Append("a")
	external := []string{"b", "c"}
	builder.ExtendBySlice(external)
	external[0] = "X"

	// Verify builder wasn't affected
	if v, ok := builder.Snapshot().Get(1); !ok || v != "b" {
		t.Errorf("builder.Get(1) = %v, %v, want b, true", v, ok)
	}
}

// TestCloneIndependence verifies that Clone creates an independent copy.
func TestCloneIndependence(t *testing.T) {
	original := NewAppendableList[int]()
	original.Append(1, 2, 3)
	clone := original.Clone()
	original.Append(4)

	// Verify clone is unchanged
	if clone.Length() != 3 {
		t.Errorf("clone.Length() = %d, want 3", clone.Length())
	}
}

// TestDockerArgsWorkflow simulates the workspace pattern.
func TestDockerArgsWorkflow(t *testing.T) {
	builder := NewAppendableList[string]()
	builder.Append("--name", "mycontainer")
	builder.Append("--network", "bridge")
	builder.Append("--rm")
	originalArgs := builder.Snapshot()

	// Simulate filtering network flags
	filtered := NewAppendableList[string]()
	skipNext := false
	originalArgs.Range(func(i int, arg string) bool {
		if skipNext {
			skipNext = false
			return true
		}
		if arg == "--network" {
			skipNext = true
			return true
		}
		filtered.Append(arg)
		return true
	})

	// Verify filtering worked
	if filtered.Length() != 3 {
		t.Errorf("filtered.Length() = %d, want 3", filtered.Length())
	}

	// Verify original snapshot is unchanged
	if originalArgs.Length() != 5 {
		t.Errorf("originalArgs.Length() = %d, want 5", originalArgs.Length())
	}
}

// TestExtendByList tests extending from another list.
func TestExtendByList(t *testing.T) {
	builder := NewAppendableList[int]()
	builder.Append(1, 2)
	other := NewList(3, 4, 5)
	builder.ExtendByList(other)

	if builder.Length() != 5 {
		t.Errorf("after ExtendByList Length() = %d, want 5", builder.Length())
	}
}

// TestMultipleSnapshots tests creating multiple snapshots from the same builder.
func TestMultipleSnapshots(t *testing.T) {
	builder := NewAppendableList[int]()
	builder.Append(1)
	snap1 := builder.Snapshot()

	builder.Append(2)
	snap2 := builder.Snapshot()

	// Verify each snapshot is independent
	if snap1.Length() != 1 || snap2.Length() != 2 {
		t.Errorf("snap1.Length() = %d, snap2.Length() = %d, want 1, 2", snap1.Length(), snap2.Length())
	}
}
