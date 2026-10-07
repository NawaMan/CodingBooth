// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

// stripRecipeComments removes # comments from recipe and --select text.
// A # outside quotes comments out the rest of the line. A # inside quotes
// stays, so a param value can contain one. The newline itself stays, so the
// following line is still a selection.
func stripRecipeComments(input string) string {
	var b []byte
	quote := byte(0)
	for i := 0; i < len(input); i++ {
		c := input[i]
		if quote != 0 {
			b = append(b, c)
			if c == quote {
				quote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			quote = c
			b = append(b, c)
			continue
		}
		if c == '#' {
			for i+1 < len(input) && input[i+1] != '\n' {
				i++
			}
			continue
		}
		b = append(b, c)
	}
	return string(b)
}
