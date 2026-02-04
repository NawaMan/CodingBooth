// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"text/tabwriter"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

type managedContainer struct {
	Name      string
	State     string
	Variant   string
	CodePath  string
	CreatedAt string
	KeepAlive bool
	Port      string
}

type inspectData struct {
	Name    string `json:"Name"`
	Created string `json:"Created"`
	State   struct {
		Status string `json:"Status"`
	} `json:"State"`
	Config struct {
		Labels map[string]string `json:"Labels"`
	} `json:"Config"`
	NetworkSettings struct {
		Ports map[string][]struct {
			HostPort string `json:"HostPort"`
		} `json:"Ports"`
	} `json:"NetworkSettings"`
}

func listBooths(_ string) {
	flagSet := flag.NewFlagSet("list", flag.ContinueOnError)
	runningOnly := flagSet.Bool("running", false, "Show only running booths")
	stoppedOnly := flagSet.Bool("stopped", false, "Show only stopped booths")
	quiet := flagSet.Bool("quiet", false, "Show only container names")
	flagSet.BoolVar(quiet, "q", false, "Show only container names")
	flagSet.SetOutput(os.Stderr)

	if err := flagSet.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
		return
	}
	if *runningOnly && *stoppedOnly {
		failLifecycle("Error: --running and --stopped cannot be used together.")
	}

	containers, err := managedContainers(false)
	if err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to list booths: %v", err))
	}

	containers = filterByState(containers, *runningOnly, *stoppedOnly)
	if len(containers) == 0 {
		if *runningOnly {
			fmt.Println("No running booth containers found.")
			return
		}
		if *stoppedOnly {
			fmt.Println("No stopped booth containers found.")
			return
		}
		fmt.Println("No booth containers found.")
		return
	}

	if *quiet {
		for _, container := range containers {
			fmt.Println(container.Name)
		}
		return
	}

	writer := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	_, _ = fmt.Fprintln(writer, "NAME\tSTATUS\tVARIANT\tKEEP_ALIVE\tPORT\tCODE PATH\tCREATED")
	for _, container := range containers {
		status := "Stopped"
		if container.State == "running" {
			status = "Running"
		}
		port := container.Port
		if port == "" {
			port = "-"
		}
		_, _ = fmt.Fprintf(
			writer,
			"%s\t%s\t%s\t%t\t%s\t%s\t%s\n",
			container.Name,
			status,
			nonEmpty(container.Variant, "-"),
			container.KeepAlive,
			port,
			nonEmpty(container.CodePath, "-"),
			nonEmpty(container.CreatedAt, "-"),
		)
	}
	_ = writer.Flush()
}

func startBooth(_ string) {
	flagSet := flag.NewFlagSet("start", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	code := flagSet.String("code", "", "Code path used to find the container")
	daemon := flagSet.Bool("daemon", false, "Start detached")
	flagSet.BoolVar(daemon, "d", false, "Start detached")
	flagSet.SetOutput(os.Stderr)

	if err := flagSet.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
		return
	}

	containers, err := managedContainers(false)
	if err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, *code, flagSet.Args(), stateStopped)
	if err != nil {
		failLifecycle(err.Error())
	}

	args := ilist.NewList(ilist.NewList(target.Name))
	if !*daemon {
		args = ilist.NewList(ilist.NewList("-ai"), ilist.NewList(target.Name))
	}
	if err := docker.Docker(docker.DockerFlags{Silent: false}, "start", args); err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to start %q: %v", target.Name, err))
	}
}

func stopBooth(_ string) {
	flagSet := flag.NewFlagSet("stop", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	force := flagSet.Bool("force", false, "Force stop with SIGKILL")
	flagSet.BoolVar(force, "f", false, "Force stop with SIGKILL")
	timeout := flagSet.Int("time", 10, "Seconds to wait before force kill")
	flagSet.SetOutput(os.Stderr)

	if err := flagSet.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
		return
	}
	if *timeout < 0 {
		failLifecycle("Error: --time must be a non-negative integer.")
	}

	containers, err := managedContainers(false)
	if err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, "", flagSet.Args(), stateRunning)
	if err != nil {
		failLifecycle(err.Error())
	}

	if *force {
		if err := docker.Docker(docker.DockerFlags{Silent: false}, "kill", ilist.NewList(ilist.NewList(target.Name))); err != nil {
			failLifecycle(fmt.Sprintf("Error: failed to force-stop %q: %v", target.Name, err))
		}
	} else {
		if err := docker.Docker(docker.DockerFlags{Silent: false}, "stop", ilist.NewList(
			ilist.NewList("--time", strconv.Itoa(*timeout)),
			ilist.NewList(target.Name),
		)); err != nil {
			failLifecycle(fmt.Sprintf("Error: failed to stop %q: %v", target.Name, err))
		}
	}

	if target.KeepAlive {
		return
	}

	exists, err := containerExists(target.Name)
	if err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to verify container state: %v", err))
	}
	if !exists {
		return
	}

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "rm", ilist.NewList(ilist.NewList(target.Name))); err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to remove non-keep-alive container %q: %v", target.Name, err))
	}
}

func restartBooth(_ string) {
	flagSet := flag.NewFlagSet("restart", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	timeout := flagSet.Int("time", 10, "Seconds to wait before force kill")
	flagSet.SetOutput(os.Stderr)

	if err := flagSet.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
		return
	}
	if *timeout < 0 {
		failLifecycle("Error: --time must be a non-negative integer.")
	}

	containers, err := managedContainers(false)
	if err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, "", flagSet.Args(), stateRunning)
	if err != nil {
		failLifecycle(err.Error())
	}

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "restart", ilist.NewList(
		ilist.NewList("--time", strconv.Itoa(*timeout)),
		ilist.NewList(target.Name),
	)); err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to restart %q: %v", target.Name, err))
	}
}

func removeBooth(_ string) {
	flagSet := flag.NewFlagSet("remove", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	force := flagSet.Bool("force", false, "Force remove even if running")
	flagSet.BoolVar(force, "f", false, "Force remove even if running")
	flagSet.SetOutput(os.Stderr)

	if err := flagSet.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
		return
	}

	containers, err := managedContainers(false)
	if err != nil {
		failLifecycle(fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	names, err := resolveRemoveTargets(containers, *name, flagSet.Args())
	if err != nil {
		failLifecycle(err.Error())
	}

	for _, targetName := range names {
		container, found := findByName(containers, targetName)
		if !found {
			failLifecycle(fmt.Sprintf("Error: booth %q not found. Use 'codingbooth list' to see available containers.", targetName))
		}
		if container.State == "running" && !*force {
			failLifecycle(fmt.Sprintf("Error: booth %q is running. Stop it first or use --force.", targetName))
		}

		args := ilist.NewList(ilist.NewList(targetName))
		if *force {
			args = ilist.NewList(ilist.NewList("--force"), ilist.NewList(targetName))
		}
		if err := docker.Docker(docker.DockerFlags{Silent: false}, "rm", args); err != nil {
			failLifecycle(fmt.Sprintf("Error: failed to remove %q: %v", targetName, err))
		}
	}
}

func managedContainers(verbose bool) ([]managedContainer, error) {
	flags := docker.DockerFlags{Verbose: verbose, Silent: true}

	out, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("-a"),
		ilist.NewList("--filter", "label=cb.managed=true"),
		ilist.NewList("--format", "{{.Names}}"),
	))
	if err != nil {
		return nil, err
	}

	names := nonEmptyLines(out)
	containers := make([]managedContainer, 0, len(names))
	for _, name := range names {
		container, inspectErr := inspectManagedContainer(name, flags)
		if inspectErr != nil {
			return nil, inspectErr
		}
		containers = append(containers, container)
	}

	sort.Slice(containers, func(i, j int) bool {
		return containers[i].Name < containers[j].Name
	})
	return containers, nil
}

func inspectManagedContainer(name string, flags docker.DockerFlags) (managedContainer, error) {
	out, err := docker.DockerOutput(flags, "inspect", ilist.NewList(
		ilist.NewList("--format", "{{json .}}"),
		ilist.NewList(name),
	))
	if err != nil {
		return managedContainer{}, fmt.Errorf("failed to inspect container %q: %w", name, err)
	}

	var data inspectData
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &data); err != nil {
		return managedContainer{}, fmt.Errorf("failed to parse docker inspect output for %q: %w", name, err)
	}

	labels := data.Config.Labels
	if labels == nil {
		labels = map[string]string{}
	}

	port := ""
	if bindings, found := data.NetworkSettings.Ports["10000/tcp"]; found && len(bindings) > 0 {
		port = bindings[0].HostPort
	}

	containerName := strings.TrimPrefix(data.Name, "/")
	if containerName == "" {
		containerName = name
	}

	createdAt := labels["cb.created-at"]
	if createdAt == "" {
		createdAt = data.Created
	}

	return managedContainer{
		Name:      containerName,
		State:     data.State.Status,
		Variant:   labels["cb.variant"],
		CodePath:  labels["cb.code-path"],
		CreatedAt: createdAt,
		KeepAlive: strings.EqualFold(labels["cb.keep-alive"], "true"),
		Port:      port,
	}, nil
}

func filterByState(containers []managedContainer, runningOnly bool, stoppedOnly bool) []managedContainer {
	if !runningOnly && !stoppedOnly {
		return containers
	}

	filtered := make([]managedContainer, 0, len(containers))
	for _, container := range containers {
		isRunning := container.State == "running"
		if runningOnly && isRunning {
			filtered = append(filtered, container)
			continue
		}
		if stoppedOnly && !isRunning {
			filtered = append(filtered, container)
		}
	}
	return filtered
}

const (
	stateAny     = ""
	stateRunning = "running"
	stateStopped = "stopped"
)

func resolveSingleContainer(containers []managedContainer, name string, codePath string, positional []string, requiredState string) (managedContainer, error) {
	if name != "" && len(positional) > 0 {
		return managedContainer{}, errors.New("Error: use either --name or positional name, not both")
	}
	if len(positional) > 1 {
		return managedContainer{}, errors.New("Error: too many positional arguments")
	}

	if codePath != "" {
		normalized := normalizeCodePath(codePath)
		matches := make([]managedContainer, 0, 4)
		for _, container := range containers {
			if container.CodePath == normalized && stateMatches(container, requiredState) {
				matches = append(matches, container)
			}
		}
		if len(matches) == 0 {
			if requiredState == stateStopped {
				return managedContainer{}, fmt.Errorf("Error: no stopped booth found for code path %q. Use 'codingbooth list --stopped'.", normalized)
			}
			return managedContainer{}, fmt.Errorf("Error: no booth found for code path %q.", normalized)
		}
		if len(matches) > 1 {
			names := make([]string, 0, len(matches))
			for _, match := range matches {
				names = append(names, match.Name)
			}
			sort.Strings(names)
			return managedContainer{}, fmt.Errorf("Error: multiple booths match code path %q (%s). Use --name.", normalized, strings.Join(names, ", "))
		}
		return matches[0], nil
	}

	targetName := name
	if targetName == "" && len(positional) == 1 {
		targetName = positional[0]
	}
	if targetName == "" {
		targetName = defaultBoothName()
	}

	container, found := findByName(containers, targetName)
	if !found {
		suggestion := "codingbooth list"
		if requiredState == stateStopped {
			suggestion = "codingbooth list --stopped"
		}
		return managedContainer{}, fmt.Errorf("Error: booth %q not found. Use '%s' to see available containers.", targetName, suggestion)
	}

	if !stateMatches(container, requiredState) {
		switch requiredState {
		case stateRunning:
			return managedContainer{}, fmt.Errorf("Error: booth %q is not running.", targetName)
		case stateStopped:
			return managedContainer{}, fmt.Errorf("Error: booth %q is already running.", targetName)
		}
	}

	return container, nil
}

func resolveRemoveTargets(containers []managedContainer, name string, positional []string) ([]string, error) {
	if name != "" && len(positional) > 0 {
		return nil, errors.New("Error: use either --name or positional names, not both")
	}
	if name != "" {
		return []string{name}, nil
	}
	if len(positional) > 0 {
		return positional, nil
	}

	defaultName := defaultBoothName()
	if _, found := findByName(containers, defaultName); !found {
		return nil, fmt.Errorf("Error: no default booth found for project %q. Use --name or 'codingbooth list'.", defaultName)
	}
	return []string{defaultName}, nil
}

func findByName(containers []managedContainer, name string) (managedContainer, bool) {
	for _, container := range containers {
		if container.Name == name {
			return container, true
		}
	}
	return managedContainer{}, false
}

func stateMatches(container managedContainer, requiredState string) bool {
	switch requiredState {
	case stateAny:
		return true
	case stateRunning:
		return container.State == "running"
	case stateStopped:
		return container.State != "running"
	default:
		return false
	}
}

func containerExists(name string) (bool, error) {
	out, err := docker.DockerOutput(docker.DockerFlags{Silent: true}, "ps", ilist.NewList(
		ilist.NewList("-a"),
		ilist.NewList("--filter", "name=^"+name+"$"),
		ilist.NewList("--format", "{{.Names}}"),
	))
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(out) != "", nil
}

func defaultBoothName() string {
	cwd, err := os.Getwd()
	if err != nil {
		return "booth"
	}
	base := filepath.Base(cwd)
	if base == "" {
		return "booth"
	}
	return sanitizeProjectName(base)
}

func sanitizeProjectName(value string) string {
	var builder strings.Builder
	for _, ch := range value {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
			builder.WriteRune(ch)
		} else {
			builder.WriteRune('-')
		}
	}
	sanitized := builder.String()
	if sanitized == "" {
		return "booth"
	}
	return sanitized
}

func normalizeCodePath(path string) string {
	if path == "" {
		return path
	}
	absPath, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return absPath
}

func nonEmptyLines(value string) []string {
	rawLines := strings.Split(value, "\n")
	lines := make([]string, 0, len(rawLines))
	for _, line := range rawLines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			lines = append(lines, trimmed)
		}
	}
	return lines
}

func nonEmpty(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func failLifecycle(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(1)
}
