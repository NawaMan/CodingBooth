package workspace

import (
	"fmt"
	"os"

	"github.com/nawaman/workspace/src/pkg/appctx"
)

// ApplyEnvFile applies environment file configuration and returns updated AppContext.
func ApplyEnvFile(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	containerEnvFile := ctx.EnvFile()

	// If not set, default to <workspace>/.env when it exists
	if containerEnvFile == "" {
		candidate := ctx.Workspace() + "/.env"
		if candidate == "" {
			candidate = "./.env"
		}

		if fileExists(candidate) {
			containerEnvFile = candidate
			builder.Config.EnvFile = candidate
		}
	}

	// Respect the "not used" token
	if containerEnvFile != "" && containerEnvFile == "-" {
		if ctx.Verbose() {
			fmt.Println("Skipping --env-file (explicitly disabled).")
		}
		return builder.Build()
	}

	// If specified, it must exist; otherwise error out
	if containerEnvFile != "" {
		if !fileExists(containerEnvFile) {
			fmt.Fprintf(os.Stderr, "Error: env-file must be an existing file: %s\n", containerEnvFile)
			os.Exit(1)
		}

		builder.CommonArgs.Append("--env-file", containerEnvFile)
		if ctx.Verbose() {
			fmt.Printf("Using env-file: %s\n", containerEnvFile)
		}
	}

	return builder.Build()
}

// fileExists checks if a file exists.
func fileExists(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}
