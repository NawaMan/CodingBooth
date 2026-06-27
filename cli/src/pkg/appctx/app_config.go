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
	"github.com/nawaman/codingbooth/src/pkg/shellexpand"
)

// ExpandEnvScalars expands environment variables, defaults, required-var
// errors, and tilde in all scalar string fields of AppConfig per
// docs/BOOTH_VARS.md. Array fields (CommonArgs, BuildArgs, RunArgs, Cmds)
// are already expanded during TOML/env-var unmarshaling and are not
// re-touched here.
func (config *AppConfig) ExpandEnvScalars() error {
	expandStr := func(field string, s *string) error {
		if *s == "" {
			return nil
		}
		v, err := shellexpand.Expand(*s, shellexpand.DefaultLookup, shellexpand.SourceRef{Field: field})
		if err != nil {
			return err
		}
		*s = v
		return nil
	}
	expandNillable := func(field string, ns *nillable.NillableString) error {
		if !ns.IsSet() {
			return nil
		}
		v, err := shellexpand.Expand(ns.ValueOrPanic(), shellexpand.DefaultLookup, shellexpand.SourceRef{Field: field})
		if err != nil {
			return err
		}
		*ns = nillable.NewNillableString(v)
		return nil
	}

	scalars := []struct {
		field string
		ptr   *string
	}{
		{"dockerfile", &config.Dockerfile},
		{"boothfile", &config.Boothfile},
		{"image", &config.Image},
		{"variant", &config.Variant},
		{"project-name", &config.ProjectName},
		{"host-uid", &config.HostUID},
		{"host-gid", &config.HostGID},
		{"timezone", &config.Timezone},
		{"name", &config.Name},
		{"port", &config.Port},
		{"env-file", &config.EnvFile},
		{"startup", &config.Startup},
		{"egress-mode", &config.EgressMode},
		{"egress-enforcement", &config.EgressEnforcement},
		{"egress-allowlist-file", &config.EgressAllowlistFile},
		{"egress-policy-file", &config.EgressPolicyFile},
	}
	for _, s := range scalars {
		if err := expandStr(s.field, s.ptr); err != nil {
			return err
		}
	}

	nillables := []struct {
		field string
		ptr   *nillable.NillableString
	}{
		{"code", &config.Code},
		{"version", &config.Version},
		{"config", &config.Config},
	}
	for _, n := range nillables {
		if err := expandNillable(n.field, n.ptr); err != nil {
			return err
		}
	}

	return nil
}

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
	KeepAlive         bool   `toml:"keep-alive,omitempty"          envconfig:"CB_KEEP_ALIVE" default:"false"`
	SilenceBuild      bool   `toml:"silence-build,omitempty"       envconfig:"CB_SILENCE_BUILD" default:"false"`
	Daemon            bool   `toml:"daemon,omitempty"              envconfig:"CB_DAEMON" default:"false"`
	Pull              bool   `toml:"pull,omitempty"                envconfig:"CB_PULL" default:"false"`
	Dind              bool   `toml:"dind,omitempty"                envconfig:"CB_DIND" default:"false"`
	Sudo              bool   `toml:"sudo,omitempty"                envconfig:"CB_SUDO" default:"true"`
	Egress            bool   `toml:"egress,omitempty"           envconfig:"CB_EGRESS" default:"false"`
	EgressMode        string `toml:"egress-mode,omitempty"        envconfig:"CB_EGRESS_MODE"`
	EgressEnforcement string `toml:"egress-enforcement,omitempty" envconfig:"CB_EGRESS_ENFORCEMENT"`
	WritableBooth     bool   `toml:"writable-booth,omitempty"      envconfig:"CB_WRITABLE_BOOTH" default:"false"`
	LeaveTmpOnExit    bool   `toml:"leave-tmp-on-exit,omitempty"   envconfig:"CB_LEAVE_TMP_ON_EXIT" default:"false"`
	KeepTmpOnStart    bool   `toml:"keep-tmp-on-start,omitempty"   envconfig:"CB_KEEP_TMP_ON_START" default:"false"`
	LogTime           bool   `toml:"log-time,omitempty"            envconfig:"CB_LOG_TIME" default:"false"`
	PersistHome       bool   `toml:"persist-home,omitempty"        envconfig:"CB_PERSIST_HOME" default:"false"`
	IdleTime          int    `toml:"idle-time,omitempty"           envconfig:"CB_IDLE_TIME" default:"0"`
	IdleShutdownTime  int    `toml:"idle-shutdown-time,omitempty"  envconfig:"CB_IDLE_SHUTDOWN_TIME" default:"0"`
	IdleExitCode      int    `toml:"idle-exit-code,omitempty"      envconfig:"CB_IDLE_EXIT_CODE" default:"0"`

	// Public exposes the booth on all interfaces (0.0.0.0) with password auth and HTTPS.
	// Password is resolved at startup from .booth/.booth.password or interactive stdin.
	// These are never read from TOML or environment variables.
	Public              bool     `toml:"-" ignored:"true"`
	Password            string   `toml:"-" ignored:"true"`
	TLSCert             string   `toml:"-" ignored:"true"`
	TLSKey              string   `toml:"-" ignored:"true"`
	EgressAllowlistFile string   `toml:"egress-allowlist-file,omitempty" envconfig:"CB_EGRESS_ALLOWLIST_FILE"`
	EgressPolicyFile    string   `toml:"egress-policy-file,omitempty"    envconfig:"CB_EGRESS_POLICY_FILE"`
	EgressAllowlist     []string `toml:"egress-allowlist,omitempty" envconfig:"CB_EGRESS_ALLOWLIST"`

	// --------------------
	// Image configuration
	// --------------------
	Dockerfile     string `toml:"dockerfile,omitempty"      envconfig:"CB_DOCKERFILE"`
	Boothfile      string `toml:"boothfile,omitempty"       envconfig:"CB_BOOTHFILE"`
	Image          string `toml:"image,omitempty"           envconfig:"CB_IMAGE"`
	Variant        string `toml:"variant,omitempty"         envconfig:"CB_VARIANT" default:"default"`
	EmitDockerfile bool   `toml:"emit-dockerfile,omitempty" envconfig:"CB_EMIT_DOCKERFILE" default:"false"`
	Strict         bool   `toml:"strict,omitempty"          envconfig:"CB_STRICT" default:"false"`

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
	Name              string `toml:"name,omitempty"           envconfig:"CB_NAME"`
	Port              string `toml:"port,omitempty"           envconfig:"CB_PORT" default:"NEXT"`
	EnvFile           string `toml:"env-file,omitempty"       envconfig:"CB_ENV_FILE"`
	Startup           string `toml:"startup,omitempty"        envconfig:"CB_STARTUP"`
	ShowRunTime       string `toml:"show-run-time,omitempty"           envconfig:"CB_SHOW_RUN_TIME"`
	ShowCountDown     string `toml:"show-count-down,omitempty"         envconfig:"CB_SHOW_COUNT_DOWN"`
	CountDownExitCode string `toml:"count-down-exit-code,omitempty"    envconfig:"CB_COUNT_DOWN_EXIT_CODE"`

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
	fmt.Fprintf(&str, "    Dryrun:  %v\n", config.Dryrun)
	fmt.Fprintf(&str, "    Verbose: %v\n", config.Verbose)
	fmt.Fprintf(&str, "    Config:  %v\n", config.Config)
	fmt.Fprintf(&str, "    Code:    %v\n", config.Code)
	fmt.Fprintf(&str, "    Version: %q\n", config.Version)

	fmt.Fprintf(&str, "# Flags -------------------------\n")
	fmt.Fprintf(&str, "    KeepAlive:         %t\n", config.KeepAlive)
	fmt.Fprintf(&str, "    SilenceBuild:      %t\n", config.SilenceBuild)
	fmt.Fprintf(&str, "    Daemon:            %t\n", config.Daemon)
	fmt.Fprintf(&str, "    Pull:              %t\n", config.Pull)
	fmt.Fprintf(&str, "    Dind:              %t\n", config.Dind)
	fmt.Fprintf(&str, "    Sudo:              %t\n", config.Sudo)
	fmt.Fprintf(&str, "    Egress:           %t\n", config.Egress)
	fmt.Fprintf(&str, "    EgressMode:       %q\n", config.EgressMode)
	fmt.Fprintf(&str, "    EgressEnforcement:%q\n", config.EgressEnforcement)
	fmt.Fprintf(&str, "    WritableBooth:     %t\n", config.WritableBooth)
	fmt.Fprintf(&str, "    Public:            %t\n", config.Public)
	fmt.Fprintf(&str, "    Password:          %s\n", maskStr(config.Password))
	fmt.Fprintf(&str, "    TLSCert:           %q\n", config.TLSCert)
	fmt.Fprintf(&str, "    TLSKey:            %q\n", config.TLSKey)
	fmt.Fprintf(&str, "    IdleTime:          %d\n", config.IdleTime)
	fmt.Fprintf(&str, "    IdleShutdownTime:  %d\n", config.IdleShutdownTime)
	fmt.Fprintf(&str, "    IdleExitCode:      %d\n", config.IdleExitCode)
	fmt.Fprintf(&str, "    EgressAllowlist:  %q\n", config.EgressAllowlistFile)
	fmt.Fprintf(&str, "    EgressPolicy:     %q\n", config.EgressPolicyFile)
	fmt.Fprintf(&str, "    EgressAllowlist+: %v\n", config.EgressAllowlist)

	fmt.Fprintf(&str, "# Image Configuration -----------\n")
	fmt.Fprintf(&str, "    Dockerfile:     %q\n", config.Dockerfile)
	fmt.Fprintf(&str, "    Boothfile:      %q\n", config.Boothfile)
	fmt.Fprintf(&str, "    Image:          %q\n", config.Image)
	fmt.Fprintf(&str, "    Variant:        %q\n", config.Variant)
	fmt.Fprintf(&str, "    EmitDockerfile: %t\n", config.EmitDockerfile)
	fmt.Fprintf(&str, "    Strict:         %t\n", config.Strict)

	fmt.Fprintf(&str, "# Runtime values ----------------\n")
	fmt.Fprintf(&str, "    ProjectName: %q\n", config.ProjectName)
	fmt.Fprintf(&str, "    HostUID:     %q\n", config.HostUID)
	fmt.Fprintf(&str, "    HostGID:     %q\n", config.HostGID)
	fmt.Fprintf(&str, "    Timezone:    %q\n", config.Timezone)

	fmt.Fprintf(&str, "# Container Configuration -------\n")
	fmt.Fprintf(&str, "    Name:    %q\n", config.Name)
	fmt.Fprintf(&str, "    Port:    %q\n", config.Port)
	fmt.Fprintf(&str, "    EnvFile: %q\n", config.EnvFile)
	fmt.Fprintf(&str, "    Startup: %q\n", config.Startup)

	fmt.Fprintf(&str, "# TOML-friendly array fields ----\n")
	formatList(&str, "CommonArgs", config.CommonArgs.List, "    ")
	formatList(&str, "BuildArgs", config.BuildArgs.List, "    ")
	formatList(&str, "RunArgs", config.RunArgs.List, "    ")
	formatList(&str, "Cmds", config.Cmds.List, "    ")

	str.WriteString("==================================================================\n")

	return str.String()
}

func maskStr(s string) string {
	if s == "" {
		return "(not set)"
	}
	return "(set)"
}
