// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"text/template"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// EngineApple is Apple's container runtime (https://github.com/apple/container),
// the macOS-native runtime that runs each Linux container in its own VM. Its
// CLI binary is `container` (appleBinary).
//
// Unlike Podman it does not accept Docker's command syntax: `ls` / `inspect`
// only print JSON (no --filter, no Go-template --format), there is no `port`
// or `restart`, and `run` lacks the host-escape flags. Rather than teach every
// call site about it, Docker() and DockerOutput() hand an "apple" call to
// runApple, which rewrites the Docker-style call and answers the queries in
// Go from the JSON. See docs/CONTAINER_SUPPORT.md.
const EngineApple = "apple"

// appleBinary is the CLI EngineApple shells out to.
const appleBinary = "container"

// appleStep is one `container` invocation a Docker-style call becomes.
// When render is set the step is a query: its JSON stdout is turned into what
// the Docker command would have printed.
type appleStep struct {
	args   []string
	render func(stdout []byte) (string, error)
}

// UnsupportedOnAppleError reports a Docker flag that Apple container has no
// equivalent for. It is raised rather than dropping the flag silently.
type UnsupportedOnAppleError struct {
	Flag string
}

func (e *UnsupportedOnAppleError) Error() string {
	return fmt.Sprintf("%s is not supported on engine apple (Apple container) — see docs/CONTAINER_SUPPORT.md", e.Flag)
}

// runApple runs a Docker-style call on Apple container. flat is the full
// argument list after the subcommand, already TTY-adjusted by the caller. With
// capture it returns stdout; otherwise stdout goes to the terminal (or nowhere
// when silent).
func runApple(flags DockerFlags, subcommand string, flat []string, capture bool) (string, error) {
	steps, err := translateForApple(subcommand, flat)
	if err != nil {
		return "", err
	}

	var out strings.Builder
	for _, step := range steps {
		if flags.Dryrun || flags.Verbose {
			printCmd(appleBinary, printGroups(step.args)...)
		}
		if flags.Dryrun {
			continue
		}

		cmd := exec.Command(appleBinary, step.args...)
		cmd.Env = commandEnv()
		cmd.Stdin = os.Stdin

		var stdout bytes.Buffer
		switch {
		case step.render != nil || capture:
			cmd.Stdout = &stdout
		case flags.Silent:
			cmd.Stdout = io.Discard
		case subcommand == "build":
			cmd.Stdout = os.Stderr
		default:
			cmd.Stdout = os.Stdout
		}
		if flags.Silent {
			cmd.Stderr = io.Discard
		} else {
			cmd.Stderr = os.Stderr
		}

		if err := cmd.Run(); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				return out.String(), &DockerExitError{Subcommand: subcommand, ExitCode: exitErr.ExitCode(), Engine: appleBinary}
			}
			return out.String(), fmt.Errorf("%s %s failed: %w", appleBinary, subcommand, err)
		}

		text := stdout.String()
		if step.render != nil {
			if text, err = step.render(stdout.Bytes()); err != nil {
				return out.String(), fmt.Errorf("%s %s: %w", appleBinary, subcommand, err)
			}
			if !capture && !flags.Silent {
				fmt.Fprint(os.Stdout, text)
			}
		}
		out.WriteString(text)
	}
	return out.String(), nil
}

// AppleServiceRunning reports whether Apple container's API server is up
// (`container system status`). When it is not, `container` cannot answer any
// query — and there are no running booths on it either — so a lookup that
// only included it because it is installed can skip it quietly.
func AppleServiceRunning() bool {
	out, err := exec.Command(appleBinary, "system", "status", "--format", "json").Output()
	if err != nil {
		return false
	}
	var status struct {
		Status string `json:"status"`
	}
	return json.Unmarshal(out, &status) == nil && status.Status == "running"
}

// AppleDefaultGateway is the IPv4 gateway of Apple container's built-in
// "default" network: the address a container on it reaches the host at.
const AppleDefaultGateway = "192.168.64.1"

// AppleNetworkGateway returns the IPv4 gateway of an Apple container network
// (`container network inspect`), or AppleDefaultGateway when it cannot be
// read. With dryrun set nothing is run and the default is returned, so what
// --dryrun prints does not depend on the machine.
func AppleNetworkGateway(network string, dryrun bool) string {
	if dryrun {
		return AppleDefaultGateway
	}
	out, err := exec.Command(appleBinary, "network", "inspect", network).Output()
	if err != nil {
		return AppleDefaultGateway
	}
	var networks []struct {
		Status struct {
			IPv4Gateway string `json:"ipv4Gateway"`
		} `json:"status"`
	}
	if json.Unmarshal(out, &networks) != nil || len(networks) == 0 || networks[0].Status.IPv4Gateway == "" {
		return AppleDefaultGateway
	}
	return networks[0].Status.IPv4Gateway
}

// printGroups splits a `container run` line into one flag (and its value) per
// printed line, the way Docker() prints its argument groups; the image and the
// command after it stay on one line. Anything else prints on a single line.
func printGroups(args []string) [][]string {
	if len(args) == 0 || args[0] != "run" {
		return [][]string{args}
	}
	groups := [][]string{{"run"}}
	for i := 1; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "-") {
			return append(groups, args[i:])
		}
		if (dockerRunValueFlags[arg] || arg == "--progress") && i+1 < len(args) {
			groups = append(groups, []string{arg, args[i+1]})
			i++
			continue
		}
		groups = append(groups, []string{arg})
	}
	return groups
}

// commandEnv is the environment every engine process runs with.
func commandEnv() []string {
	env := append(os.Environ(), "MSYS_NO_PATHCONV=1", "FORCE_COLOR=1",
		"BUILDKIT_COLORS=run=cyan:warning=yellow:error=red:cancel=green")
	if os.Getenv("TERM") == "" {
		env = append(env, "TERM=xterm-256color")
	}
	return env
}

func flattenArgs(args ilist.List[ilist.List[string]]) []string {
	var flat []string
	args.Range(func(_ int, group ilist.List[string]) bool {
		flat = append(flat, group.Slice()...)
		return true
	})
	return flat
}

// translateForApple maps one Docker-style call onto Apple container.
func translateForApple(subcommand string, args []string) ([]appleStep, error) {
	passthrough := func(prefix ...string) []appleStep {
		return []appleStep{{args: append(prefix, args...)}}
	}
	switch subcommand {
	case "run":
		translated, err := translateRunArgs(args)
		if err != nil {
			return nil, err
		}
		// The image is already local by now (EnsureDockerImage), so run's
		// fetch/unpack progress is noise — and under -d it lands in the
		// captured container ID.
		prefix := []string{"run"}
		if !containsFlag(translated, "--progress") {
			prefix = append(prefix, "--progress", "none")
		}
		return []appleStep{{args: append(prefix, translated...)}}, nil
	case "ps":
		return psQuery(args)
	case "inspect":
		return inspectQuery(args)
	case "port":
		return portQuery(args)
	case "build":
		return []appleStep{{args: append([]string{"build"}, translateBuildArgs(args)...)}}, nil
	case "pull":
		return passthrough("image", "pull"), nil
	case "image":
		if len(args) > 0 && args[0] == "inspect" {
			return imageInspectQuery(args[1:])
		}
		return passthrough("image"), nil
	case "volume":
		if len(args) > 0 && (args[0] == "ls" || args[0] == "list") {
			return volumeListQuery(args[1:])
		}
		return passthrough("volume"), nil
	case "stop":
		return []appleStep{{args: append([]string{"stop"}, translateStopArgs(args)...)}}, nil
	case "start":
		return []appleStep{{args: append([]string{"start"}, splitShortFlags(args)...)}}, nil
	case "restart":
		// No `container restart`: stop, then start detached — what `docker restart` does.
		stopArgs := translateStopArgs(args)
		steps := []appleStep{{args: append([]string{"stop"}, stopArgs...)}}
		for _, name := range positionalArgs(stopArgs, map[string]bool{"--time": true}) {
			steps = append(steps, appleStep{args: []string{"start", name}})
		}
		return steps, nil
	case "info":
		return nil, &UnsupportedOnAppleError{Flag: "info"}
	default:
		return passthrough(subcommand), nil
	}
}

// ---- run ------------------------------------------------------------------

// dockerRunValueFlags are the `docker run` flags that take a separate value, so
// the scan can step over it and find where the image (and the command) starts.
var dockerRunValueFlags = map[string]bool{
	"-e": true, "--env": true, "--env-file": true, "-v": true, "--volume": true, "--mount": true,
	"-w": true, "--workdir": true, "-p": true, "--publish": true, "-l": true, "--label": true,
	"--name": true, "-u": true, "--user": true, "--network": true, "--net": true,
	"--entrypoint": true, "--cap-add": true, "--cap-drop": true, "--platform": true,
	"--shm-size": true, "--tmpfs": true, "-m": true, "--memory": true, "--cpus": true,
	"--dns": true, "--dns-search": true, "--dns-option": true, "--ulimit": true,
	"--cidfile": true, "--add-host": true, "--device": true, "--device-cgroup-rule": true,
	"--pid": true, "--ipc": true, "--userns": true, "--sysctl": true, "--security-opt": true,
	"--group-add": true, "--gpus": true, "--restart": true, "--hostname": true, "-h": true,
	"--pull": true, "--stop-timeout": true, "--log-driver": true, "--log-opt": true,
	"--expose": true, "--label-file": true,
}

// unsupportedRunFlags have no Apple container equivalent. Most are host-escape
// flags; each container is its own VM, so there is no host namespace to join.
var unsupportedRunFlags = map[string]bool{
	"--device": true, "--device-cgroup-rule": true, "--pid": true, "--ipc": true,
	"--userns": true, "--sysctl": true, "--security-opt": true, "--group-add": true,
	"--gpus": true, "--restart": true, "--hostname": true, "-h": true,
	"--label-file": true, "--expose": true, "--log-driver": true, "--log-opt": true,
}

// translateRunArgs rewrites `docker run` flags for `container run`, up to the
// image; the image and the command after it are copied untouched.
func translateRunArgs(args []string) ([]string, error) {
	out := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "-") || arg == "-" {
			return append(out, args[i:]...), nil
		}
		if arg == "--" {
			return append(out, args[i:]...), nil
		}

		name, value, inline := arg, "", false
		if strings.HasPrefix(arg, "--") {
			name, value, inline = strings.Cut(arg, "=")
		}
		if !inline && dockerRunValueFlags[name] && i+1 < len(args) {
			i++
			value = args[i]
		}

		switch {
		case name == "--add-host":
			// The booth's own host.docker.internal:host-gateway alias. Apple
			// container has no --add-host; the host is the network gateway.
			if strings.HasSuffix(value, ":host-gateway") {
				continue
			}
			return nil, &UnsupportedOnAppleError{Flag: "--add-host"}
		case name == "--pull":
			// `container run` only fetches an image it does not have, which is
			// what never/missing ask for; the CLI checks presence before run.
			if value == "never" || value == "missing" {
				continue
			}
			return nil, &UnsupportedOnAppleError{Flag: "--pull=" + value}
		case name == "--privileged":
			if inline && value == "false" {
				continue
			}
			return nil, &UnsupportedOnAppleError{Flag: "--privileged"}
		case unsupportedRunFlags[name]:
			return nil, &UnsupportedOnAppleError{Flag: name}
		}

		switch {
		case inline:
			out = append(out, name+"="+value)
		case dockerRunValueFlags[name]:
			out = append(out, name, value)
		default:
			out = append(out, name)
		}
	}
	return out, nil
}

// translateBuildArgs maps Docker's valued --pull=<bool> onto `container
// build`'s bare --pull switch.
func translateBuildArgs(args []string) []string {
	out := make([]string, 0, len(args))
	for _, arg := range args {
		switch arg {
		case "--pull=false":
			continue
		case "--pull=true":
			arg = "--pull"
		}
		out = append(out, arg)
	}
	return out
}

// translateStopArgs maps `docker stop --timeout N` / `-t N` to `--time N`.
func translateStopArgs(args []string) []string {
	out := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case (arg == "--timeout" || arg == "-t" || arg == "--time") && i+1 < len(args):
			out = append(out, "--time", args[i+1])
			i++
		case strings.HasPrefix(arg, "--timeout="), strings.HasPrefix(arg, "--time="):
			out = append(out, "--time", arg[strings.Index(arg, "=")+1:])
		default:
			out = append(out, arg)
		}
	}
	return out
}

// containsFlag reports whether run args set flag, as "flag value" or
// "flag=value", before the image.
func containsFlag(args []string, flag string) bool {
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "-") {
			return false
		}
		if arg == flag || strings.HasPrefix(arg, flag+"=") {
			return true
		}
		if dockerRunValueFlags[arg] {
			i++
		}
	}
	return false
}

// splitShortFlags turns a bundled "-ai" into "-a", "-i".
func splitShortFlags(args []string) []string {
	out := make([]string, 0, len(args))
	for _, arg := range args {
		if len(arg) > 2 && arg[0] == '-' && arg[1] != '-' {
			for _, letter := range arg[1:] {
				out = append(out, "-"+string(letter))
			}
			continue
		}
		out = append(out, arg)
	}
	return out
}

// positionalArgs returns the args that are not flags or flag values.
func positionalArgs(args []string, valueFlags map[string]bool) []string {
	var names []string
	for i := 0; i < len(args); i++ {
		if strings.HasPrefix(args[i], "-") {
			if valueFlags[args[i]] {
				i++
			}
			continue
		}
		names = append(names, args[i])
	}
	return names
}

// ---- the JSON Apple container prints --------------------------------------

type applePort struct {
	HostAddress   string `json:"hostAddress"`
	HostPort      int    `json:"hostPort"`
	ContainerPort int    `json:"containerPort"`
	Proto         string `json:"proto"`
	Count         int    `json:"count"`
}

type appleContainer struct {
	ID            string `json:"id"`
	Configuration struct {
		Labels       map[string]string `json:"labels"`
		CreationDate string            `json:"creationDate"`
		Image        struct {
			Reference string `json:"reference"`
		} `json:"image"`
		InitProcess struct {
			Environment []string `json:"environment"`
		} `json:"initProcess"`
		PublishedPorts []applePort `json:"publishedPorts"`
	} `json:"configuration"`
	Status struct {
		State    string `json:"state"`
		Networks []struct {
			IPv4Address string `json:"ipv4Address"`
			IPv4Gateway string `json:"ipv4Gateway"`
		} `json:"networks"`
	} `json:"status"`
}

type appleVolume struct {
	ID            string `json:"id"`
	Configuration struct {
		Name   string            `json:"name"`
		Driver string            `json:"driver"`
		Source string            `json:"source"`
		Labels map[string]string `json:"labels"`
	} `json:"configuration"`
}

type appleImage struct {
	ID            string `json:"id"`
	Configuration struct {
		Name         string `json:"name"`
		CreationDate string `json:"creationDate"`
		Descriptor   struct {
			Digest string `json:"digest"`
		} `json:"descriptor"`
	} `json:"configuration"`
}

// dockerState maps Apple container's state onto Docker's vocabulary, which the
// CLI (and `--filter status=`) speaks: a stopped container is "exited".
func dockerState(state string) string {
	if state == "stopped" {
		return "exited"
	}
	return state
}

// ---- ps -------------------------------------------------------------------

// psRow carries the `docker ps --format` fields.
type psRow struct {
	ID, Names, Image, State, Status, Ports, Labels, CreatedAt string

	labels map[string]string
}

func (row psRow) Label(key string) string { return row.labels[key] }

func toPsRow(c appleContainer) psRow {
	state := dockerState(c.Status.State)
	status := "Exited"
	if state == "running" {
		status = "Up"
	}
	return psRow{
		ID:        c.ID,
		Names:     c.ID,
		Image:     c.Configuration.Image.Reference,
		State:     state,
		Status:    status,
		Ports:     formatPsPorts(c.Configuration.PublishedPorts),
		Labels:    joinLabels(c.Configuration.Labels),
		CreatedAt: c.Configuration.CreationDate,
		labels:    c.Configuration.Labels,
	}
}

// formatPsPorts renders ports the way `docker ps` shows them:
// "127.0.0.1:10000->10000/tcp".
func formatPsPorts(ports []applePort) string {
	parts := make([]string, 0, len(ports))
	for _, p := range ports {
		host := nonEmptyString(p.HostAddress, "0.0.0.0")
		proto := nonEmptyString(p.Proto, "tcp")
		if p.Count > 1 {
			parts = append(parts, fmt.Sprintf("%s:%d-%d->%d-%d/%s", host, p.HostPort, p.HostPort+p.Count-1,
				p.ContainerPort, p.ContainerPort+p.Count-1, proto))
			continue
		}
		parts = append(parts, fmt.Sprintf("%s:%d->%d/%s", host, p.HostPort, p.ContainerPort, proto))
	}
	return strings.Join(parts, ", ")
}

func joinLabels(labels map[string]string) string {
	keys := make([]string, 0, len(labels))
	for key := range labels {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		parts = append(parts, key+"="+labels[key])
	}
	return strings.Join(parts, ",")
}

type listOptions struct {
	all     bool
	quiet   bool
	filters []string
	format  string
	targets []string
}

// parseListOptions reads the ps / inspect / volume ls flags the CLI uses. The
// short -f is --filter for ps and volume ls but --format for inspect.
func parseListOptions(args []string, shortFIsFilter bool) listOptions {
	var opts listOptions
	for i := 0; i < len(args); i++ {
		arg := args[i]
		value := func() string {
			if _, v, ok := strings.Cut(arg, "="); ok && strings.HasPrefix(arg, "--") {
				return v
			}
			if i+1 < len(args) {
				i++
				return args[i]
			}
			return ""
		}
		switch {
		case arg == "-a" || arg == "--all":
			opts.all = true
		case arg == "-q" || arg == "--quiet":
			opts.quiet = true
		case arg == "--filter" || strings.HasPrefix(arg, "--filter=") || (arg == "-f" && shortFIsFilter):
			opts.filters = append(opts.filters, value())
		case arg == "--format" || strings.HasPrefix(arg, "--format=") || arg == "-f":
			opts.format = value()
		case arg == "--type" || arg == "--no-trunc" || arg == "-s" || arg == "--size":
			if arg == "--type" {
				i++
			}
		case strings.HasPrefix(arg, "-"):
			// Unknown boolean flag: ignored.
		default:
			opts.targets = append(opts.targets, arg)
		}
	}
	return opts
}

func psQuery(args []string) ([]appleStep, error) {
	opts := parseListOptions(args, true)
	format := opts.format
	if format == "" {
		format = "{{.Names}}"
		if opts.quiet {
			format = "{{.ID}}"
		}
	}
	tmpl, err := parseDockerTemplate(format)
	if err != nil {
		return nil, err
	}
	match, err := compileFilters(opts.filters)
	if err != nil {
		return nil, err
	}
	return []appleStep{{
		args: []string{"ls", "--all", "--format", "json"},
		render: func(stdout []byte) (string, error) {
			var containers []appleContainer
			if err := decodeJSON(stdout, &containers); err != nil {
				return "", err
			}
			var out strings.Builder
			for _, c := range containers {
				row := toPsRow(c)
				if !opts.all && row.State != "running" {
					continue
				}
				if !match(row.Names, row.ID, row.State, row.labels) {
					continue
				}
				if err := renderLine(&out, tmpl, row); err != nil {
					return "", err
				}
			}
			return out.String(), nil
		},
	}}, nil
}

// compileFilters builds a matcher for Docker's --filter: the same key ORs, and
// different keys AND. Supported keys: name (a regex, matched with and without
// Docker's leading "/"), id (a prefix), label (key or key=value), status.
func compileFilters(filters []string) (func(name, id, state string, labels map[string]string) bool, error) {
	byKey := map[string][]string{}
	for _, filter := range filters {
		key, value, _ := strings.Cut(filter, "=")
		byKey[key] = append(byKey[key], value)
	}
	nameRes := make([]*regexp.Regexp, 0, len(byKey["name"]))
	for _, pattern := range byKey["name"] {
		re, err := regexp.Compile(pattern)
		if err != nil {
			return nil, fmt.Errorf("invalid name filter %q: %w", pattern, err)
		}
		nameRes = append(nameRes, re)
	}
	for key := range byKey {
		switch key {
		case "name", "id", "label", "status":
		default:
			return nil, fmt.Errorf("filter %q is not supported on engine apple", key)
		}
	}
	anyOf := func(values []string, test func(string) bool) bool {
		if len(values) == 0 {
			return true
		}
		for _, value := range values {
			if test(value) {
				return true
			}
		}
		return false
	}
	return func(name, id, state string, labels map[string]string) bool {
		if len(nameRes) > 0 {
			hit := false
			for _, re := range nameRes {
				if re.MatchString(name) || re.MatchString("/"+name) {
					hit = true
					break
				}
			}
			if !hit {
				return false
			}
		}
		if !anyOf(byKey["id"], func(v string) bool { return strings.HasPrefix(id, v) }) {
			return false
		}
		if !anyOf(byKey["status"], func(v string) bool { return v == state }) {
			return false
		}
		// Docker ANDs label filters, unlike the other keys.
		for _, want := range byKey["label"] {
			key, value, hasValue := strings.Cut(want, "=")
			got, present := labels[key]
			if !present || (hasValue && got != value) {
				return false
			}
		}
		return true
	}, nil
}

// ---- inspect / port -------------------------------------------------------

type portBinding struct {
	HostIp   string
	HostPort string
}

// inspectDoc is the subset of `docker inspect` the CLI reads, filled from
// Apple container's JSON so `{{json .}}` and field templates work unchanged.
type inspectDoc struct {
	Id      string
	Name    string
	Created string
	State   struct {
		Status  string
		Running bool
	}
	Config struct {
		Image  string
		Labels map[string]string
		Env    []string
	}
	NetworkSettings struct {
		IPAddress string
		Gateway   string
		Ports     map[string][]portBinding
	}
	HostConfig struct {
		PortBindings map[string][]portBinding
	}
}

func toInspectDoc(c appleContainer) inspectDoc {
	var doc inspectDoc
	doc.Id = c.ID
	doc.Name = "/" + c.ID
	doc.Created = c.Configuration.CreationDate
	doc.State.Status = dockerState(c.Status.State)
	doc.State.Running = doc.State.Status == "running"
	doc.Config.Image = c.Configuration.Image.Reference
	doc.Config.Labels = c.Configuration.Labels
	if doc.Config.Labels == nil {
		doc.Config.Labels = map[string]string{}
	}
	doc.Config.Env = c.Configuration.InitProcess.Environment

	bindings := map[string][]portBinding{}
	for _, p := range c.Configuration.PublishedPorts {
		count := p.Count
		if count < 1 {
			count = 1
		}
		for offset := 0; offset < count; offset++ {
			key := fmt.Sprintf("%d/%s", p.ContainerPort+offset, nonEmptyString(p.Proto, "tcp"))
			bindings[key] = append(bindings[key], portBinding{HostIp: p.HostAddress, HostPort: strconv.Itoa(p.HostPort + offset)})
		}
	}
	doc.HostConfig.PortBindings = bindings
	doc.NetworkSettings.Ports = map[string][]portBinding{}
	if doc.State.Running {
		doc.NetworkSettings.Ports = bindings
		if len(c.Status.Networks) > 0 {
			doc.NetworkSettings.IPAddress, _, _ = strings.Cut(c.Status.Networks[0].IPv4Address, "/")
			doc.NetworkSettings.Gateway = c.Status.Networks[0].IPv4Gateway
		}
	}
	return doc
}

func inspectQuery(args []string) ([]appleStep, error) {
	opts := parseListOptions(args, false)
	if len(opts.targets) == 0 {
		return nil, fmt.Errorf("inspect needs at least one container name")
	}
	var tmpl *template.Template
	if opts.format != "" {
		var err error
		if tmpl, err = parseDockerTemplate(opts.format); err != nil {
			return nil, err
		}
	}
	return []appleStep{{
		args: append([]string{"inspect"}, opts.targets...),
		render: func(stdout []byte) (string, error) {
			var containers []appleContainer
			if err := decodeJSON(stdout, &containers); err != nil {
				return "", err
			}
			docs := make([]inspectDoc, 0, len(containers))
			for _, c := range containers {
				docs = append(docs, toInspectDoc(c))
			}
			if tmpl == nil {
				data, err := json.MarshalIndent(docs, "", "    ")
				return string(data) + "\n", err
			}
			var out strings.Builder
			for _, doc := range docs {
				if err := renderLine(&out, tmpl, doc); err != nil {
					return "", err
				}
			}
			return out.String(), nil
		},
	}}, nil
}

// portQuery answers `docker port <name> [<port>[/<proto>]]` from inspect:
// "10000/tcp -> 127.0.0.1:11000" per binding, or just the host side when a
// port is asked for.
func portQuery(args []string) ([]appleStep, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("port needs a container name")
	}
	name := args[0]
	want := ""
	if len(args) > 1 {
		want = args[1]
		if !strings.Contains(want, "/") {
			want += "/tcp"
		}
	}
	return []appleStep{{
		args: []string{"inspect", name},
		render: func(stdout []byte) (string, error) {
			var containers []appleContainer
			if err := decodeJSON(stdout, &containers); err != nil {
				return "", err
			}
			if len(containers) == 0 {
				return "", nil
			}
			doc := toInspectDoc(containers[0])
			keys := make([]string, 0, len(doc.NetworkSettings.Ports))
			for key := range doc.NetworkSettings.Ports {
				keys = append(keys, key)
			}
			sort.Strings(keys)
			var out strings.Builder
			for _, key := range keys {
				if want != "" && key != want {
					continue
				}
				for _, b := range doc.NetworkSettings.Ports[key] {
					host := nonEmptyString(b.HostIp, "0.0.0.0") + ":" + b.HostPort
					if want != "" {
						fmt.Fprintln(&out, host)
					} else {
						fmt.Fprintf(&out, "%s -> %s\n", key, host)
					}
				}
			}
			return out.String(), nil
		},
	}}, nil
}

// ---- image / volume -------------------------------------------------------

func imageInspectQuery(args []string) ([]appleStep, error) {
	opts := parseListOptions(args, false)
	if len(opts.targets) == 0 {
		return nil, fmt.Errorf("image inspect needs an image name")
	}
	format := nonEmptyString(opts.format, "{{json .}}")
	tmpl, err := parseDockerTemplate(format)
	if err != nil {
		return nil, err
	}
	return []appleStep{{
		args: append([]string{"image", "inspect"}, opts.targets...),
		render: func(stdout []byte) (string, error) {
			var images []appleImage
			if err := decodeJSON(stdout, &images); err != nil {
				return "", err
			}
			var out strings.Builder
			for _, image := range images {
				id := nonEmptyString(image.Configuration.Descriptor.Digest, "sha256:"+image.ID)
				doc := struct {
					Id       string
					RepoTags []string
					Created  string
				}{Id: id, RepoTags: []string{image.Configuration.Name}, Created: image.Configuration.CreationDate}
				if err := renderLine(&out, tmpl, doc); err != nil {
					return "", err
				}
			}
			return out.String(), nil
		},
	}}, nil
}

func volumeListQuery(args []string) ([]appleStep, error) {
	opts := parseListOptions(args, true)
	format := nonEmptyString(opts.format, "{{.Name}}")
	if opts.quiet {
		format = "{{.Name}}"
	}
	tmpl, err := parseDockerTemplate(format)
	if err != nil {
		return nil, err
	}
	match, err := compileFilters(opts.filters)
	if err != nil {
		return nil, err
	}
	return []appleStep{{
		args: []string{"volume", "list", "--format", "json"},
		render: func(stdout []byte) (string, error) {
			var volumes []appleVolume
			if err := decodeJSON(stdout, &volumes); err != nil {
				return "", err
			}
			var out strings.Builder
			for _, v := range volumes {
				name := nonEmptyString(v.Configuration.Name, v.ID)
				if !match(name, name, "", v.Configuration.Labels) {
					continue
				}
				row := struct{ Name, Driver, Mountpoint, Labels string }{
					Name: name, Driver: v.Configuration.Driver, Mountpoint: v.Configuration.Source,
					Labels: joinLabels(v.Configuration.Labels),
				}
				if err := renderLine(&out, tmpl, row); err != nil {
					return "", err
				}
			}
			return out.String(), nil
		},
	}}, nil
}

// ---- templates ------------------------------------------------------------

// parseDockerTemplate parses a Docker --format string with the helper
// functions Docker provides that the CLI uses.
func parseDockerTemplate(format string) (*template.Template, error) {
	if format == "json" {
		format = "{{json .}}"
	}
	format = strings.TrimPrefix(format, "table ")
	funcs := template.FuncMap{
		"json": func(v any) (string, error) {
			data, err := json.Marshal(v)
			return string(data), err
		},
		"join":  strings.Join,
		"split": strings.Split,
		"lower": strings.ToLower,
		"upper": strings.ToUpper,
	}
	tmpl, err := template.New("format").Funcs(funcs).Parse(format)
	if err != nil {
		return nil, fmt.Errorf("invalid --format %q: %w", format, err)
	}
	return tmpl, nil
}

func renderLine(out *strings.Builder, tmpl *template.Template, data any) error {
	if err := tmpl.Execute(out, data); err != nil {
		return err
	}
	out.WriteString("\n")
	return nil
}

func decodeJSON(data []byte, target any) error {
	trimmed := bytes.TrimSpace(data)
	if len(trimmed) == 0 {
		return nil
	}
	if err := json.Unmarshal(trimmed, target); err != nil {
		return fmt.Errorf("unexpected JSON from %s: %w", appleBinary, err)
	}
	return nil
}

func nonEmptyString(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

// appleSilentBuild is DockerBuild's --silence-build path for Apple
// container: both streams are captured (its builder, like Buildah, puts step
// output on stdout too) and shown only if the build fails.
func appleSilentBuild(flags DockerFlags, args ilist.List[ilist.List[string]]) error {
	buildArgs := append([]string{"build"}, translateBuildArgs(flattenArgs(args))...)
	if flags.Dryrun || flags.Verbose {
		printCmd(appleBinary, buildArgs)
	}
	if flags.Dryrun {
		return nil
	}

	progressOut, releaseProgressOut := buildProgressOut()
	defer releaseProgressOut()

	var captureBuf bytes.Buffer
	progress := newBuildProgress(&captureBuf, progressOut, EngineApple)
	defer progress.Close()

	cmd := exec.Command(appleBinary, buildArgs...)
	cmd.Env = commandEnv()
	cmd.Stdin = os.Stdin
	cmd.Stdout = progress
	cmd.Stderr = progress
	if err := cmd.Run(); err != nil {
		progress.Close()
		fmt.Fprintln(os.Stderr)
		fmt.Fprintf(os.Stderr, "❌ %s build failed!\n", appleBinary)
		fmt.Fprintln(os.Stderr, "---- Build output ----")
		fmt.Fprint(os.Stderr, captureBuf.String())
		fmt.Fprintln(os.Stderr, "----------------------")
		if exitErr, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("%s build failed with exit code %d", appleBinary, exitErr.ExitCode())
		}
		return fmt.Errorf("%s build failed: %w", appleBinary, err)
	}
	return nil
}
