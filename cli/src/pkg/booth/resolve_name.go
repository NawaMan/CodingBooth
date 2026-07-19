// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// ResolveNamePlaceholders expands `{…}` placeholders in the container name using
// values determined earlier in the run pipeline. It runs AFTER PortDetermination
// so `{port}` sees the concrete host port (including one chosen by NEXT / RANDOM).
//
// Supported placeholders:
//   - {port}    -> the resolved host port  (e.g. 12000)
//   - {project} -> the sanitized project name (folder-derived)
//   - {variant} -> the variant name (e.g. base, codeserver, desktop-xfce)
//
// This lets a name follow an auto-picked port in a single command, e.g.
//
//	booth --port NEXT --name '{project}-{port}'   ->  myproj-12000
//
// so several booths of the same project no longer collide on the container name,
// mirroring how booth-relative `+OFFSET` publishes let their ports follow the
// booth port. The template is stored literally in config.toml and expanded here,
// so a stored `name = "{project}-{port}"` re-resolves on every run.
//
// Names without a `{` are left untouched — the common case pays nothing.
func ResolveNamePlaceholders(ctx appctx.AppContext) appctx.AppContext {
	name := ctx.Name()
	if !strings.Contains(name, "{") {
		return ctx
	}

	replacer := strings.NewReplacer(
		"{port}", strconv.Itoa(ctx.PortNumber()),
		"{project}", ctx.ProjectName(),
		"{variant}", ctx.Variant(),
	)
	resolved := sanitizeContainerName(replacer.Replace(name))
	if resolved == name {
		return ctx
	}

	builder := ctx.ToBuilder()
	builder.Config.Name = resolved
	return builder.Build()
}

// sanitizeContainerName makes an expanded name safe for Docker, whose container
// names must match [a-zA-Z0-9][a-zA-Z0-9_.-]*. Any other character becomes '-',
// and a leading run of non-alphanumerics is trimmed so the first character is
// always valid. The `{project}`/`{port}`/`{variant}` values are already safe;
// this only guards literal parts of a user-supplied template.
func sanitizeContainerName(name string) string {
	var b strings.Builder
	for _, ch := range name {
		switch {
		case ch >= 'a' && ch <= 'z', ch >= 'A' && ch <= 'Z', ch >= '0' && ch <= '9',
			ch == '_', ch == '.', ch == '-':
			b.WriteRune(ch)
		default:
			b.WriteRune('-')
		}
	}
	sanitized := strings.TrimLeft(b.String(), "_.-")
	if sanitized == "" {
		return "booth"
	}
	return sanitized
}
