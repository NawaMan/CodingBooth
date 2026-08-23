// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// The transient progress line a silenced build draws can only be judged on a
// real terminal — `go test` captures output, which is exactly the case where the
// line is deliberately not drawn. This runs the two paths that matter side by
// side: a build that goes quiet mid-step, and a build that fails.

const quietDockerfile = `FROM alpine:latest
RUN echo "Downloading something enormous (224 MB)…" && sleep 20 && echo "done"
CMD ["echo", "Hello"]
`

const failingDockerfile = `FROM alpine:latest
RUN echo "about to fail" && sleep 3 && exit 7
`

func main() {
	// `quiet` runs the slow build alone, so the wrapper can run this binary a
	// second time with its stderr redirected — the shape every test in
	// tests/complex has, and the one the terminal fallback exists for.
	if len(os.Args) > 1 && os.Args[1] == "quiet" {
		runSilentBuild("quiet", quietDockerfile, "build-progress-manual-test:latest")
		return
	}

	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Silenced Build Progress Manual Test")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("Part 1 — a build that goes quiet for 20 seconds.")
	fmt.Println()
	fmt.Println("You should see ONE line, redrawn in place:")
	fmt.Println("  • a spinner and a clock that keeps counting through the silence")
	fmt.Println("  • the step being built, e.g. [2/2] RUN echo \"Downloading …\"")
	fmt.Println("  • that step's last output line after the em dash")
	fmt.Println("  • nothing left behind in the scrollback when it finishes")
	fmt.Println()

	runSilentBuild("quiet", quietDockerfile, "build-progress-manual-test:latest")

	fmt.Println("✅ Part 1 done — the line above this one should be gone.")
	fmt.Println()
	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Part 2 — a build that fails.")
	fmt.Println()
	fmt.Println("You should see the status line erased, then the full build log,")
	fmt.Println("with no spinner text glued to the '❌ Docker build failed!' header.")
	fmt.Println()

	if err := runSilentBuild("failing", failingDockerfile, "build-progress-manual-test-fail:latest"); err == nil {
		fmt.Println("❌ Part 2 was expected to fail and did not.")
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println("✅ Part 2 done.")
}

func runSilentBuild(name string, dockerfile string, tag string) error {
	dir, err := os.MkdirTemp("", "build-progress-manual-test-"+name)
	if err != nil {
		fmt.Printf("Failed to create build context: %v\n", err)
		os.Exit(1)
	}
	defer os.RemoveAll(dir)

	path := dir + "/Dockerfile"
	if err := os.WriteFile(path, []byte(dockerfile), 0644); err != nil {
		fmt.Printf("Failed to create Dockerfile: %v\n", err)
		os.Exit(1)
	}

	flags := docker.DockerFlags{Silent: true}

	// --no-cache so the slow step actually runs on every invocation; a cached
	// build would finish before the line is even drawn.
	return docker.DockerBuild(flags, ilist.NewList(ilist.NewList(
		"--no-cache",
		"-t", tag,
		"-f", path,
		dir,
	)))
}
