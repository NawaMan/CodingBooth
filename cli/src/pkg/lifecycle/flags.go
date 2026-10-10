// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"flag"
	"fmt"
	"strings"
)

// engineFlag validates an explicit engine before any container is queried.
func engineFlag(flagSet *flag.FlagSet) *string {
	var engine string
	flagSet.Func("engine", "Container engine: docker, podman, apple (overrides config and CB_ENGINE)", func(value string) error {
		value = strings.ToLower(strings.TrimSpace(value))
		switch value {
		case "docker", "podman", "apple":
			engine = value
			return nil
		default:
			return fmt.Errorf("invalid engine %q (supported: docker, podman, apple)", value)
		}
	})
	return &engine
}

// parseLifecycleFlags accepts flags on either side of operands. The flag set,
// rather than a second list of flag names, decides which flags consume a value.
// A lone '-' is an operand; '--' protects every remaining operand literally.
func parseLifecycleFlags(flagSet *flag.FlagSet, args []string) error {
	var flags, positional []string
	for index := 0; index < len(args); index++ {
		arg := args[index]
		if arg == "--" {
			positional = append(positional, args[index+1:]...)
			break
		}
		if arg == "-" || !strings.HasPrefix(arg, "-") {
			positional = append(positional, arg)
			continue
		}
		flags = append(flags, arg)
		name, _, hasValue := strings.Cut(strings.TrimLeft(arg, "-"), "=")
		option := flagSet.Lookup(name)
		if option == nil || hasValue {
			continue
		}
		boolean, ok := option.Value.(interface{ IsBoolFlag() bool })
		if ok && boolean.IsBoolFlag() {
			continue
		}
		if index+1 < len(args) {
			index++
			flags = append(flags, args[index])
		} else {
			// Do not let the synthetic '--' below become a missing flag's value.
			return flagSet.Parse(flags)
		}
	}
	return flagSet.Parse(append(append(flags, "--"), positional...))
}
