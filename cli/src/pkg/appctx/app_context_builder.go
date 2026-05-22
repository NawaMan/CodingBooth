// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// ProfileEntry is one resolved profile, in the order it should be applied.
// Either ConfigPath or EnvPath may be empty if the corresponding file is
// absent on disk for that profile.
type ProfileEntry struct {
	Name       string
	ConfigPath string
	EnvPath    string
}

// AppContextBuilder is a mutable builder for constructing AppContext instances.
type AppContextBuilder struct {

	// constant
	PrebuildRepo string
	CbVersion    string
	SetupsDir    string
	Version      string

	// taken from the script runtime
	ScriptName string
	ScriptDir  string
	LibDir     string

	// Profiles resolved from --profile / BOOTH_PROFILES, in apply order.
	// Empty when no profile is selected.
	Profiles []ProfileEntry

	// derived from variant
	HasNotebook bool
	HasVscode   bool
	HasDesktop  bool

	// derived from DinD
	CreatedDindNet    bool
	CreatedSandboxNet bool

	// derived from image determination of image
	RunMode    string
	LocalBuild bool
	ImageMode  string

	// derived from all the context processing
	CommonArgs *ilist.AppendableList[ilist.List[string]]
	BuildArgs  *ilist.AppendableList[ilist.List[string]]
	RunArgs    *ilist.AppendableList[ilist.List[string]]
	Cmds       *ilist.AppendableList[ilist.List[string]]

	// derived from port determination
	PortGenerated bool
	PortNumber    int

	// Configurable
	Config AppConfig
}

// Build creates an immutable AppContext snapshot from this builder.
func (builder *AppContextBuilder) Build() AppContext {
	return NewAppContext(builder)
}

// Clone the content of the app context builder.
func (builder *AppContextBuilder) Clone() *AppContextBuilder {
	copied := *builder

	copied.CommonArgs = cloneAppendableList(builder.CommonArgs)
	copied.BuildArgs = cloneAppendableList(builder.BuildArgs)
	copied.RunArgs = cloneAppendableList(builder.RunArgs)
	copied.Cmds = cloneAppendableList(builder.Cmds)

	copied.Config = *builder.Config.Clone()

	if builder.Profiles != nil {
		copied.Profiles = append([]ProfileEntry(nil), builder.Profiles...)
	}

	return &copied
}

// Clone the content of the appendable list.
func cloneAppendableList(list *ilist.AppendableList[ilist.List[string]]) *ilist.AppendableList[ilist.List[string]] {
	if list == nil {
		return ilist.NewAppendableList[ilist.List[string]]()
	}
	return list.Clone()
}
