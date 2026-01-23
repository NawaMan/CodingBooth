// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func TestValidateVariant(t *testing.T) {
	tests := []struct {
		name         string
		inputVariant string
		wantVariant  string
		wantNotebook bool
		wantVscode   bool
		wantDesktop  bool
	}{
		// Valid variants
		{
			name:         "valid base",
			inputVariant: "base",
			wantVariant:  "base",
			wantNotebook: false,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "valid ide-notebook",
			inputVariant: "ide-notebook",
			wantVariant:  "ide-notebook",
			wantNotebook: true,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "valid ide-codeserver",
			inputVariant: "ide-codeserver",
			wantVariant:  "ide-codeserver",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  false,
		},
		{
			name:         "valid desktop-xfce",
			inputVariant: "desktop-xfce",
			wantVariant:  "desktop-xfce",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  true,
		},
		{
			name:         "valid desktop-kde",
			inputVariant: "desktop-kde",
			wantVariant:  "desktop-kde",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  true,
		},

		// Aliases
		{
			name:         "alias console -> base",
			inputVariant: "console",
			wantVariant:  "base",
			wantNotebook: false,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "alias default -> base",
			inputVariant: "default",
			wantVariant:  "base",
			wantNotebook: false,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "alias ide -> ide-codeserver",
			inputVariant: "ide",
			wantVariant:  "ide-codeserver",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  false,
		},
		{
			name:         "alias desktop -> desktop-xfce",
			inputVariant: "desktop",
			wantVariant:  "desktop-xfce",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  true,
		},
		{
			name:         "alias notebook -> ide-notebook",
			inputVariant: "notebook",
			wantVariant:  "ide-notebook",
			wantNotebook: true,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "alias codeserver -> ide-codeserver",
			inputVariant: "codeserver",
			wantVariant:  "ide-codeserver",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  false,
		},
		{
			name:         "alias xfce -> desktop-xfce",
			inputVariant: "xfce",
			wantVariant:  "desktop-xfce",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  true,
		},
		{
			name:         "alias kde -> desktop-kde",
			inputVariant: "kde",
			wantVariant:  "desktop-kde",
			wantNotebook: true,
			wantVscode:   true,
			wantDesktop:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup context with input variant
			builder := &appctx.AppContextBuilder{
				CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
				BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
				RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
				Cmds:       ilist.NewAppendableList[ilist.List[string]](),
			}
			builder.Config.Variant = tt.inputVariant
			ctx := builder.Build()

			// Execute
			gotCtx := ValidateVariant(ctx)

			// Assert Variant
			if gotCtx.Variant() != tt.wantVariant {
				t.Errorf("ValidateVariant() variant = %v, want %v", gotCtx.Variant(), tt.wantVariant)
			}

			// Assert Flags
			if gotCtx.HasNotebook() != tt.wantNotebook {
				t.Errorf("ValidateVariant() HasNotebook = %v, want %v", gotCtx.HasNotebook(), tt.wantNotebook)
			}
			if gotCtx.HasVscode() != tt.wantVscode {
				t.Errorf("ValidateVariant() HasVscode = %v, want %v", gotCtx.HasVscode(), tt.wantVscode)
			}
			if gotCtx.HasDesktop() != tt.wantDesktop {
				t.Errorf("ValidateVariant() HasDesktop = %v, want %v", gotCtx.HasDesktop(), tt.wantDesktop)
			}
		})
	}
}
