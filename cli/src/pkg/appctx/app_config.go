// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"fmt"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/kelseyhightower/envconfig"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

type AppConfig struct {

	// --------------------
	// General configuration
	// --------------------
	Dryrun  nillable.NillableBool   `toml:"dryrun,omitempty"  envconfig:"CB_DRYRUN"`
	Verbose nillable.NillableBool   `toml:"verbose,omitempty" envconfig:"CB_VERBOSE"`
	Config  nillable.NillableString `toml:"config,omitempty"  envconfig:"CB_CONFIG"`
	Code    nillable.NillableString `toml:"code,omitempty"    envconfig:"CB_CODE"`
	Version nillable.NillableString `toml:"version,omitempty" envconfig:"CB_VERSION"`

	// --------------------
	// Flags
	// --------------------
	KeepAlive    bool `toml:"keep-alive,omitempty"    envconfig:"CB_KEEP_ALIVE" default:"false"`
	SilenceBuild bool `toml:"silence-build,omitempty" envconfig:"CB_SILENCE_BUILD" default:"false"`
	Daemon       bool `toml:"daemon,omitempty"        envconfig:"CB_DAEMON" default:"false"`
	Pull         bool `toml:"pull,omitempty"          envconfig:"CB_PULL" default:"false"`
	Dind         bool `toml:"dind,omitempty"          envconfig:"CB_DIND" default:"false"`

	// --------------------
	// Image configuration
	// --------------------
	Dockerfile string `toml:"dockerfile,omitempty" envconfig:"CB_DOCKERFILE"`
	Image      string `toml:"image,omitempty"      envconfig:"CB_IMAGE"`
	Variant    string `toml:"variant,omitempty"    envconfig:"CB_VARIANT" default:"default"`

	// --------------------
	// Runtime values
	// --------------------
	ProjectName string `toml:"project-name,omitempty" envconfig:"CB_PROJECT_NAME"`
	HostUID     string `toml:"host-uid,omitempty"     envconfig:"CB_HOST_UID"`
	HostGID     string `toml:"host-gid,omitempty"     envconfig:"CB_HOST_GID"`
	Timezone    string `toml:"timezone,omitempty"     envconfig:"CB_TIMEZONE"`

	// --------------------
	// Container configuration
	// --------------------
	Name    string `toml:"name,omitempty"      envconfig:"CB_NAME"`
	Port    string `toml:"port,omitempty"      envconfig:"CB_PORT" default:"NEXT"`
	EnvFile string `toml:"env-file,omitempty"  envconfig:"CB_ENV_FILE"`
	Startup string `toml:"startup,omitempty"   envconfig:"CB_STARTUP"`

	// --------------------
	// TOML-friendly array fields
	// --------------------
	CommonArgs ilist.SemicolonStringList `toml:"common-args,omitempty" envconfig:"CB_COMMON_ARGS"`
	BuildArgs  ilist.SemicolonStringList `toml:"build-args,omitempty"  envconfig:"CB_BUILD_ARGS"`
	RunArgs    ilist.SemicolonStringList `toml:"run-args,omitempty"    envconfig:"CB_RUN_ARGS"`
	Cmds       ilist.SemicolonStringList `toml:"cmds,omitempty"        envconfig:"CB_CMDS"`
}

// Clone the content of the app config.
func (config *AppConfig) Clone() *AppConfig {
	copy := *config

	copy.CommonArgs = config.CommonArgs.Clone()
	copy.BuildArgs = config.BuildArgs.Clone()
	copy.RunArgs = config.RunArgs.Clone()
	copy.Cmds = config.Cmds.Clone()

	return &copy
}

// ReadFromEnvVars reads configuration from environment variables and populates the config (overriding existing values).
func ReadFromEnvVars(config *AppConfig) error {
	return envconfig.Process("", config)
}

// ReadFromToml reads configuration from a TOML file and populates the config (overriding existing values).
func ReadFromToml(path string, config *AppConfig) error {
	if _, err := toml.DecodeFile(path, config); err != nil {
		return err
	}
	return nil
}

// String returns a string representation of the app config.
func (config AppConfig) String() string {
	var str strings.Builder

	str.WriteString("==| AppConfig |==================================================\n")

	fmt.Fprintf(&str, "# General configuration ---------\n")
	fmt.Fprintf(&str, "    Dryrun:           %v\n", config.Dryrun)
	fmt.Fprintf(&str, "    Verbose:          %v\n", config.Verbose)
	fmt.Fprintf(&str, "    Config:           %v\n", config.Config)
	fmt.Fprintf(&str, "    Code:             %v\n", config.Code)
	fmt.Fprintf(&str, "    Version:          %q\n", config.Version)

	fmt.Fprintf(&str, "# Flags -------------------------\n")
	fmt.Fprintf(&str, "    KeepAlive:        %t\n", config.KeepAlive)
	fmt.Fprintf(&str, "    SilenceBuild:     %t\n", config.SilenceBuild)
	fmt.Fprintf(&str, "    Daemon:           %t\n", config.Daemon)
	fmt.Fprintf(&str, "    Pull:             %t\n", config.Pull)
	fmt.Fprintf(&str, "    Dind:             %t\n", config.Dind)

	fmt.Fprintf(&str, "# Image Configuration -----------\n")
	fmt.Fprintf(&str, "    Dockerfile:       %q\n", config.Dockerfile)
	fmt.Fprintf(&str, "    Image:            %q\n", config.Image)
	fmt.Fprintf(&str, "    Variant:          %q\n", config.Variant)

	fmt.Fprintf(&str, "# Runtime values ----------------\n")
	fmt.Fprintf(&str, "    ProjectName:      %q\n", config.ProjectName)
	fmt.Fprintf(&str, "    HostUID:          %q\n", config.HostUID)
	fmt.Fprintf(&str, "    HostGID:          %q\n", config.HostGID)
	fmt.Fprintf(&str, "    Timezone:         %q\n", config.Timezone)

	fmt.Fprintf(&str, "# Container Configuration -------\n")
	fmt.Fprintf(&str, "    Name:             %q\n", config.Name)
	fmt.Fprintf(&str, "    Port:             %q\n", config.Port)
	fmt.Fprintf(&str, "    EnvFile:          %q\n", config.EnvFile)
	fmt.Fprintf(&str, "    Startup:          %q\n", config.Startup)

	fmt.Fprintf(&str, "# TOML-friendly array fields ----\n")
	formatList(&str, "CommonArgs", config.CommonArgs.List, "    ")
	formatList(&str, "BuildArgs", config.BuildArgs.List, "    ")
	formatList(&str, "RunArgs", config.RunArgs.List, "    ")
	formatList(&str, "Cmds", config.Cmds.List, "    ")

	str.WriteString("==================================================================\n")

	return str.String()
}
