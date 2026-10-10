// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"fmt"
	"io"
)

// queryTarget selects an existing booth without starting or registering a session.
// With both a name and --code, the code path is an identity check, not an
// alternative lookup that could silently select a different booth.
func queryTarget(name, code, engine string, positional []string, state string, stderr io.Writer) (managedContainer, error) {
	codePath, err := resolveCodePathFlag(code)
	if err != nil {
		return managedContainer{}, err
	}
	containers, err := managedContainersAcross(resolveLifecycleEngines(codePath, engine), false, stderr)
	if err != nil {
		return managedContainer{}, commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}
	lookupPath := codePath
	if name != "" || len(positional) > 0 {
		lookupPath = ""
	}
	target, err := resolveSingleContainer(containers, name, lookupPath, positional, state)
	if err != nil {
		return managedContainer{}, commandExit(1, err.Error())
	}
	if codePath != "" && normalizeCodePath(target.CodePath) != codePath {
		return managedContainer{}, commandExit(1, fmt.Sprintf("Error: booth %q was created from code path %q, not %q.", target.Name, target.CodePath, codePath))
	}
	return target, nil
}
