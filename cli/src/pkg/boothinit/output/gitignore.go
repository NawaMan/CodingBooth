// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

// BoothGitignore is the canonical content of .booth/.gitignore.
//
// Two things write this file: `booth config` (here) and the booth wrapper script, which has
// to write it before the CLI binary has even been downloaded. They must stay byte-identical.
// TestBoothGitignoreMatchesWrapper pins them together; keep this constant and the GITIGNORE
// heredoc in ./booth in sync, or that test fails.
//
// Drift here is not cosmetic. `booth config` rewrites .gitignore unconditionally, so any rule
// only one writer knows about is silently dropped the next time the other one runs — which is
// how the wrapper's tools/ rules used to disappear, leaving the downloaded binaries
// committable in --cache=local projects.
//
// The content is deliberately mode-independent. The wrapper previously emitted the tools/
// rules only for --cache=local; in shared-cache mode .booth/tools/ holds nothing but the lock
// file, so carrying them always is a harmless no-op there and survives a mode switch.
const BoothGitignore = `# Secrets - never commit
.booth.password
.env

# Local persistent state (not committed).
# Holds whatever the container writes to the mounted paths, including live credentials
# (~/.claude/.credentials.json arrives here via the cb-home override layer).
# Booth refuses to start if this is tracked by git.
cache/

# Runtime temp files
.tmp/

# Transient artifacts of booth config overwriting hand-written files:
# .bak = what was replaced, .new = generated content awaiting a manual merge
*.bak
*.new

# Downloaded binaries - re-fetched from the lock version.
# Shared cache (the default) keeps them in ~/.cache/codingbooth/; --cache=local puts them here.
tools/codingbooth-*
tools/*.sha256

# codingbooth.lock and .generated are version-controlled
`
