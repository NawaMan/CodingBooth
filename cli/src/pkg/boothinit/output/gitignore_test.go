// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// wrapperScript is the booth wrapper at the repo root, five levels up from this package.
const wrapperScript = "../../../../../booth"

// TestBoothGitignoreMatchesWrapper pins the two writers of .booth/.gitignore together.
//
// The wrapper writes the file before the CLI binary is downloaded; `booth config` rewrites it
// unconditionally afterwards. When they disagree, whichever runs last wins and the other's
// rules vanish -- that is how the wrapper's tools/ rules were being dropped, and how a
// .booth/.gitignore missing "cache/" could reach a project and let credentials be committed.
func TestBoothGitignoreMatchesWrapper(t *testing.T) {
	data, err := os.ReadFile(filepath.Clean(wrapperScript))
	if err != nil {
		t.Fatalf("reading the booth wrapper: %v", err)
	}

	heredocs := extractHeredocs(string(data), "GITIGNORE")
	if len(heredocs) != 1 {
		t.Fatalf("expected exactly 1 GITIGNORE heredoc in the booth wrapper, found %d — "+
			"a per-mode copy is how these drifted before; keep it to one", len(heredocs))
	}

	if heredocs[0] != BoothGitignore {
		t.Errorf("the booth wrapper's .gitignore has drifted from output.BoothGitignore.\n"+
			"They must be byte-identical; `booth config` overwrites whatever the wrapper wrote.\n\n"+
			"--- wrapper (./booth) ---\n%s\n--- BoothGitignore (gitignore.go) ---\n%s",
			heredocs[0], BoothGitignore)
	}
}

// TestBoothGitignoreCoversCache guards the rule the start-up check depends on: booth refuses
// to start when .booth/cache/ is not ignored, so the file we generate had better ignore it.
func TestBoothGitignoreCoversCache(t *testing.T) {
	for _, rule := range []string{"cache/", ".booth.password", ".env", "tools/codingbooth-*"} {
		if !hasLine(BoothGitignore, rule) {
			t.Errorf("BoothGitignore is missing the %q rule", rule)
		}
	}
}

// extractHeredocs returns the body of every <<'DELIM' ... DELIM heredoc in src.
func extractHeredocs(src, delim string) []string {
	var bodies []string
	lines := strings.Split(src, "\n")
	for i := 0; i < len(lines); i++ {
		if !strings.Contains(lines[i], "<<'"+delim+"'") {
			continue
		}
		var body []string
		for j := i + 1; j < len(lines); j++ {
			if lines[j] == delim {
				bodies = append(bodies, strings.Join(body, "\n")+"\n")
				i = j
				break
			}
			body = append(body, lines[j])
		}
	}
	return bodies
}

func hasLine(content, line string) bool {
	for _, l := range strings.Split(content, "\n") {
		if l == line {
			return true
		}
	}
	return false
}
