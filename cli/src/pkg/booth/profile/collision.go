// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package profile

import (
	"path"
	"strconv"
	"strings"
)

// Collision is one entry of a later layer that claims something an earlier layer
// already claimed, with a different value.
type Collision struct {
	What    string // what both entries claim, e.g. "environment variable LOG"
	Earlier string // the earlier layer's entry as written, e.g. "-e LOG=info"
	Later   string // the later layer's entry as written, e.g. "-e LOG=debug"
}

// FindCollisions compares the docker-style arguments of a later layer (a profile
// overlay) against those already accumulated from earlier layers, and reports every
// entry of the later layer that claims something an earlier one already does.
//
// Profile overlays merge these lists by concatenation, so without this check the
// outcome of a repeated claim was left to whichever layer happened to handle the
// flag — Docker keeps the last -e, booth keeps the first bind mount, and a repeated
// -p was published twice. Naming the collision up front replaces that with one rule.
//
// What counts as a claim:
//
//	-e / --env KEY[=VAL]        the variable KEY
//	-l / --label KEY[=VAL]      the label KEY
//	--build-arg KEY[=VAL]       the build arg KEY
//	-v / --volume SRC:TARGET    the container mount target
//	-p / --publish [IP:]H:C     the host port H, and the container port C
//
// An entry that repeats an earlier one exactly is redundant, not a collision.
// Repeats within one layer are not reported: only a layer colliding with the layers
// before it. Other flags (--cpus, --network, ...) are not examined, and an entry that
// cannot be parsed with confidence is skipped rather than guessed at.
func FindCollisions(earlier, later []string) []Collision {
	prior := claimsOf(earlier)
	var out []Collision
	seen := map[[2]string]bool{}

	for _, l := range claimsOf(later) {
		for _, e := range prior {
			if !e.collidesWith(l) {
				continue
			}
			pair := [2]string{e.text, l.text}
			if seen[pair] {
				continue // one mapping can clash on both host and container port; report once
			}
			seen[pair] = true
			out = append(out, Collision{What: l.what, Earlier: e.text, Later: l.text})
		}
	}
	return out
}

// claim is one thing a single flag entry lays claim to.
type claim struct {
	kind string // "env", "label", "build-arg", "volume", "host-port", "container-port"
	key  string // identity within the kind
	id   string // identity of the whole entry: equal ids are redundant, not a collision
	text string // the entry as written, for messages
	what string // human label for messages
	ip   string // host-port claims only: the bind address ("" = every interface)
}

func (a claim) collidesWith(b claim) bool {
	if a.kind != b.kind || a.key != b.key || a.id == b.id {
		return false
	}
	if a.kind == "host-port" {
		return isWildcard(a.ip) || isWildcard(b.ip) || a.ip == b.ip
	}
	return true
}

func isWildcard(ip string) bool {
	return ip == "" || ip == "0.0.0.0" || ip == "::"
}

var flagKinds = map[string]string{
	"-e": "env", "--env": "env",
	"-l": "label", "--label": "label",
	"--build-arg": "build-arg",
	"-v":          "volume", "--volume": "volume",
	"-p": "publish", "--publish": "publish",
}

// claimsOf extracts the claims of every recognised flag in args. Recognised forms:
// "-e V", "--env V", "--env=V" and the attached short form "-eV".
func claimsOf(args []string) []claim {
	var out []claim
	for i := 0; i < len(args); i++ {
		flag, value, ok := splitFlag(args, &i)
		if !ok {
			continue
		}
		text := flag + " " + value
		switch flagKinds[flag] {
		case "env":
			out = append(out, keyedClaim("env", "environment variable", value, text))
		case "label":
			out = append(out, keyedClaim("label", "label", value, text))
		case "build-arg":
			out = append(out, keyedClaim("build-arg", "build arg", value, text))
		case "volume":
			if target, ok := mountTarget(value); ok {
				out = append(out, claim{kind: "volume", key: target, id: value, text: text,
					what: "mount target " + target})
			}
		case "publish":
			out = append(out, publishClaims(value, text)...)
		}
	}
	return out
}

// splitFlag reads the flag at args[*i] and its value, advancing *i past the value
// when it was a separate argument. ok is false for anything not recognised.
func splitFlag(args []string, i *int) (flag, value string, ok bool) {
	arg := args[*i]
	if _, known := flagKinds[arg]; known {
		if *i+1 >= len(args) {
			return "", "", false
		}
		*i++
		return arg, args[*i], true
	}
	if eq := strings.Index(arg, "="); eq > 0 && strings.HasPrefix(arg, "--") {
		if _, known := flagKinds[arg[:eq]]; known {
			return arg[:eq], arg[eq+1:], true
		}
	}
	if len(arg) > 2 && arg[0] == '-' && arg[1] != '-' {
		if _, known := flagKinds["-"+arg[1:2]]; known {
			return "-" + arg[1:2], arg[2:], true
		}
	}
	return "", "", false
}

func keyedClaim(kind, label, value, text string) claim {
	key := value
	if eq := strings.Index(value, "="); eq >= 0 {
		key = value[:eq]
	}
	return claim{kind: kind, key: key, id: value, text: text, what: label + " " + key}
}

// mountTarget returns the container path of a "SRC:TARGET[:OPTS]" mount spec. An
// anonymous volume (no colon) has no source to compete over and is skipped.
func mountTarget(spec string) (string, bool) {
	rest := spec
	if hasDrive(rest) { // Windows host path C:\dir or C:/dir — its colon is not a separator
		rest = rest[2:]
	}
	i := strings.Index(rest, ":")
	if i < 0 {
		return "", false
	}
	rest = rest[i+1:]
	offset := 0
	if hasDrive(rest) { // Windows container path
		offset = 2
	}
	if j := strings.Index(rest[offset:], ":"); j >= 0 {
		rest = rest[:offset+j]
	}
	if rest == "" {
		return "", false
	}
	if strings.HasPrefix(rest, "/") {
		rest = path.Clean(rest) // "/cfg/" and "/cfg" are one target
	}
	return rest, true
}

func hasDrive(s string) bool {
	return len(s) >= 3 && s[1] == ':' && (s[2] == '\\' || s[2] == '/') &&
		((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z'))
}

// publishClaims parses "[IP:]HOST:CONTAINER[/PROTO]". A "+OFFSET" host side is not a
// port yet (booth resolves it against the booth port later), so it claims only its
// container port. Forms it does not understand, such as ranges, claim nothing.
func publishClaims(spec, text string) []claim {
	parts := strings.Split(spec, ":")
	var ip, host, container string
	switch len(parts) {
	case 2:
		host, container = parts[0], parts[1]
	case 3:
		ip, host, container = parts[0], parts[1], parts[2]
	default:
		return nil
	}

	proto := "tcp"
	if slash := strings.Index(container, "/"); slash >= 0 {
		container, proto = container[:slash], container[slash+1:]
	}
	if _, err := strconv.Atoi(container); err != nil || container == "" {
		return nil
	}
	if isWildcard(ip) {
		ip = ""
	}

	relative := strings.HasPrefix(host, "+")
	hostPort, err := strconv.Atoi(strings.TrimPrefix(host, "+"))
	if err != nil {
		return nil
	}

	// One id for the whole mapping, so "8080:80" and "8080:80/tcp" are the same entry.
	id := ip + "|" + host + "|" + container + "|" + proto
	out := []claim{{
		kind: "container-port", key: container + "/" + proto, id: id, text: text,
		what: "container port " + container + "/" + proto,
	}}
	if !relative {
		out = append([]claim{{
			kind: "host-port", key: strconv.Itoa(hostPort) + "/" + proto, id: id, text: text,
			what: "host port " + strconv.Itoa(hostPort) + "/" + proto, ip: ip,
		}}, out...)
	}
	return out
}
