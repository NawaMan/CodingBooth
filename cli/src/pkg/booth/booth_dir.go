// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"path/filepath"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// hostBoothDir is the .booth directory this run reads and mounts.
// --booth-dir wins, so express can keep the project's .booth unread.
func hostBoothDir(ctx appctx.AppContext) string {
	if dir := ctx.ExplicitBoothDir(); dir != "" {
		return dir
	}
	code := ctx.Code()
	if code == "" {
		return ""
	}
	return filepath.Join(code, ".booth")
}
