// Interactive TTY Demo - demonstrates -it flags working with TTY detection
//
// Run this directly to see interactive mode:
//
//	go run ./src/cmd/docker-interactive-demo/main.go
//
// Or build and run:
//
//	go build -o docker-demo ./src/cmd/docker-interactive-demo/
//	./docker-demo
package main

import (
	"fmt"
	"os"

	"github.com/nawaman/workspace/src/pkg/docker"
)

func main() {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Docker Interactive Shell Demo")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()

	// Show TTY status
	hasTTY := docker.HasInteractiveTTY()
	fmt.Println("Current TTY status:")
	fmt.Printf("  • HasInteractiveTTY: %v\n", hasTTY)
	fmt.Printf("  • IsStdinTTY: %v\n", docker.IsStdinTTY())
	fmt.Printf("  • IsStdoutTTY: %v\n", docker.IsStdoutTTY())
	fmt.Println()

	if hasTTY {
		fmt.Println("✅ Running with TTY detected!")
		fmt.Println("   The -it flags will be PRESERVED")
		fmt.Println("   You will get an interactive shell")
		fmt.Println()
		fmt.Println("   Type 'exit' to quit the shell")
	} else {
		fmt.Println("ℹ️  Running without TTY")
		fmt.Println("   The -it flags will be AUTO-STRIPPED")
		fmt.Println("   Will run non-interactively")
	}
	fmt.Println()

	// Define options
	verbose := true
	dryrun := false

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")

	// Use -it flags - they'll be preserved if TTY is available
	err := docker.Docker(dryrun, verbose, "run",
		"-it",  // Interactive + TTY (auto-filtered if no TTY)
		"--rm", // Remove after exit
		"alpine:latest",
		"sh", // Start shell (interactive if -it is preserved)
	)

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println()

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("✅ Demo completed!")
}
