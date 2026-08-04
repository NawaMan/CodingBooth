// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

// Every text field in the TUI keeps its own cursor position, and all of them move
// it the same way. One helper answers "does this key move the cursor, and where
// to" for all six input sites — the search bar, config string/int fields, config
// list entries, single-value params, variadic package rows and the overwrite
// confirmation — so a field cannot quietly grow its own idea of Home.
//
// Positions are byte offsets, which is safe because every one of those fields
// filters its input to printable ASCII (see typedText): one byte is one column.

// moveTextCursor applies a cursor-movement key to a text field, returning the new
// position and whether the key was one of them.
func moveTextCursor(key string, cursor, length int) (int, bool) {
	switch key {
	case "left":
		if cursor > 0 {
			cursor--
		}
	case "right":
		if cursor < length {
			cursor++
		}
	case "home":
		cursor = 0
	case "end":
		cursor = length
	default:
		return cursor, false
	}
	if cursor < 0 {
		cursor = 0
	}
	if cursor > length {
		cursor = length
	}
	return cursor, true
}

// A block cursor is drawn by reversing the cell the cursor is on, the way a
// terminal draws its own — and the way Claude Code draws its prompt.
//
// The codes are written by hand rather than through a lipgloss style because a
// style ends its output with a full reset (\x1b[0m), which would also drop the
// background the field itself is painted with and leave the rest of the row
// unstyled. `27` turns off reverse and nothing else, so the field's own colours
// carry on across the cursor.
const (
	cursorReverseOn  = "\x1b[7m"
	cursorReverseOff = "\x1b[27m"
)

// caretText draws value with a block cursor on the character at cursor.
//
// The cursor covers a character rather than sitting between two, so the text does
// not shift as the cursor walks it — and at the end of the value it covers the
// blank cell the next character will land in. Before this the caret was appended
// to the end of every field regardless of where the cursor was, which made moving
// the cursor invisible: the text went in at the right place, but the field looked
// like it had ignored the arrow key.
func caretText(value string, cursor int) string {
	if cursor < 0 {
		cursor = 0
	}
	if cursor >= len(value) {
		return value + cursorReverseOn + " " + cursorReverseOff
	}
	return value[:cursor] + cursorReverseOn + value[cursor:cursor+1] + cursorReverseOff + value[cursor+1:]
}

// windowAround returns the run of text that fits in width columns while keeping
// cursor inside it, along with where the cursor sits within that run.
//
// Only the search bar needs it — it is the one field drawn in a box of fixed
// width, and a cursor sent Home in a long query would otherwise scroll off the
// left edge and take the caret with it.
func windowAround(text string, cursor, width int) (string, int) {
	if width < 1 {
		width = 1
	}
	if cursor < 0 {
		cursor = 0
	}
	if cursor > len(text) {
		cursor = len(text)
	}
	if len(text) <= width {
		return text, cursor
	}

	start := 0
	if cursor > width {
		start = cursor - width
	}
	if start > len(text)-width {
		start = len(text) - width
	}
	return text[start : start+width], cursor - start
}
