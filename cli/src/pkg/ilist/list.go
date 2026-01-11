// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package ilist provides immutable list types that prevent slice aliasing bugs.
//
// Two types:
//   - List[TYPE]:           immutable view (read-only, goroutine-safe)
//   - AppendableList[TYPE]: mutable builder (NOT goroutine-safe)
//
// All conversions copy slices to prevent aliasing.
// For reference types (pointers, slices, maps), only references are copied.
package ilist

import (
	"fmt"
)

type List[TYPE any] struct {
	elements []TYPE
}

// NewList creates a new immutable List from the given elements.
// Note: To create from a slice, use NewListFromSlice to avoid NewList(slice) which creates List[[]TYPE].
func NewList[TYPE any](elements ...TYPE) List[TYPE] {
	if len(elements) == 0 {
		return List[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(elements))
	copy(copied, elements)
	return List[TYPE]{elements: copied}
}

// NewListFromSlice creates a new immutable List from an existing slice.
func NewListFromSlice[TYPE any](slice []TYPE) List[TYPE] {
	if len(slice) == 0 {
		return List[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(slice))
	copy(copied, slice)
	return List[TYPE]{elements: copied}
}

// String returns a string representation of the list.
func (thisList List[TYPE]) String() string {
	return fmt.Sprintf("%v", thisList.elements)
}

// Length returns the number of elements in the list.
func (thisList List[TYPE]) Length() int {
	return len(thisList.elements)
}

// Get returns (element, true) if index is valid, (zero, false) otherwise.
func (thisList List[TYPE]) Get(index int) (TYPE, bool) {
	if index < 0 || index >= len(thisList.elements) {
		var zero TYPE
		return zero, false
	}
	return thisList.elements[index], true
}

// At panics if index is out of bounds. Use Get for bounds-checked access.
func (thisList List[TYPE]) At(index int) TYPE {
	return thisList.elements[index]
}

// Slice returns a copy of the elements as a slice.
func (thisList List[TYPE]) Slice() []TYPE {
	if len(thisList.elements) == 0 {
		return nil
	}
	copied := make([]TYPE, len(thisList.elements))
	copy(copied, thisList.elements)
	return copied
}

// Range stops early if fn returns false.
func (thisList List[TYPE]) Range(fn func(index int, value TYPE) bool) {
	for index, value := range thisList.elements {
		if !fn(index, value) {
			break
		}
	}
}

func (thisList List[T]) Clone() List[T] {
	if thisList.elements == nil {
		return List[T]{elements: nil}
	}
	cp := append([]T(nil), thisList.elements...)
	return List[T]{elements: cp}
}

// ToBuilder creates a new AppendableList with a copy of this List's elements.
func (thisList List[TYPE]) ToBuilder() *AppendableList[TYPE] {
	if len(thisList.elements) == 0 {
		return &AppendableList[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(thisList.elements))
	copy(copied, thisList.elements)
	return &AppendableList[TYPE]{elements: copied}
}

// ExtendByLists returns a new List combining this list with other lists.
func (thisList List[TYPE]) ExtendByLists(others ...List[TYPE]) List[TYPE] {
	totalLength := len(thisList.elements)
	for _, other := range others {
		totalLength += len(other.elements)
	}

	if totalLength == 0 {
		return List[TYPE]{elements: nil}
	}

	combined := make([]TYPE, totalLength)
	offset := copy(combined, thisList.elements)
	for _, other := range others {
		offset += copy(combined[offset:], other.elements)
	}

	return List[TYPE]{elements: combined}
}
