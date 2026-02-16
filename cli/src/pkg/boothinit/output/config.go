// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"fmt"
	"sort"
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

	// Write --set overrides as raw TOML key=value pairs
	if len(cfg.Overrides) > 0 {
		b.WriteString("\n")
		keys := make([]string, 0, len(cfg.Overrides))
		for k := range cfg.Overrides {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			v := cfg.Overrides[k]
			switch val := v.(type) {
			case bool:
				fmt.Fprintf(&b, "%s = %t\n", k, val)
			case string:
				fmt.Fprintf(&b, "%s = %q\n", k, val)
			default:
				fmt.Fprintf(&b, "%s = %q\n", k, fmt.Sprintf("%v", val))
			}
		}
	}

	return b.String()
}

// writeStringArray writes a TOML array of strings.
// Paired flags (e.g., "-v" + "path", "-e" + "VAR=val") are kept on the same line.
func writeStringArray(b *strings.Builder, key string, values []string) {
	if len(values) == 1 {
		fmt.Fprintf(b, "%s = [%q]\n", key, values[0])
		return
	}

	// Group values into lines: paired flags stay together, standalone values get their own line.
	var lines []string
	for i := 0; i < len(values); i++ {
		if isPairedFlag(values[i]) && i+1 < len(values) {
			lines = append(lines, fmt.Sprintf("%q, %q", values[i], values[i+1]))
			i++ // skip the next value (already consumed)
		} else {
			lines = append(lines, fmt.Sprintf("%q", values[i]))
		}
	}

	if len(lines) == 1 {
		fmt.Fprintf(b, "%s = [%s]\n", key, lines[0])
		return
	}

	fmt.Fprintf(b, "%s = [\n", key)
	for i, line := range lines {
		if i < len(lines)-1 {
			fmt.Fprintf(b, "    %s,\n", line)
		} else {
			fmt.Fprintf(b, "    %s\n", line)
		}
	}
	b.WriteString("]\n")
}

// isPairedFlag returns true if the string is a flag that takes a subsequent value argument.
func isPairedFlag(s string) bool {
	return strings.HasPrefix(s, "-") && !strings.Contains(s, "=")
}
