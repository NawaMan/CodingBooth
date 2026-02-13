// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"fmt"
	"strings"
)

// SerializeConfigToml produces the content of a .booth/config.toml file.
// Only non-empty/non-zero fields are included.
func SerializeConfigToml(cfg *ConfigToml, command, adjustCommand string) string {
	if cfg == nil {
		return ""
	}

	var b strings.Builder
	b.WriteString(formatGeneratedHeader("#", command, adjustCommand))
	b.WriteString("\n")

	if cfg.Variant != "" {
		fmt.Fprintf(&b, "variant = %q\n", cfg.Variant)
	}
	if cfg.Port != "" {
		fmt.Fprintf(&b, "port = %q\n", cfg.Port)
	}
	if cfg.Timezone != "" {
		fmt.Fprintf(&b, "timezone = %q\n", cfg.Timezone)
	}
	if cfg.Dind {
		fmt.Fprintf(&b, "dind = true\n")
	}

	if len(cfg.Cmds) > 0 {
		b.WriteString("\n")
		writeStringArray(&b, "cmds", cfg.Cmds)
	}

	if len(cfg.BuildArgs) > 0 {
		b.WriteString("\n")
		writeStringArray(&b, "build-args", cfg.BuildArgs)
	}

	if len(cfg.RunArgs) > 0 {
		b.WriteString("\n")
		writeStringArray(&b, "run-args", cfg.RunArgs)
	}

	return b.String()
}

// writeStringArray writes a TOML array of strings.
func writeStringArray(b *strings.Builder, key string, values []string) {
	if len(values) == 1 {
		fmt.Fprintf(b, "%s = [%q]\n", key, values[0])
		return
	}

	fmt.Fprintf(b, "%s = [\n", key)
	for i, v := range values {
		if i < len(values)-1 {
			fmt.Fprintf(b, "    %q,\n", v)
		} else {
			fmt.Fprintf(b, "    %q\n", v)
		}
	}
	b.WriteString("]\n")
}
