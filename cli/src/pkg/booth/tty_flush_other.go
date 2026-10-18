// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

//go:build !linux && !darwin && !dragonfly && !freebsd && !netbsd && !openbsd

package booth

import "os"

// discardPendingInput is a no-op here: there is no /dev/tty input queue to drop (Windows has no
// /dev/tty, so the consent prompt reports there is no terminal before it gets this far).
func discardPendingInput(tty *os.File) {}
