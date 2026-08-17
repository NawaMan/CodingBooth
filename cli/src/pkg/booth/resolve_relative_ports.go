// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// ResolveRelativePorts resolves +OFFSET port mappings in RunArgs to absolute ports.
// For example, if the offset base is 10000 and run-args contains "-p +8080:8080",
// it becomes "-p 18080:8080".
//
// The base is the booth port unless offset-base says otherwise (see
// parseOffsetBase). Following the booth port is what a local run wants — two
// booths of one project land on different booth ports and so on different
// published ports. A booth alone on a cloud host has no such collision to dodge
// and a front door it does not choose, so it sets a base of its own instead.
func ResolveRelativePorts(ctx appctx.AppContext) appctx.AppContext {
	offsetBase := ctx.OffsetBaseNumber()
	runArgs := ctx.RunArgs()

	result := ilist.NewAppendableList[ilist.List[string]]()
	changed := false

	runArgs.Range(func(_ int, argList ilist.List[string]) bool {
		newArgs := ilist.NewAppendableList[string]()
		prevWasPort := false

		argList.Range(func(_ int, arg string) bool {
			if prevWasPort {
				prevWasPort = false
				if strings.HasPrefix(arg, "+") {
					if mapped, ok := resolveRelativeMapping(arg, offsetBase); ok {
						newArgs.Append(mapped)
						changed = true
						return true
					}
				}
				newArgs.Append(arg)
				return true
			}

			if arg == "-p" || arg == "--publish" {
				prevWasPort = true
				newArgs.Append(arg)
				return true
			}

			// Handle -p=+OFFSET:CONTAINER and --publish=+OFFSET:CONTAINER
			if strings.HasPrefix(arg, "-p=+") {
				value := strings.TrimPrefix(arg, "-p=")
				if mapped, ok := resolveRelativeMapping(value, offsetBase); ok {
					newArgs.Append("-p=" + mapped)
					changed = true
					return true
				}
			} else if strings.HasPrefix(arg, "--publish=+") {
				value := strings.TrimPrefix(arg, "--publish=")
				if mapped, ok := resolveRelativeMapping(value, offsetBase); ok {
					newArgs.Append("--publish=" + mapped)
					changed = true
					return true
				}
			}

			newArgs.Append(arg)
			return true
		})

		result.Append(newArgs.ToList())
		return true
	})

	if !changed {
		return ctx
	}

	builder := ctx.ToBuilder()
	builder.RunArgs = result
	return builder.Build()
}

// resolveRelativeMapping resolves a +OFFSET:CONTAINER mapping against the offset
// base to an absolute port mapping. Returns the resolved mapping and true if
// successful.
func resolveRelativeMapping(mapping string, offsetBase int) (string, bool) {
	if !strings.HasPrefix(mapping, "+") {
		return "", false
	}

	parts := strings.SplitN(mapping[1:], ":", 2)
	if len(parts) != 2 {
		return "", false
	}

	offset, err := strconv.Atoi(parts[0])
	if err != nil {
		return "", false
	}

	hostPort := offsetBase + offset
	return fmt.Sprintf("%d:%s", hostPort, parts[1]), true
}
