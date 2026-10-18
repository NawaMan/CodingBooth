// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

//go:build darwin || dragonfly || freebsd || netbsd || openbsd

package booth

import (
	"os"

	"golang.org/x/sys/unix"
)

// fread is FREAD from <sys/fcntl.h>: TIOCFLUSH with it drops the input queue only.
const fread = 0x1

// discardPendingInput drops whatever was typed on the terminal but not yet read. Best effort: a
// failure leaves the input as it was.
func discardPendingInput(tty *os.File) {
	_ = unix.IoctlSetPointerInt(int(tty.Fd()), unix.TIOCFLUSH, fread)
}
