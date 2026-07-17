// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
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
	Daemon    bool
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
	// HostConfig.PortBindings retains the configured host ports even when the
	// container is stopped (NetworkSettings.Ports is often empty then).
	HostConfig struct {
		PortBindings map[string][]struct {
			HostPort string `json:"HostPort"`
		} `json:"PortBindings"`
	} `json:"HostConfig"`
}

type commandError struct {
	exitCode int
	message  string
}

func (err *commandError) Error() string {
	return err.message
}

func (err *commandError) ExitCode() int {
	return err.exitCode
}

func commandExit(exitCode int, message string) error {
	return &commandError{
		exitCode: exitCode,
		message:  message,
	}
}

func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	var commandErr *commandError
	if errors.As(err, &commandErr) {
		return commandErr.exitCode
	}
	return 1
}

func List(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("list", flag.ContinueOnError)
	runningOnly := flagSet.Bool("running", false, "Show only running booths")
	stoppedOnly := flagSet.Bool("stopped", false, "Show only stopped booths")
	nameOnly := flagSet.Bool("name-only", false, "Show only container names")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}
	if *runningOnly && *stoppedOnly {
		return commandExit(1, "Error: --running and --stopped cannot be used together.")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to list booths: %v", err))
	}

	containers = filterByState(containers, *runningOnly, *stoppedOnly)
	if len(containers) == 0 {
		if *runningOnly {
			_, _ = fmt.Fprintln(stdout, "No running booth containers found.")
			return nil
		}
		if *stoppedOnly {
			_, _ = fmt.Fprintln(stdout, "No stopped booth containers found.")
			return nil
		}
		_, _ = fmt.Fprintln(stdout, "No booth containers found.")
		return nil
	}

	if *nameOnly {
		for _, container := range containers {
			_, _ = fmt.Fprintln(stdout, container.Name)
		}
		return nil
	}

	writer := tabwriter.NewWriter(stdout, 0, 4, 2, ' ', 0)
	_, _ = fmt.Fprintln(writer, "NAME\tSTATUS\tVARIANT\tPORT\tCODE PATH\tDAEMON\tKEEP_ALIVE\tCREATED")
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
			"%s\t%s\t%s\t%s\t%s\t%t\t%t\t%s\n",
			container.Name,
			status,
			nonEmpty(container.Variant, "-"),
			port,
			nonEmpty(container.CodePath, "-"),
			container.Daemon,
			container.KeepAlive,
			nonEmpty(container.CreatedAt, "-"),
		)
	}
	_ = writer.Flush()
	return nil
}

func Start(args []string, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("start", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	code := flagSet.String("code", "", "Code path used to find the container")
	daemon := flagSet.Bool("daemon", false, "Start detached")
	flagSet.BoolVar(daemon, "d", false, "Start detached")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, *code, flagSet.Args(), stateStopped)
	if err != nil {
		return commandExit(1, err.Error())
	}

	dockerArgs := ilist.NewList(ilist.NewList(target.Name))
	if !*daemon {
		dockerArgs = ilist.NewList(ilist.NewList("-ai"), ilist.NewList(target.Name))
	}
	if err := docker.Docker(docker.DockerFlags{Silent: false}, "start", dockerArgs); err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to start %q: %v", target.Name, err))
	}
	return nil
}

func Stop(args []string, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("stop", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	force := flagSet.Bool("force", false, "Force stop with SIGKILL")
	flagSet.BoolVar(force, "f", false, "Force stop with SIGKILL")
	timeout := flagSet.Int("timeout", 10, "Seconds to wait before force kill")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}
	if *timeout < 0 {
		return commandExit(1, "Error: --timeout must be a non-negative integer.")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, "", flagSet.Args(), stateRunning)
	if err != nil {
		return commandExit(1, err.Error())
	}

	if *force {
		if err := docker.Docker(docker.DockerFlags{Silent: false}, "kill", ilist.NewList(ilist.NewList(target.Name))); err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to force-stop %q: %v", target.Name, err))
		}
	} else {
		if err := docker.Docker(docker.DockerFlags{Silent: false}, "stop", ilist.NewList(
			ilist.NewList("--timeout", strconv.Itoa(*timeout)),
			ilist.NewList(target.Name),
		)); err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to stop %q: %v", target.Name, err))
		}
	}

	// Stop any sidecar containers (DinD, egress) belonging to this booth
	stopSidecars(target.Name, docker.DockerFlags{Silent: true})

	if target.KeepAlive {
		return nil
	}

	exists, err := containerExists(target.Name)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to verify container state: %v", err))
	}
	if !exists {
		return nil
	}

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "rm", ilist.NewList(ilist.NewList(target.Name))); err != nil {
		// Container may have been auto-removed between the existence check and
		// the rm call. If it is gone now, treat the stop as successful.
		gone, existsErr := containerExists(target.Name)
		if existsErr == nil && !gone {
			return nil
		}
		return commandExit(1, fmt.Sprintf("Error: failed to remove non-keep-alive container %q: %v", target.Name, err))
	}
	return nil
}

func Restart(args []string, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("restart", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	timeout := flagSet.Int("timeout", 10, "Seconds to wait before force kill")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}
	if *timeout < 0 {
		return commandExit(1, "Error: --timeout must be a non-negative integer.")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, "", flagSet.Args(), stateRunning)
	if err != nil {
		return commandExit(1, err.Error())
	}

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "restart", ilist.NewList(
		ilist.NewList("--timeout", strconv.Itoa(*timeout)),
		ilist.NewList(target.Name),
	)); err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to restart %q: %v", target.Name, err))
	}
	return nil
}

func Remove(args []string, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("remove", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	force := flagSet.Bool("force", false, "Force remove even if running")
	flagSet.BoolVar(force, "f", false, "Force remove even if running")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	names, err := resolveRemoveTargets(containers, *name, flagSet.Args())
	if err != nil {
		return commandExit(1, err.Error())
	}

	for _, targetName := range names {
		container, found := findByName(containers, targetName)
		if !found {
			return commandExit(1, fmt.Sprintf("Error: booth %q not found. Use 'booth list' to see available containers.", targetName))
		}
		if container.State == "running" && !*force {
			return commandExit(1, fmt.Sprintf("Error: booth %q is running. Stop it first or use --force.", targetName))
		}

		// Stop any sidecar containers (DinD, egress) belonging to this booth
		stopSidecars(targetName, docker.DockerFlags{Silent: true})

		dockerArgs := ilist.NewList(ilist.NewList(targetName))
		if *force {
			dockerArgs = ilist.NewList(ilist.NewList("--force"), ilist.NewList(targetName))
		}
		if err := docker.Docker(docker.DockerFlags{Silent: false}, "rm", dockerArgs); err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to remove %q: %v", targetName, err))
		}

		// Remove associated home volume (if any). Fails silently if volume does not exist.
		homeVolName := "cb-home-" + targetName
		_ = docker.Docker(docker.DockerFlags{Silent: true}, "volume", ilist.NewList(ilist.NewList("rm", homeVolName)))
	}
	return nil
}

func Prune(args []string, stdin io.Reader, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("prune", flag.ContinueOnError)
	yes := flagSet.Bool("yes", false, "Skip confirmation prompt")
	flagSet.BoolVar(yes, "y", false, "Skip confirmation prompt")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	candidates := filterByState(containers, false, true)
	if len(candidates) == 0 {
		_, _ = fmt.Fprintln(stdout, "No stopped booth containers to prune.")
		return nil
	}

	names := make([]string, 0, len(candidates))
	for _, container := range candidates {
		names = append(names, container.Name)
	}
	sort.Strings(names)

	if !*yes {
		_, _ = fmt.Fprintf(stdout, "About to remove %d stopped booth container(s): %s\n", len(names), strings.Join(names, ", "))
		_, _ = fmt.Fprint(stdout, "Proceed? [y/N]: ")
		confirmed, confirmErr := readConfirmation(stdin)
		if confirmErr != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to read confirmation: %v", confirmErr))
		}
		if !confirmed {
			_, _ = fmt.Fprintln(stdout, "Prune cancelled.")
			return nil
		}
	}

	for _, name := range names {
		// Stop any sidecar containers belonging to this booth before removing
		stopSidecars(name, docker.DockerFlags{Silent: true})

		if err := docker.Docker(docker.DockerFlags{Silent: false}, "rm", ilist.NewList(ilist.NewList(name))); err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to remove %q: %v", name, err))
		}

		// Remove associated home volume (if any). Fails silently if volume does not exist.
		homeVolName := "cb-home-" + name
		_ = docker.Docker(docker.DockerFlags{Silent: true}, "volume", ilist.NewList(ilist.NewList("rm", homeVolName)))
	}

	_, _ = fmt.Fprintf(stdout, "Removed %d stopped booth container(s).\n", len(names))

	// Clean up any orphaned sidecars whose parent container no longer exists
	orphanCount := pruneOrphanSidecars(docker.DockerFlags{Silent: true})
	if orphanCount > 0 {
		_, _ = fmt.Fprintf(stdout, "Removed %d orphaned sidecar(s).\n", orphanCount)
	}

	return nil
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

	port := hostPortFromInspect(data)

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
		Daemon:    strings.EqualFold(labels["cb.daemon"], "true"),
		Port:      port,
	}, nil
}

// hostPortFromInspect returns the host port mapped to the booth UI container
// port. Prefers live NetworkSettings, then HostConfig bindings (works for
// stopped containers). Checks both 10000/tcp (default) and 10443/tcp (public TLS).
func hostPortFromInspect(data inspectData) string {
	for _, containerPort := range []string{"10000/tcp", "10443/tcp"} {
		if bindings, found := data.NetworkSettings.Ports[containerPort]; found && len(bindings) > 0 {
			if p := strings.TrimSpace(bindings[0].HostPort); p != "" {
				return p
			}
		}
	}
	for _, containerPort := range []string{"10000/tcp", "10443/tcp"} {
		if bindings, found := data.HostConfig.PortBindings[containerPort]; found && len(bindings) > 0 {
			if p := strings.TrimSpace(bindings[0].HostPort); p != "" {
				return p
			}
		}
	}
	return ""
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
				return managedContainer{}, fmt.Errorf("Error: no stopped booth found for code path %q. Use 'booth list --stopped'.", normalized)
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
		suggestion := "booth list"
		if requiredState == stateStopped {
			suggestion = "booth list --stopped"
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
		return nil, fmt.Errorf("Error: no default booth found for project %q. Use --name or 'booth list'.", defaultName)
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

func readConfirmation(reader io.Reader) (bool, error) {
	line, err := bufio.NewReader(reader).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return false, err
	}

	answer := strings.ToLower(strings.TrimSpace(line))
	return answer == "y" || answer == "yes", nil
}

// stopSidecars stops all sidecar containers labeled with cb.parent matching the given container name.
// Sidecars are typically started with --rm, so stopping them also removes them.
func stopSidecars(parentName string, flags docker.DockerFlags) {
	out, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("-aq"),
		ilist.NewList("--filter", "label=cb.role=sidecar"),
		ilist.NewList("--filter", "label=cb.parent="+parentName),
	))
	if err != nil || strings.TrimSpace(out) == "" {
		return
	}

	for _, id := range nonEmptyLines(out) {
		_ = docker.Docker(flags, "stop", ilist.NewList(ilist.NewList(id)))
		_ = docker.Docker(flags, "rm", ilist.NewList(ilist.NewList("-f", id)))
	}
}

// pruneOrphanSidecars finds sidecar containers whose parent no longer exists and removes them.
// Returns the number of orphaned sidecars cleaned up.
func pruneOrphanSidecars(flags docker.DockerFlags) int {
	out, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("-aq"),
		ilist.NewList("--filter", "label=cb.role=sidecar"),
	))
	if err != nil || strings.TrimSpace(out) == "" {
		return 0
	}

	count := 0
	for _, id := range nonEmptyLines(out) {
		// Get the parent name from the sidecar's label
		labelOut, err := docker.DockerOutput(flags, "inspect", ilist.NewList(
			ilist.NewList("--format", "{{index .Config.Labels \"cb.parent\"}}"),
			ilist.NewList(id),
		))
		if err != nil {
			continue
		}
		parentName := strings.TrimSpace(labelOut)
		if parentName == "" {
			continue
		}

		// Check if parent container still exists
		exists, err := containerExists(parentName)
		if err != nil || exists {
			continue
		}

		// Parent is gone — stop and remove the orphaned sidecar
		_ = docker.Docker(flags, "stop", ilist.NewList(ilist.NewList(id)))
		_ = docker.Docker(flags, "rm", ilist.NewList(ilist.NewList("-f", id)))
		count++
	}
	return count
}
