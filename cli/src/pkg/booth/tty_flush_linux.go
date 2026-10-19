// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"

	"golang.org/x/sys/unix"
)

// discardPendingInput drops whatever was typed on the terminal but not yet read (tcflush with
// TCIFLUSH). Best effort: a failure leaves the input as it was.
func discardPendingInput(tty *os.File) {
	_ = unix.IoctlSetInt(int(tty.Fd()), unix.TCFLSH, unix.TCIFLUSH)
}
