// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"errors"
	"fmt"
	"io"
	"os/exec"
)

// Native runs already-translated engine arguments and streams output unchanged.
// In particular, user-facing inspect must retain the complete native document;
// the Apple adapter's Docker-shaped inspection is only for internal lookups.
func Native(engine, subcommand string, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	binary := EngineBinary(engine)
	command := exec.Command(binary, append([]string{subcommand}, args...)...)
	command.Env = commandEnv()
	command.Stdin, command.Stdout, command.Stderr = stdin, stdout, stderr
	if err := command.Run(); err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			return &DockerExitError{Subcommand: subcommand, ExitCode: exitError.ExitCode(), Engine: binary}
		}
		return fmt.Errorf("%s %s failed: %w", binary, subcommand, err)
	}
	return nil
}
