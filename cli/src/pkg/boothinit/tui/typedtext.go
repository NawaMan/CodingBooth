// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	tea "github.com/charmbracelet/bubbletea"
)

// typedText returns the text a key contributes to a text field: one character for
// a keystroke, the whole payload for a paste or any other multi-rune key event.
//
// Every text field used to test `len(msg.String()) == 1`, and so threw away all of
// them but the single keystroke. Two ways a field receives more than one character
// at a time, both of which used to vanish:
//
//   - A bracketed paste (Bubble Tea enables it by default) arrives as one KeyRunes
//     message carrying the entire clipboard, and its String() is deliberately
//     wrapped in "[...]" so key bindings cannot match a paste. Length test and
//     printable-byte test both fail, so a pasted module path like
//     "github.com/golangci/golangci-lint/cmd/golangci-lint@latest" simply did not
//     appear, and had to be retyped by hand.
//   - Bubble Tea coalesces "the longest sequence of runes that are not control
//     characters" from one read into a single KeyRunes message. A terminal without
//     bracketed paste, an `xdotool type`, a laggy link delivering a burst, or a
//     multi-rune IME commit therefore also arrive several characters at once —
//     with no Paste flag to notice them by.
//
// So the payload of any KeyRunes is text, however many runes it holds. It is
// filtered to printable ASCII rather than rejected whole: copying a line usually
// brings its trailing newline along, and a control character in a param value would
// be written straight into the Boothfile. Filtering keeps the paste visible so the
// user can see and fix a mangled value, where dropping it outright just looks like
// paste is still broken.
func typedText(msg tea.KeyMsg) string {
	// Alt+<rune> is a chord, not text — Bubble Tea models it as KeyRunes too.
	if msg.Type == tea.KeyRunes && !msg.Alt {
		return filterBytes(string(msg.Runes), isPrintableASCII)
	}
	// Named keys: only the ones that stand for a character (space) are text.
	s := msg.String()
	if len(s) == 1 && isPrintableASCII(s[0]) {
		return s
	}
	return ""
}

// keyName returns the name a handler should dispatch on, and "" for a key event
// that is text rather than a keypress.
//
// Handlers switch on msg.String(), and String() of a multi-rune event is just its
// runes: an unbracketed paste of the literal text "up" or "esc" would otherwise be
// obeyed as the key of that name instead of inserted. A single rune stays
// ambiguous by design — " " has to keep meaning "edit this row" — but more than one
// rune, or an explicit paste, can never be a keypress.
func keyName(msg tea.KeyMsg) string {
	if msg.Paste || len(msg.Runes) > 1 {
		return ""
	}
	return msg.String()
}

// isPrintableASCII reports whether ch is a character a text field can display.
func isPrintableASCII(ch byte) bool {
	return ch >= 32 && ch < 127
}

// filterBytes returns s without the bytes keep rejects, and s itself when there
// is nothing to drop — the common case, since a keystroke is one accepted byte.
func filterBytes(s string, keep func(byte) bool) string {
	drop := -1
	for i := range len(s) {
		if !keep(s[i]) {
			drop = i
			break
		}
	}
	if drop < 0 {
		return s
	}

	out := make([]byte, 0, len(s)-1)
	out = append(out, s[:drop]...)
	for i := drop + 1; i < len(s); i++ {
		if keep(s[i]) {
			out = append(out, s[i])
		}
	}
	return string(out)
}
