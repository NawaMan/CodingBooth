// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// ValidateVariant validates and normalizes the variant and returns updated AppContext.
func ValidateVariant(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()
	variant := ctx.Variant()

	// Step 1: Normalize variant aliases
	switch variant {
	case "base", "ide-notebook", "ide-codeserver", "desktop-xfce", "desktop-kde":
		// Valid variants, no change needed
	case "default", "console":
		variant = "base"
	case "ide":
		variant = "ide-codeserver"
	case "desktop":
		variant = "desktop-xfce"
	case "notebook", "codeserver":
		variant = "ide-" + variant
	case "xfce", "kde":
		variant = "desktop-" + variant
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown --variant '%s' (valid: base|ide-notebook|ide-codeserver|desktop-xfce|desktop-kde;\n", variant)
		fmt.Fprintln(os.Stderr, "       aliases: notebook|codeserver|xfce|kde)")
		os.Exit(1)
	}

	builder.Config.Variant = variant

	// Step 2: Set HAS_* flags based on variant
	switch {
	case variant == "base":
		builder.HasNotebook = false
		builder.HasVscode = false
		builder.HasDesktop = false
	case variant == "ide-notebook":
		builder.HasNotebook = true
		builder.HasVscode = false
		builder.HasDesktop = false
	case variant == "ide-codeserver":
		builder.HasNotebook = true
		builder.HasVscode = true
		builder.HasDesktop = false
	case strings.HasPrefix(variant, "desktop-"):
		builder.HasNotebook = true
		builder.HasVscode = true
		builder.HasDesktop = true
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown variant '%s'.\n", variant)
		os.Exit(1)
	}

	return builder.Build()
}
