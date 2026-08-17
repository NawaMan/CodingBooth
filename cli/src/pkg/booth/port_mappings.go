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

// Docker binds the *host* side of a published port, so the host side is what can collide.
// Two mappings that bind the same host port cannot both start — docker fails the container
// with "address already in use", whichever way the duplicate arose:
//
//   - a template and a --expose flag publishing the same port
//     (cloudbeaver+expose --expose 8978:8978)
//   - two templates that default to the same host port
//     (nginx+expose/apache+expose — both 8080)
//   - an absolute mapping and a +OFFSET one that lands on it
//     (-p 28978:8978 with -p +8978:8978 on a booth at port 20000)
//
// The last of those is only knowable once the booth port is known, which is why this runs
// at start rather than at config time.
//
// Identical mappings are redundant rather than conflicting: collapsing them is what the
// user meant, so they are deduped silently. Everything else is refused with both mappings
// named, because docker's own message ("driver failed programming external connectivity")
// does not say which two ports are at fault.

// PortMapping is a parsed "[IP:]HOST:CONTAINER[/PROTO]" docker port mapping.
type PortMapping struct {
	Raw       string // as written, e.g. "127.0.0.1:18978:8978"
	IP        string // "" when bound on every interface
	Host      int    // the offset, when Relative
	Container string // kept as text: may carry a "/udp" suffix
	Proto     string // "tcp" unless the container side says otherwise
	Relative  bool   // host side was "+OFFSET": the port it claims is not known yet
	Source    string // where it came from, for error messages
}

// ParsePortMapping parses a docker port mapping. Forms it does not understand (a port
// range, say) are reported as not-ok and left alone by callers — this is a safety net,
// not a validator of docker's whole surface.
//
// A "+OFFSET" host side is flagged Relative rather than accepted as a port: strconv.Atoi
// reads "+4567" as 4567, so an unresolved offset would otherwise pass itself off as the
// absolute port 4567 and be compared against real ones.
func ParsePortMapping(raw string) (PortMapping, bool) {
	parts := strings.Split(raw, ":")

	var ip, host, container string
	switch len(parts) {
	case 2:
		host, container = parts[0], parts[1]
	case 3:
		ip, host, container = parts[0], parts[1], parts[2]
	default:
		return PortMapping{}, false
	}

	relative := strings.HasPrefix(host, "+")
	hostPort, err := strconv.Atoi(strings.TrimPrefix(host, "+"))
	if err != nil {
		return PortMapping{}, false
	}

	proto := "tcp"
	if slash := strings.Index(container, "/"); slash >= 0 {
		proto = container[slash+1:]
	}

	return PortMapping{
		Raw:       raw,
		IP:        ip,
		Host:      hostPort,
		Container: container,
		Proto:     proto,
		Relative:  relative,
	}, true
}

// bindsSameHostPort reports whether two mappings compete for the same host binding.
// A wildcard bind (no IP, or 0.0.0.0) covers every interface, so it collides with any
// address; two mappings pinned to *different* addresses can coexist, as can the same port
// on different protocols.
func bindsSameHostPort(a, b PortMapping) bool {
	if a.Relative || b.Relative {
		return false // the port it claims is not known until the booth port is
	}
	if a.Host != b.Host || a.Proto != b.Proto {
		return false
	}
	if isWildcardIP(a.IP) || isWildcardIP(b.IP) {
		return true
	}
	return a.IP == b.IP
}

func isWildcardIP(ip string) bool {
	return ip == "" || ip == "0.0.0.0" || ip == "::"
}

// PortConflicts returns the pairs of mappings that bind the same host port without being
// the same mapping. Identical mappings are not conflicts — see DedupePortMappings.
func PortConflicts(mappings []PortMapping) [][2]PortMapping {
	var conflicts [][2]PortMapping
	for i := 0; i < len(mappings); i++ {
		for j := i + 1; j < len(mappings); j++ {
			a, b := mappings[i], mappings[j]
			if a.Raw == b.Raw {
				continue // redundant, not conflicting
			}
			if bindsSameHostPort(a, b) {
				conflicts = append(conflicts, [2]PortMapping{a, b})
			}
		}
	}
	return conflicts
}

// DedupePortMappings drops repeats of a mapping already published by an earlier argument,
// regardless of which flag form spells it ("-p" vs "--publish" — docker treats them the
// same, but the compiler's dedup runs before params are expanded and so cannot see that
// "${NGINX_PORT}:80" and "${APACHE_PORT}:80" are both "8080:80").
//
// Returns the arguments with duplicates removed, and how many were removed.
func DedupePortMappings(args []string) ([]string, int) {
	seen := make(map[string]bool)
	out := make([]string, 0, len(args))
	removed := 0

	for i := 0; i < len(args); i++ {
		flag := args[i]
		if (flag == "-p" || flag == "--publish") && i+1 < len(args) {
			mapping := args[i+1]
			if seen[mapping] {
				removed++
				i++ // skip the value too
				continue
			}
			seen[mapping] = true
			out = append(out, flag, mapping)
			i++
			continue
		}
		out = append(out, flag)
	}
	return out, removed
}

// collectPortMappings pulls every parseable "-p"/"--publish" mapping out of run-args.
func collectPortMappings(runArgs ilist.List[ilist.List[string]], source string) []PortMapping {
	var mappings []PortMapping

	runArgs.Range(func(_ int, argList ilist.List[string]) bool {
		prevWasPort := false
		argList.Range(func(_ int, arg string) bool {
			if prevWasPort {
				prevWasPort = false
				if m, ok := ParsePortMapping(arg); ok {
					m.Source = source
					mappings = append(mappings, m)
				}
				return true
			}
			if arg == "-p" || arg == "--publish" {
				prevWasPort = true
			}
			return true
		})
		return true
	})

	return mappings
}

// NormalizePortMappings collapses redundant published ports and refuses to start a booth
// whose published ports cannot all bind. It must run after ResolveRelativePorts, so that
// a +OFFSET mapping is compared as the port it will actually claim.
func NormalizePortMappings(ctx appctx.AppContext) appctx.AppContext {
	runArgs := ctx.RunArgs()

	// Rebuild run-args without repeats of a mapping an earlier argument already published.
	result := ilist.NewAppendableList[ilist.List[string]]()
	seen := make(map[string]bool)
	changed := false

	runArgs.Range(func(_ int, argList ilist.List[string]) bool {
		args := make([]string, 0, argList.Length())
		argList.Range(func(_ int, arg string) bool {
			args = append(args, arg)
			return true
		})

		kept := make([]string, 0, len(args))
		for i := 0; i < len(args); i++ {
			flag := args[i]
			if (flag == "-p" || flag == "--publish") && i+1 < len(args) {
				mapping := args[i+1]
				if seen[mapping] {
					changed = true
					i++
					continue
				}
				seen[mapping] = true
				kept = append(kept, flag, mapping)
				i++
				continue
			}
			kept = append(kept, flag)
		}
		if len(kept) > 0 {
			result.Append(ilist.NewList(kept...))
		}
		return true
	})

	if changed {
		builder := ctx.ToBuilder()
		builder.RunArgs = result
		ctx = builder.Build()
	}

	// The booth publishes its own port too, and it is added later in the run — so a
	// run-args mapping that lands on it would otherwise reach docker unchallenged.
	mappings := collectPortMappings(ctx.RunArgs(), "run-args")
	if !ctx.Dind() && !ctx.Egress() {
		containerPort := 10000
		if ctx.Public() {
			containerPort = 10443
		}
		boothMapping := formatPortMapping(ctx.Public(), ctx.PortNumber(), containerPort)
		if m, ok := ParsePortMapping(boothMapping); ok {
			m.Source = "the booth's own port"
			mappings = append(mappings, m)
		}
	}

	if conflicts := PortConflicts(mappings); len(conflicts) > 0 {
		for _, c := range conflicts {
			fmt.Fprintf(os.Stderr,
				"Error: host port %d is published twice — %q (%s) and %q (%s).\n",
				c[0].Host, c[0].Raw, c[0].Source, c[1].Raw, c[1].Source)
		}
		fmt.Fprintln(os.Stderr,
			"Docker cannot bind one host port twice. Move one of them — an expose extension takes\n"+
				"a host port directly (e.g. cloudbeaver+expose:19000, or +expose:+9000 for base-relative).")
		os.Exit(1)
	}

	return ctx
}
