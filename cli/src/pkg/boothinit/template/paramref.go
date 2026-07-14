// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

// paramRef matches a ${NAME} reference inside a param value.
var paramRef = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)\}`)

// ParamRefNames returns the param names a value references, in order of appearance.
// "${SSH_PORT}" yields ["SSH_PORT"]; a value with no references yields nil.
func ParamRefNames(value string) []string {
	matches := paramRef.FindAllStringSubmatch(value, -1)
	if len(matches) == 0 {
		return nil
	}
	names := make([]string, 0, len(matches))
	for _, m := range matches {
		names = append(names, m[1])
	}
	return names
}

// ExpandRefs substitutes ${NAME} references in a single value using already-resolved
// params. Names that are not params are left untouched, as in ResolveParamRefs.
func ExpandRefs(value string, params map[string]string) string {
	return paramRef.ReplaceAllStringFunc(value, func(ref string) string {
		name := paramRef.FindStringSubmatch(ref)[1]
		if v, ok := params[name]; ok {
			return v
		}
		return ref
	})
}

// ResolveParamRefs resolves ${OTHER} references inside param values to a fixpoint,
// so one param's default can follow another's — an expose extension's host port can
// default to "${SSH_PORT}" and stay in step with the port the service actually listens
// on. Resolving to a fixpoint (rather than a single substitution pass over the map) is
// what makes the result independent of Go's random map iteration order.
//
// References to names that are not params are left as-is: a default may legitimately
// reference a runtime environment variable like ${HOME}, which must survive into the
// generated Boothfile or startup script untouched.
//
// Returns an error naming the cycle if the references are circular.
func ResolveParamRefs(params map[string]string) (map[string]string, error) {
	const (
		visiting = 1
		done     = 2
	)
	resolved := make(map[string]string, len(params))
	state := make(map[string]int, len(params))

	var resolve func(name string, path []string) (string, error)
	resolve = func(name string, path []string) (string, error) {
		switch state[name] {
		case done:
			return resolved[name], nil
		case visiting:
			return "", fmt.Errorf("param %q has a circular default: %s",
				path[0], strings.Join(append(path, name), " -> "))
		}
		state[name] = visiting

		var err error
		value := paramRef.ReplaceAllStringFunc(params[name], func(ref string) string {
			refName := paramRef.FindStringSubmatch(ref)[1]
			if _, isParam := params[refName]; !isParam {
				return ref // not a param — leave for the shell to expand at runtime
			}
			// Copy: sibling refs would otherwise share the backing array and
			// clobber each other's entry in the cycle path.
			next := append(append([]string{}, path...), name)
			refValue, refErr := resolve(refName, next)
			if refErr != nil {
				err = refErr
				return ref
			}
			return refValue
		})
		if err != nil {
			return "", err
		}

		resolved[name] = value
		state[name] = done
		return value, nil
	}

	// Sort so a cycle is always reported from the same entry point, and the error
	// message does not change from run to run.
	names := make([]string, 0, len(params))
	for name := range params {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		if _, err := resolve(name, nil); err != nil {
			return nil, err
		}
	}
	return resolved, nil
}
