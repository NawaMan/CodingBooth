// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"errors"
	"strings"
	"testing"
)

func TestParseSecurityOptions(t *testing.T) {
	tests := []struct {
		name        string
		options     []string
		rootless    bool
		usernsRemap bool
	}{
		{
			name:    "rootful Linux with seccomp and cgroupns is supported",
			options: []string{"name=apparmor", "name=seccomp,profile=builtin", "name=cgroupns"},
		},
		{
			name:     "name=rootless is rootless",
			options:  []string{"name=seccomp,profile=builtin", "name=rootless"},
			rootless: true,
		},
		{
			name:     "bare rootless token is rootless",
			options:  []string{"rootless"},
			rootless: true,
		},
		{
			name:        "name=userns is userns-remap",
			options:     []string{"name=apparmor", "name=userns"},
			usernsRemap: true,
		},
		{
			name:        "cgroupns is not userns-remap",
			options:     []string{"name=cgroupns"},
			usernsRemap: false,
		},
		{
			name:        "rootless and userns together",
			options:     []string{"name=rootless", "name=userns"},
			rootless:    true,
			usernsRemap: true,
		},
		{
			name:    "empty options are supported",
			options: nil,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			mode := ParseSecurityOptions(test.options)
			if mode.Rootless != test.rootless {
				t.Errorf("Rootless = %v, want %v", mode.Rootless, test.rootless)
			}
			if mode.UsernsRemap != test.usernsRemap {
				t.Errorf("UsernsRemap = %v, want %v", mode.UsernsRemap, test.usernsRemap)
			}
		})
	}
}

func TestCheckHostDocker_refusesLinuxRootless(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		RequireDaemon: true,
		ReadInfo: func() ([]string, string, error) {
			return []string{"name=rootless"}, "", nil
		},
	})
	hostErr, ok := err.(*HostCheckError)
	if !ok {
		t.Fatalf("got %v (%T), want HostCheckError", err, err)
	}
	if hostErr.Kind != "rootless" {
		t.Errorf("Kind = %q, want rootless", hostErr.Kind)
	}
	if !strings.Contains(hostErr.Message, "--rootless") {
		t.Errorf("message should mention --rootless, got:\n%s", hostErr.Message)
	}
	if !strings.Contains(hostErr.Message, "coder") {
		t.Errorf("message should mention coder, got:\n%s", hostErr.Message)
	}
}

func TestCheckHostDocker_refusesLinuxUsernsRemap(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos: "linux",
		ReadInfo: func() ([]string, string, error) {
			return []string{"name=userns"}, "", nil
		},
	})
	hostErr, ok := err.(*HostCheckError)
	if !ok {
		t.Fatalf("got %v (%T), want HostCheckError", err, err)
	}
	if hostErr.Kind != "userns" {
		t.Errorf("Kind = %q, want userns", hostErr.Kind)
	}
	if !strings.Contains(hostErr.Message, "userns-remap") {
		t.Errorf("message should mention userns-remap, got:\n%s", hostErr.Message)
	}
}

func TestCheckHostDocker_darwinRootlessIsIgnored(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "darwin",
		RequireDaemon: true,
		ReadInfo: func() ([]string, string, error) {
			return []string{"name=rootless"}, "", nil
		},
	})
	if err != nil {
		t.Fatalf("darwin should not refuse rootless SecurityOptions: %v", err)
	}
}

func TestCheckHostDocker_allowRootlessWarnsAndContinues(t *testing.T) {
	var warned string
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		AllowRootless: true,
		ReadInfo: func() ([]string, string, error) {
			return []string{"name=rootless"}, "", nil
		},
		Warn: func(message string) { warned = message },
	})
	if err != nil {
		t.Fatalf("AllowRootless should not refuse: %v", err)
	}
	if !strings.Contains(warned, "--rootless") {
		t.Errorf("warning should mention --rootless, got %q", warned)
	}
}

func TestCheckHostDocker_dryrunSkipsMissingDocker(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		RequireDaemon: false,
		ReadInfo: func() ([]string, string, error) {
			return nil, "", errors.New(`exec: "docker": executable file not found in $PATH`)
		},
	})
	if err != nil {
		t.Fatalf("dryrun should skip a missing daemon: %v", err)
	}
}

func TestCheckHostDocker_missingDockerWhenRequired(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		RequireDaemon: true,
		ReadInfo: func() ([]string, string, error) {
			return nil, "", errors.New(`exec: "docker": executable file not found in $PATH`)
		},
	})
	hostErr, ok := err.(*HostCheckError)
	if !ok {
		t.Fatalf("got %v (%T), want HostCheckError", err, err)
	}
	if hostErr.Kind != "missing" {
		t.Errorf("Kind = %q, want missing", hostErr.Kind)
	}
}

func TestCheckHostDocker_permissionDenied(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		RequireDaemon: true,
		ReadInfo: func() ([]string, string, error) {
			return nil, "permission denied while trying to connect to the Docker daemon socket", errors.New("exit status 1")
		},
	})
	hostErr, ok := err.(*HostCheckError)
	if !ok {
		t.Fatalf("got %v (%T), want HostCheckError", err, err)
	}
	if hostErr.Kind != "permission" {
		t.Errorf("Kind = %q, want permission", hostErr.Kind)
	}
	if !strings.Contains(hostErr.Message, "usermod") {
		t.Errorf("message should mention usermod, got:\n%s", hostErr.Message)
	}
}

func TestCheckHostDocker_daemonNotRunning(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		RequireDaemon: true,
		ReadInfo: func() ([]string, string, error) {
			return nil, "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?", errors.New("exit status 1")
		},
	})
	hostErr, ok := err.(*HostCheckError)
	if !ok {
		t.Fatalf("got %v (%T), want HostCheckError", err, err)
	}
	if hostErr.Kind != "daemon" {
		t.Errorf("Kind = %q, want daemon", hostErr.Kind)
	}
}

func TestCheckHostDocker_rootfulLinuxIsFine(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		RequireDaemon: true,
		ReadInfo: func() ([]string, string, error) {
			return []string{"name=apparmor", "name=seccomp,profile=builtin", "name=cgroupns"}, "", nil
		},
	})
	if err != nil {
		t.Fatalf("rootful linux should pass: %v", err)
	}
}

func TestCheckHostDocker_podmanSkipsDockerChecks(t *testing.T) {
	// A Podman booth must not be judged by the Docker daemon: no Docker at all,
	// or a rootless / userns-remap Docker, is irrelevant when Podman is the engine.
	for name, readInfo := range map[string]func() ([]string, string, error){
		"docker rootless":    func() ([]string, string, error) { return []string{"name=rootless"}, "", nil },
		"docker userns":      func() ([]string, string, error) { return []string{"name=userns"}, "", nil },
		"docker not on PATH": func() ([]string, string, error) { return nil, "", errors.New("executable file not found in $PATH") },
	} {
		t.Run(name, func(t *testing.T) {
			err := CheckHostDocker(HostCheckOptions{
				Goos:          "linux",
				Engine:        "podman",
				RequireDaemon: true,
				ReadInfo:      readInfo,
			})
			if err != nil {
				t.Fatalf("podman engine must skip the Docker host check, got %v", err)
			}
		})
	}
}

func TestCheckHostDocker_explicitDockerEngineStillChecked(t *testing.T) {
	err := CheckHostDocker(HostCheckOptions{
		Goos:          "linux",
		Engine:        "docker",
		RequireDaemon: true,
		ReadInfo: func() ([]string, string, error) {
			return []string{"name=rootless"}, "", nil
		},
	})
	if _, ok := err.(*HostCheckError); !ok {
		t.Fatalf("got %v (%T), want HostCheckError for docker engine", err, err)
	}
}
