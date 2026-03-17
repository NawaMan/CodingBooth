// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// DockerBuildAndPush builds a Docker image locally then pushes it to a registry.
// This uses "docker build" followed by "docker push", which is more reliable than
// "docker buildx build --push" because it avoids buildx driver networking issues
// (e.g., docker-container driver cannot reach localhost registries).
func DockerBuildAndPush(flags DockerFlags, buildArgs ilist.List[ilist.List[string]], imageName string) error {
	// Step 1: Build locally
	err := DockerBuild(flags, buildArgs)
	if err != nil {
		return err
	}

	if flags.Dryrun {
		return nil
	}

	// Step 2: Push
	pushArgs := ilist.NewList(ilist.NewList(imageName))

	pushFlags := flags
	// Push output goes to stderr regardless of silent mode
	// so the user sees progress, but on failure the build output is already shown
	err = Docker(pushFlags, "push", pushArgs)
	if err != nil {
		return err
	}

	return nil
}
