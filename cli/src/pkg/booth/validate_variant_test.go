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
			name:         "valid notebook",
			inputVariant: "notebook",
			wantVariant:  "notebook",
			wantNotebook: true,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "valid codeserver",
			inputVariant: "codeserver",
			wantVariant:  "codeserver",
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
			name:         "alias default -> base",
			inputVariant: "default",
			wantVariant:  "base",
			wantNotebook: false,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "alias console -> base",
			inputVariant: "console",
			wantVariant:  "base",
			wantNotebook: false,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "alias terminal -> base",
			inputVariant: "terminal",
			wantVariant:  "base",
			wantNotebook: false,
			wantVscode:   false,
			wantDesktop:  false,
		},
		{
			name:         "alias ide -> codeserver",
			inputVariant: "ide",
			wantVariant:  "codeserver",
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

	// Separate test for terminal variant setting bash command
	t.Run("terminal sets bash command when no cmds", func(t *testing.T) {
		builder := &appctx.AppContextBuilder{
			CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
			BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
			RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
			Cmds:       ilist.NewAppendableList[ilist.List[string]](),
		}
		builder.Config.Variant = "terminal"
		ctx := builder.Build()

		gotCtx := ValidateVariant(ctx)

		if gotCtx.Variant() != "base" {
			t.Errorf("variant = %v, want base", gotCtx.Variant())
		}
		if gotCtx.Cmds().Length() != 1 {
			t.Fatalf("Cmds length = %d, want 1", gotCtx.Cmds().Length())
		}
		if gotCtx.Cmds().At(0).At(0) != "bash" {
			t.Errorf("Cmds[0][0] = %v, want bash", gotCtx.Cmds().At(0).At(0))
		}
	})

	t.Run("terminal preserves existing cmds", func(t *testing.T) {
		builder := &appctx.AppContextBuilder{
			CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
			BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
			RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
			Cmds:       ilist.NewAppendableList[ilist.List[string]](),
		}
		builder.Config.Variant = "terminal"
		builder.Cmds.Append(ilist.NewList[string]("zsh"))
		ctx := builder.Build()

		gotCtx := ValidateVariant(ctx)

		if gotCtx.Variant() != "base" {
			t.Errorf("variant = %v, want base", gotCtx.Variant())
		}
		if gotCtx.Cmds().Length() != 1 {
			t.Fatalf("Cmds length = %d, want 1", gotCtx.Cmds().Length())
		}
		if gotCtx.Cmds().At(0).At(0) != "zsh" {
			t.Errorf("Cmds[0][0] = %v, want zsh", gotCtx.Cmds().At(0).At(0))
		}
	})

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
		})
	}
}
