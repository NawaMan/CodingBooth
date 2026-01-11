// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package ilist

import "fmt"

type AppendableList[TYPE any] struct {
	elements []TYPE
}

// NewAppendableList creates a new empty AppendableList.
func NewAppendableList[TYPE any]() *AppendableList[TYPE] {
	return &AppendableList[TYPE]{elements: nil}
}

// NewAppendableListFrom creates a new AppendableList with the given initial elements.
func NewAppendableListFrom[TYPE any](elements ...TYPE) *AppendableList[TYPE] {
	if len(elements) == 0 {
		return &AppendableList[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(elements))
	copy(copied, elements)
	return &AppendableList[TYPE]{elements: copied}
}

// String returns a string representation of the list.
func (thisList AppendableList[TYPE]) String() string {
	return fmt.Sprintf("%v", thisList.elements)
}

// Append adds one or more elements to the end of the list.
func (thisList *AppendableList[TYPE]) Append(values ...TYPE) {
	thisList.elements = append(thisList.elements, values...)
}

// ExtendBySlice appends all elements from the given slice.
func (thisList *AppendableList[TYPE]) ExtendBySlice(slice []TYPE) {
	if len(slice) == 0 {
		return
	}
	copied := make([]TYPE, len(slice))
	copy(copied, slice)
	thisList.elements = append(thisList.elements, copied...)
}

// ExtendByList appends all elements from the given List.
func (thisList *AppendableList[TYPE]) ExtendByList(list List[TYPE]) {
	if list.Length() == 0 {
		return
	}
	copied := make([]TYPE, len(list.elements))
	copy(copied, list.elements)
	thisList.elements = append(thisList.elements, copied...)
}

// Length returns the number of elements in the list.
func (thisList *AppendableList[TYPE]) Length() int {
	return len(thisList.elements)
}

// Slice returns a copy of the current elements as a slice.
func (thisList *AppendableList[TYPE]) Slice() []TYPE {
	if len(thisList.elements) == 0 {
		return nil
	}
	copied := make([]TYPE, len(thisList.elements))
	copy(copied, thisList.elements)
	return copied
}

// Snapshot creates an immutable List with a copy of the current elements.
func (thisList *AppendableList[TYPE]) Snapshot() List[TYPE] {
	if len(thisList.elements) == 0 {
		return List[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(thisList.elements))
	copy(copied, thisList.elements)
	return List[TYPE]{elements: copied}
}

// Clone creates a copy of this AppendableList.
func (thisList *AppendableList[TYPE]) Clone() *AppendableList[TYPE] {
	if len(thisList.elements) == 0 {
		return &AppendableList[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(thisList.elements))
	copy(copied, thisList.elements)
	return &AppendableList[TYPE]{elements: copied}
}

// ToList returns an immutable List snapshot from this mutable list, handling nil receiver.
func (thisList *AppendableList[TYPE]) ToList() List[TYPE] {
	if thisList == nil {
		return NewList[TYPE]()
	}
	return thisList.Snapshot()
}
