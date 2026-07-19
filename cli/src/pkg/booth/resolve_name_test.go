// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func buildCtxWithName(name, project, variant string, port int) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
		PortNumber: port,
	}
	builder.Config.Name = name
	builder.Config.ProjectName = project
	builder.Config.Variant = variant
	return builder.Build()
}

func TestResolveNamePlaceholders(t *testing.T) {
	tests := []struct {
		name    string
		tmpl    string
		project string
		variant string
		port    int
		want    string
	}{
		{"port only", "gp{port}", "myproj", "base", 12000, "gp12000"},
		{"project and port", "{project}-{port}", "myproj", "base", 12000, "myproj-12000"},
		{"variant and port", "{project}-{variant}-{port}", "myproj", "codeserver", 11000, "myproj-codeserver-11000"},
		{"no placeholder untouched", "fixed-name", "myproj", "base", 12000, "fixed-name"},
		{"repeated placeholder", "{port}-{port}", "myproj", "base", 10000, "10000-10000"},
		{"illegal literal chars sanitized", "my proj:{port}", "myproj", "base", 12000, "my-proj-12000"},
		{"leading illegal trimmed", "-{port}", "myproj", "base", 12000, "12000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := buildCtxWithName(tt.tmpl, tt.project, tt.variant, tt.port)
			got := ResolveNamePlaceholders(ctx).Name()
			if got != tt.want {
				t.Errorf("ResolveNamePlaceholders(%q) = %q, want %q", tt.tmpl, got, tt.want)
			}
		})
	}
}

func TestResolveNamePlaceholders_NoBraceReturnsSameCtx(t *testing.T) {
	ctx := buildCtxWithName("plain", "myproj", "base", 12000)
	if got := ResolveNamePlaceholders(ctx).Name(); got != "plain" {
		t.Errorf("expected plain name unchanged, got %q", got)
	}
}
