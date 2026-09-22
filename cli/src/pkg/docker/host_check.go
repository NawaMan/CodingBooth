// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// NamespaceMode is what Docker's SecurityOptions say about user namespaces.
type NamespaceMode struct {
	Rootless    bool
	UsernsRemap bool
}

// Unsupported reports Linux modes CodingBooth cannot remap a `coder` user under.
func (mode NamespaceMode) Unsupported() bool {
	return mode.Rootless || mode.UsernsRemap
}

func (mode NamespaceMode) label() string {
	switch {
	case mode.Rootless && mode.UsernsRemap:
		return "rootless Docker and userns-remap"
	case mode.Rootless:
		return "rootless Docker"
	case mode.UsernsRemap:
		return "Docker userns-remap"
	default:
		return ""
	}
}

// ParseSecurityOptions classifies docker info SecurityOptions.
// Entries look like "name=rootless" or "name=seccomp,profile=builtin".
func ParseSecurityOptions(options []string) NamespaceMode {
	var mode NamespaceMode
	for _, option := range options {
		for _, part := range strings.Split(option, ",") {
			name := strings.TrimSpace(part)
			if strings.HasPrefix(name, "name=") {
				name = strings.TrimPrefix(name, "name=")
			}
			switch name {
			case "rootless":
				mode.Rootless = true
			case "userns":
				mode.UsernsRemap = true
			}
		}
	}
	return mode
}

// HostCheckError is a host Docker problem explained in user terms.
type HostCheckError struct {
	Kind    string
	Message string
}

func (err *HostCheckError) Error() string {
	return err.Message
}

// HostCheckOptions controls CheckHostDocker.
type HostCheckOptions struct {
	Goos string
	// Engine is the container engine in use ("docker" or "podman"; empty means
	// docker). The rootless / userns-remap refusal is about how Docker maps the
	// host user, so it does not apply to any other engine — Podman's rootless
	// mode is handled by --userns=keep-id at run time.
	Engine        string
	AllowRootless bool
	RequireDaemon bool
	ReadInfo      func() (options []string, stderr string, err error)
	Warn          func(string)
}

func defaultWarn(message string) {
	fmt.Fprintln(os.Stderr, message)
}

// CheckHostDocker refuses Linux rootless / userns-remap unless AllowRootless
// is set, and (when RequireDaemon) explains a missing or unreachable daemon.
func CheckHostDocker(opts HostCheckOptions) error {
	if opts.Engine != "" && opts.Engine != "docker" {
		return nil
	}
	goos := opts.Goos
	if goos == "" {
		goos = runtime.GOOS
	}
	readInfo := opts.ReadInfo
	if readInfo == nil {
		readInfo = ReadDockerSecurityOptions
	}
	warn := opts.Warn
	if warn == nil {
		warn = defaultWarn
	}

	options, stderr, readErr := readInfo()
	if readErr != nil {
		if !opts.RequireDaemon {
			return nil
		}
		return classifyDockerInfoError(readErr, stderr)
	}

	mode := ParseSecurityOptions(options)
	if goos != "linux" || !mode.Unsupported() {
		return nil
	}

	if opts.AllowRootless {
		warn(namespaceOverrideWarning(mode))
		return nil
	}
	return &HostCheckError{
		Kind:    namespaceKind(mode),
		Message: namespaceRefusal(mode),
	}
}

func namespaceKind(mode NamespaceMode) string {
	if mode.Rootless {
		return "rootless"
	}
	return "userns"
}

func namespaceRefusal(mode NamespaceMode) string {
	label := mode.label()
	return fmt.Sprintf(`CodingBooth cannot run on Linux %s.

Rootless Docker (and userns-remap) map your host user to root inside the
container, so there is no separate identity for the booth's coder user.
Project files would look like they belong to root, and CodingBooth cannot
remap ownership the way it does on rootful Docker.

macOS and Windows with Docker Desktop, and Linux with rootful Docker, work.

Refusing to start. This is unsupported. To try anyway, re-run with --rootless.`, label)
}

func namespaceOverrideWarning(mode NamespaceMode) string {
	return fmt.Sprintf(`Warning: this Linux Docker looks like %s, which CodingBooth does not support.
--rootless skips the check. File ownership inside the booth may be wrong.`, mode.label())
}

func classifyDockerInfoError(err error, stderr string) error {
	combined := strings.ToLower(err.Error() + "\n" + stderr)
	switch {
	case strings.Contains(combined, "executable file not found") ||
		strings.Contains(combined, "not found in $path"):
		return &HostCheckError{
			Kind: "missing",
			Message: `CodingBooth needs Docker, but "docker" was not found on PATH.

Install Docker Engine (Linux, rootful) or Docker Desktop (macOS/Windows),
then confirm with: docker info`,
		}
	case strings.Contains(combined, "permission denied"):
		return &HostCheckError{
			Kind: "permission",
			Message: `CodingBooth cannot talk to the Docker daemon (permission denied).

On Linux, add your user to the docker group, then log out and back in:
  sudo usermod -aG docker $USER
Confirm with: docker info`,
		}
	case strings.Contains(combined, "cannot connect") ||
		strings.Contains(combined, "is the docker daemon running"):
		return &HostCheckError{
			Kind: "daemon",
			Message: `CodingBooth cannot reach the Docker daemon.

Start Docker (Docker Desktop on macOS/Windows, or the docker service on Linux)
and confirm with: docker info`,
		}
	default:
		return &HostCheckError{
			Kind:    "docker",
			Message: fmt.Sprintf("CodingBooth cannot talk to Docker:\n  %s", strings.TrimSpace(firstLine(stderr, err.Error()))),
		}
	}
}

func firstLine(stderr, fallback string) string {
	text := strings.TrimSpace(stderr)
	if text == "" {
		return fallback
	}
	if index := strings.IndexByte(text, '\n'); index >= 0 {
		return text[:index]
	}
	return text
}

// ReadDockerSecurityOptions runs `docker info` and returns SecurityOptions.
func ReadDockerSecurityOptions() (options []string, stderr string, err error) {
	command := exec.Command("docker", "info", "--format", "{{json .SecurityOptions}}")
	var stderrBuf bytes.Buffer
	command.Stderr = &stderrBuf
	output, runErr := command.Output()
	stderr = stderrBuf.String()
	if runErr != nil {
		return nil, stderr, runErr
	}
	trimmed := bytes.TrimSpace(output)
	if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
		return nil, stderr, nil
	}
	if unmarshalErr := json.Unmarshal(trimmed, &options); unmarshalErr != nil {
		return nil, stderr, fmt.Errorf("parse docker info SecurityOptions: %w", unmarshalErr)
	}
	return options, stderr, nil
}
