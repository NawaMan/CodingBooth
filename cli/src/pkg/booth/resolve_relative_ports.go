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
// For example, if the booth port is 10000 and run-args contains "-p +8080:8080",
// it becomes "-p 18080:8080".
func ResolveRelativePorts(ctx appctx.AppContext) appctx.AppContext {
	boothPort := ctx.PortNumber()
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
					if mapped, ok := resolveRelativeMapping(arg, boothPort); ok {
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
				if mapped, ok := resolveRelativeMapping(value, boothPort); ok {
					newArgs.Append("-p=" + mapped)
					changed = true
					return true
				}
			} else if strings.HasPrefix(arg, "--publish=+") {
				value := strings.TrimPrefix(arg, "--publish=")
				if mapped, ok := resolveRelativeMapping(value, boothPort); ok {
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

// resolveRelativeMapping resolves a +OFFSET:CONTAINER mapping to an absolute port mapping.
// Returns the resolved mapping and true if successful.
func resolveRelativeMapping(mapping string, boothPort int) (string, bool) {
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

	hostPort := boothPort + offset
	return fmt.Sprintf("%d:%s", hostPort, parts[1]), true
}
