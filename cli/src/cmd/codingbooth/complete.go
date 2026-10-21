// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"

	"github.com/nawaman/codingbooth/src/pkg/completion"
)

// runComplete handles: codingbooth __complete <word>... — the shell completion
// scripts call it with the words after `booth`, the last being the word under
// the cursor. It always exits 0: a completion that fails offers nothing.
func runComplete(version string, words []string) {
	result := completion.Complete(completion.Spec(), words, completion.LiveSources{Version: version})
	completion.Write(os.Stdout, result)
}
