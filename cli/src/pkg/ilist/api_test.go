// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package ilist

import "testing"

// TestNewListFromSlice verifies no aliasing when creating from slice.
func TestNewListFromSlice(t *testing.T) {
	original := []string{"a", "b", "c"}
	list := NewListFromSlice(original)
	original[0] = "X"

	if v, ok := list.Get(0); !ok || v != "a" {
		t.Errorf("list.Get(0) = %v, want a (no aliasing)", v)
	}
}

// TestAtPanic tests that At panics on out-of-bounds access.
func TestAtPanic(t *testing.T) {
	list := NewList(1, 2, 3)

	defer func() {
		if r := recover(); r == nil {
			t.Error("At(-1) should panic")
		}
	}()
	_ = list.At(-1)
}

// TestAppendableListSlice verifies no aliasing when getting slice from builder.
func TestAppendableListSlice(t *testing.T) {
	builder := NewAppendableList[string]()
	builder.Append("x", "y")
	slice := builder.Slice()
	slice[0] = "MODIFIED"

	// Verify builder wasn't affected
	if newSlice := builder.Slice(); newSlice[0] != "x" {
		t.Errorf("builder.Slice()[0] = %s, want x (no aliasing)", newSlice[0])
	}
}
