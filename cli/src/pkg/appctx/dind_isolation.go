// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"strconv"
	"strings"
)

// DindVmMemoryMiB converts a size like 4g, 4096m or 2048mb to MiB, the unit
// Kata's default_memory annotation takes; 0 when it does not parse.
func DindVmMemoryMiB(size string) int {
	s := strings.ToLower(strings.TrimSuffix(strings.TrimSuffix(size, "b"), "B"))
	unit := 1.0 / (1 << 20) // bare number: bytes, as Docker reads -m
	if n := len(s); n > 0 {
		switch s[n-1] {
		case 'k':
			unit, s = 1.0/1024, s[:n-1]
		case 'm':
			unit, s = 1, s[:n-1]
		case 'g':
			unit, s = 1024, s[:n-1]
		case 't':
			unit, s = 1024*1024, s[:n-1]
		}
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil || v <= 0 {
		return 0
	}
	return int(v * unit)
}
