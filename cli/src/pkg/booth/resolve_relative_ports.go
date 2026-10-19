// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
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
					if mapped, ok := resolveOrExit(arg, offsetBase); ok {
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
				if mapped, ok := resolveOrExit(value, offsetBase); ok {
					newArgs.Append("-p=" + mapped)
					changed = true
					return true
				}
			} else if strings.HasPrefix(arg, "--publish=+") {
				value := strings.TrimPrefix(arg, "--publish=")
				if mapped, ok := resolveOrExit(value, offsetBase); ok {
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

// relativeOffsetOf reads the OFFSET and CONTAINER halves out of a
// "+OFFSET:CONTAINER" mapping. Anything that is not one of those — a plain
// "8080:8080", a "+8080" with no container port, a non-numeric offset — comes
// back ok=false and is left for docker to accept or reject on its own terms.
func relativeOffsetOf(mapping string) (offset int, container string, ok bool) {
	rest, hasPlus := strings.CutPrefix(mapping, "+")
	if !hasPlus {
		return 0, "", false
	}

	parts := strings.SplitN(rest, ":", 2)
	if len(parts) != 2 {
		return 0, "", false
	}

	offset, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0, "", false
	}

	return offset, parts[1], true
}

// resolveRelativeMapping resolves a +OFFSET:CONTAINER mapping against the offset
// base to an absolute port mapping. Returns the resolved mapping and true if
// successful; a mapping that is relative but lands past the port ceiling comes
// back as an error.
//
// The ceiling has to be checked here, and not left to docker. A booth that drew
// booth port 65000 with "-p +8888:18888" in its config asked for host port 73888
// and died on docker's "invalid hostPort: 73888" — a number that appears in no
// config file, with nothing to say which mapping produced it or that the booth
// port was the variable. NEXT / RANDOM now reserve the headroom these offsets
// need (see maxRelativeOffset), so this fires only for a base the user pinned
// themselves.
func resolveRelativeMapping(mapping string, offsetBase int) (string, bool, error) {
	offset, container, ok := relativeOffsetOf(mapping)
	if !ok {
		return "", false, nil
	}

	hostPort := offsetBase + offset
	if hostPort > maxPortNumber {
		return "", false, fmt.Errorf(
			"Error: published port '%s' resolves to host port %d, which is above %d (offset base %d). Lower --port, or set --offset-base.",
			mapping, hostPort, maxPortNumber, offsetBase)
	}

	return fmt.Sprintf("%d:%s", hostPort, container), true, nil
}

// resolveOrExit resolves a relative mapping, or stops the run with the reason. A
// mapping that is not relative at all comes back ok=false, for the caller to pass
// through untouched.
func resolveOrExit(mapping string, offsetBase int) (string, bool) {
	mapped, ok, err := resolveRelativeMapping(mapping, offsetBase)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}
	return mapped, ok
}

// maxRelativeOffset reports the largest "+OFFSET" that any published port in
// run-args — or --browser-port — counts off the offset base, and whether there
// was one at all.
//
// NEXT / RANDOM settle the booth port before any of these offsets are resolved,
// and while the offset base follows the booth port (the default) a high pick
// pushes them over the ceiling. So the scan needs to know the headroom up front:
// it is the difference between a booth that starts wherever it fits and one that
// dies on "invalid hostPort" roughly one run in six.
func maxRelativeOffset(ctx appctx.AppContext) (int, bool) {
	largest := 0
	found := false
	note := func(mapping string) {
		offset, _, ok := relativeOffsetOf(mapping)
		if !ok {
			return
		}
		if !found || offset > largest {
			largest = offset
		}
		found = true
	}

	ctx.RunArgs().Range(func(_ int, argList ilist.List[string]) bool {
		prevWasPort := false
		argList.Range(func(_ int, arg string) bool {
			if prevWasPort {
				prevWasPort = false
				note(arg)
				return true
			}
			switch {
			case arg == "-p" || arg == "--publish":
				prevWasPort = true
			case strings.HasPrefix(arg, "-p=+"):
				note(strings.TrimPrefix(arg, "-p="))
			case strings.HasPrefix(arg, "--publish=+"):
				note(strings.TrimPrefix(arg, "--publish="))
			}
			return true
		})
		return true
	})

	// --browser-port +OFFSET counts off the same base (see parseBrowserPort), so a
	// pick that puts it out of range is just as broken as one docker refuses. The
	// ":0" is only there to make it a mapping relativeOffsetOf will read.
	if rest, ok := strings.CutPrefix(strings.TrimSpace(ctx.BrowserPort()), "+"); ok {
		note("+" + rest + ":0")
	}

	return largest, found
}
