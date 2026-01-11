// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package ilist

import (
	"testing"
)

// TestToBuilderDeepCopy verifies that List→Builder conversion performs a deep copy.
func TestToBuilderDeepCopy(t *testing.T) {
	list := NewList("a", "b", "c")
	builder := list.ToBuilder()
	builder.Append("d")

	// Verify original list is unchanged
	if list.Length() != 3 {
		t.Errorf("list.Length() = %d, want 3", list.Length())
	}
}

// TestSliceDeepCopy verifies that Slice() returns a deep copy.
func TestSliceDeepCopy(t *testing.T) {
	list := NewList(1, 2, 3)
	slice := list.Slice()
	slice[0] = 999

	// Verify original list is unchanged
	if v, ok := list.Get(0); !ok || v != 1 {
		t.Errorf("list.Get(0) = %v, %v, want 1, true", v, ok)
	}
}

// TestRange tests iteration behavior.
func TestRange(t *testing.T) {
	list := NewList(10, 20, 30)

	sum := 0
	list.Range(func(i int, v int) bool {
		sum += v
		return true
	})
	if sum != 60 {
		t.Errorf("sum = %d, want 60", sum)
	}

	// Test early termination
	count := 0
	list.Range(func(i int, v int) bool {
		count++
		return i < 1 // Stop after index 1
	})
	if count != 2 {
		t.Errorf("count = %d, want 2", count)
	}
}

// TestGetOutOfBounds tests Get with invalid indices.
func TestGetOutOfBounds(t *testing.T) {
	list := NewList(1, 2, 3)

	if _, ok := list.Get(-1); ok {
		t.Error("Get(-1) should return false")
	}
	if _, ok := list.Get(3); ok {
		t.Error("Get(3) should return false")
	}
}

// TestExtendByListsDeepCopy verifies that ExtendByLists performs a deep copy.
func TestExtendByListsDeepCopy(t *testing.T) {
	list1 := NewList(1, 2, 3)
	list2 := NewList(4, 5)
	list3 := NewList(6, 7, 8)

	combined := list1.ExtendByLists(list2, list3)

	// Verify combined list has correct elements
	if combined.Length() != 8 {
		t.Errorf("combined.Length() = %d, want 8", combined.Length())
	}

	// Verify original lists are independent
	builder1 := list1.ToBuilder()
	builder1.Append(999)

	if v, _ := combined.Get(0); v == 999 {
		t.Error("modifying original list1 should not affect combined list")
	}
}

// TestExtendByListsMultiple tests combining multiple lists.
func TestExtendByListsMultiple(t *testing.T) {
	list1 := NewList("a", "b")
	list2 := NewList("c", "d")
	list3 := NewList("e", "f")

	combined := list1.ExtendByLists(list2, list3)

	expected := []string{"a", "b", "c", "d", "e", "f"}
	if combined.Length() != len(expected) {
		t.Errorf("combined.Length() = %d, want %d", combined.Length(), len(expected))
	}

	for index, want := range expected {
		if got, ok := combined.Get(index); !ok || got != want {
			t.Errorf("combined.Get(%d) = %v, %v, want %v, true", index, got, ok, want)
		}
	}
}

// TestExtendByListsEmpty tests edge cases with empty lists.
func TestExtendByListsEmpty(t *testing.T) {
	list1 := NewList(1, 2, 3)
	empty := NewList[int]()

	// Extend with empty list
	result1 := list1.ExtendByLists(empty)
	if result1.Length() != 3 {
		t.Errorf("result1.Length() = %d, want 3", result1.Length())
	}

	// Empty list extended with non-empty
	result2 := empty.ExtendByLists(list1)
	if result2.Length() != 3 {
		t.Errorf("result2.Length() = %d, want 3", result2.Length())
	}

	// All empty lists
	result3 := empty.ExtendByLists(empty, empty)
	if result3.Length() != 0 {
		t.Errorf("result3.Length() = %d, want 0", result3.Length())
	}
}

// TestExtendByListsNoArgs tests calling ExtendByLists with no arguments.
func TestExtendByListsNoArgs(t *testing.T) {
	list := NewList(1, 2, 3)
	result := list.ExtendByLists()

	if result.Length() != 3 {
		t.Errorf("result.Length() = %d, want 3", result.Length())
	}

	// Verify it's a copy, not the same underlying slice
	builder := list.ToBuilder()
	builder.Append(999)

	if v, _ := result.Get(3); v == 999 {
		t.Error("result should be independent of original list")
	}
}
