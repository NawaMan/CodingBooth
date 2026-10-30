// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package prepare is `booth prepare gha|ubuntu` (EXPERIMENT, docs/REUSE_BOOTH.md):
// it makes the current machine run a project's booth code without a container, by
// replaying the base image, a variant, the project's Boothfile and the user steps
// of booth-entry on the machine itself. This file is the decision logic, kept free
// of side effects so it can be unit tested; run.go carries it out.
package prepare

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"

	"github.com/nawaman/codingbooth/src/pkg/booth"
)

// Target is the kind of machine being prepared.
type Target string

const (
	GHA    Target = "gha"
	Ubuntu Target = "ubuntu"
)

// UbuntuRelease is the release the base image is built on. The setups expect it.
const UbuntuRelease = "26.04"

// CBTarget is the CB_TARGET value the scripts and the guarded booth-entry read.
func (t Target) CBTarget() string {
	if t == GHA {
		return "gha"
	}
	return "host"
}

// ParseTarget accepts the command's target word.
func ParseTarget(s string) (Target, error) {
	switch s {
	case "gha":
		return GHA, nil
	case "ubuntu":
		return Ubuntu, nil
	}
	return "", fmt.Errorf("unknown target %q (expected gha or ubuntu)", s)
}

// ParseOSRelease reads /etc/os-release content into KEY -> value.
func ParseOSRelease(content string) map[string]string {
	out := map[string]string{}
	sc := bufio.NewScanner(strings.NewReader(content))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		out[k] = strings.Trim(v, `"'`)
	}
	return out
}

// CheckMachine says whether this machine matches the target: Ubuntu 26.04 for both,
// and a GitHub Actions runner (GITHUB_ACTIONS=true with GITHUB_ENV set) for gha.
func CheckMachine(t Target, osRelease map[string]string, getenv func(string) string) error {
	id, ver := osRelease["ID"], osRelease["VERSION_ID"]
	if id != "ubuntu" || ver != UbuntuRelease {
		name := osRelease["PRETTY_NAME"]
		if name == "" {
			name = strings.TrimSpace(id + " " + ver)
		}
		if name == "" {
			name = "an unknown OS"
		}
		return fmt.Errorf("this machine runs %s; booth prepare %s needs Ubuntu %s, the release the base image is built on", name, t, UbuntuRelease)
	}
	if t == GHA {
		if getenv("GITHUB_ACTIONS") != "true" {
			return fmt.Errorf("booth prepare gha runs on a GitHub Actions runner (GITHUB_ACTIONS is not true here); use booth prepare ubuntu on another Ubuntu machine")
		}
		if getenv("GITHUB_ENV") == "" || getenv("GITHUB_PATH") == "" {
			return fmt.Errorf("GITHUB_ENV / GITHUB_PATH are not set; booth prepare gha must run as a workflow step")
		}
	}
	return nil
}

// Variants are the canonical variant names; aliases map onto them as `booth run` does.
var Variants = []string{"base", "notebook", "codeserver", "desktop-xfce", "desktop-kde", "desktop-lxqt", "desktop-wayland"}

// CanonicalVariant resolves a variant name or alias, the same set as `--variant`.
var CanonicalVariant = booth.CanonicalVariant

// ResolveVariant picks the variant to prepare. gha is always base (a GHA run is a
// base booth): a --variant other than base is an error, and a config.toml variant is
// only noted. ubuntu takes --variant, else config.toml's variant, else base.
func ResolveVariant(t Target, flagVariant, configVariant string) (variant, note string, err error) {
	if t == GHA {
		if flagVariant != "" {
			if v, ok := CanonicalVariant(flagVariant); !ok || v != "base" {
				return "", "", fmt.Errorf("booth prepare gha always prepares a base booth; --variant %s is not allowed", flagVariant)
			}
		}
		if v, ok := CanonicalVariant(configVariant); configVariant != "" && ok && v != "base" {
			note = fmt.Sprintf("config.toml asks for variant %s; a GHA run is a base booth, so graphic and notebook parts are skipped", v)
		}
		return "base", note, nil
	}
	chosen, from := flagVariant, "--variant"
	if chosen == "" {
		chosen, from = configVariant, "config.toml variant"
	}
	v, ok := CanonicalVariant(chosen)
	if !ok {
		return "", "", fmt.Errorf("unknown %s %q (valid: %s; aliases: console|terminal|ide|desktop|xfce|kde|lxqt|wayland)",
			from, chosen, strings.Join(Variants, "|"))
	}
	return v, "", nil
}

// Config is the part of .booth/config.toml prepare reads.
type Config struct {
	Variant string   `toml:"variant"`
	RunArgs []string `toml:"run-args"`
	Dind    bool     `toml:"dind"`
}

// LoadConfig reads .booth/config.toml; a missing file is an empty Config.
func LoadConfig(path string) (Config, error) {
	var c Config
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	if _, err := toml.Decode(string(data), &c); err != nil {
		return c, fmt.Errorf("%s: %w", path, err)
	}
	return c, nil
}

// EnvVar is one KEY=VALUE.
type EnvVar struct{ Key, Value string }

// RunArgsEnv takes the -e/--env KEY=VALUE pairs out of config.toml run-args: what a
// booth's processes get from `docker run`. A bare -e KEY (passed through from the
// host's environment) is skipped and named, as is every other run-arg.
func RunArgsEnv(runArgs []string) (env []EnvVar, skipped []string) {
	for i := 0; i < len(runArgs); i++ {
		a := runArgs[i]
		var val string
		switch {
		case a == "-e" || a == "--env":
			if i+1 >= len(runArgs) {
				skipped = append(skipped, a)
				continue
			}
			i++
			val = runArgs[i]
		case strings.HasPrefix(a, "--env="):
			val = strings.TrimPrefix(a, "--env=")
		case strings.HasPrefix(a, "-e") && len(a) > 2:
			val = strings.TrimPrefix(a, "-e")
		default:
			skipped = append(skipped, a)
			continue
		}
		k, v, ok := strings.Cut(val, "=")
		if !ok || k == "" {
			skipped = append(skipped, "-e "+val+" (taken from the host environment)")
			continue
		}
		env = append(env, EnvVar{k, v})
	}
	return env, skipped
}

// RewriteHome replaces /home/coder, the booth user's home, with home in each value,
// as provision-example.sh does for the Boothfile's env lines.
func RewriteHome(env []EnvVar, home string) []EnvVar {
	out := make([]EnvVar, len(env))
	for i, e := range env {
		out[i] = EnvVar{e.Key, strings.ReplaceAll(e.Value, "/home/coder", home)}
	}
	return out
}

// ConfigProfile is /etc/profile.d/06-cb-config-env.sh: CB_TARGET first, so a later
// shell or script can tell it is not in a booth (on gha it reaches later steps
// through GITHUB_ENV), then config.toml's -e KEY=VALUE run-args.
func ConfigProfile(cbTarget string, env []EnvVar) string {
	var b strings.Builder
	b.WriteString("# Profile: booth prepare's target and the -e run-args of .booth/config.toml.\n")
	fmt.Fprintf(&b, "export CB_TARGET=%s\n", shellQuote(cbTarget))
	for _, e := range env {
		fmt.Fprintf(&b, "export %s=%s\n", e.Key, shellQuote(e.Value))
	}
	return b.String()
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// UserDecision is who prepare sets the machine up for.
type UserDecision struct {
	Name    string // the user the setups and booth-entry user steps are for
	Create  bool   // root with --add-user: create the user (if missing) and add to sudo
	UseSudo bool   // not root: the root phases run through sudo
}

// DecideUser applies the rules: a non-root user prepares for itself, through sudo;
// root must name a user with --add-user. --add-user is only for root.
func DecideUser(euid int, currentUser, addUser string) (UserDecision, error) {
	if euid == 0 {
		if addUser == "" {
			return UserDecision{}, fmt.Errorf("running as root: use --add-user <name> to prepare the machine for that user (it is created if missing and added to sudo)")
		}
		if !validUserName(addUser) {
			return UserDecision{}, fmt.Errorf("--add-user %q is not a valid user name", addUser)
		}
		return UserDecision{Name: addUser, Create: true}, nil
	}
	if addUser != "" {
		return UserDecision{}, fmt.Errorf("--add-user is for root; as %s, booth prepare sets the machine up for %s", currentUser, currentUser)
	}
	return UserDecision{Name: currentUser, UseSudo: true}, nil
}

func validUserName(s string) bool {
	if s == "" || len(s) > 32 || s == "root" {
		return false
	}
	for i, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r == '_':
		case (r >= '0' && r <= '9') || r == '-':
			if i == 0 {
				return false
			}
		default:
			return false
		}
	}
	return true
}

// envSkip lists variables a login shell sets for itself; they are not exported to GitHub.
var envSkip = map[string]bool{
	"_": true, "PWD": true, "OLDPWD": true, "SHLVL": true, "PATH": true, "HOME": true, "USER": true,
	"LOGNAME": true, "SHELL": true, "TERM": true, "MAIL": true, "BASH_ENV": true, "PS1": true,
}

// GitHubExports compares the environment of a login shell (after) with the step's
// own (before) and returns what later workflow steps need: the lines for
// $GITHUB_ENV (new or changed variables, in multi-line-safe form) and for
// $GITHUB_PATH (login PATH entries the step does not have, so that the final order
// matches the login shell's: GitHub puts the last line written first).
func GitHubExports(before, after map[string]string, delimiter string) (envFile string, pathLines []string) {
	keys := make([]string, 0, len(after))
	for k, v := range after {
		if envSkip[k] || strings.HasPrefix(k, "BASH_FUNC_") || strings.HasPrefix(k, "GITHUB_") || strings.HasPrefix(k, "RUNNER_") {
			continue
		}
		if old, ok := before[k]; ok && old == v {
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		fmt.Fprintf(&b, "%s<<%s\n%s\n%s\n", k, delimiter, after[k], delimiter)
	}

	have := map[string]bool{}
	for _, p := range strings.Split(before["PATH"], ":") {
		have[p] = true
	}
	var add []string
	for _, p := range strings.Split(after["PATH"], ":") {
		if p != "" && !have[p] {
			have[p] = true
			add = append(add, p)
		}
	}
	for i := len(add) - 1; i >= 0; i-- {
		pathLines = append(pathLines, add[i])
	}
	return b.String(), pathLines
}

// ParseEnv0 parses `env -0` output.
func ParseEnv0(data []byte) map[string]string {
	out := map[string]string{}
	for _, kv := range strings.Split(string(data), "\x00") {
		if k, v, ok := strings.Cut(kv, "="); ok && k != "" {
			out[k] = v
		}
	}
	return out
}

// ReportFailures returns the FAIL lines of a provisioning report.
func ReportFailures(report string) []string {
	var out []string
	for _, line := range strings.Split(report, "\n") {
		if strings.HasPrefix(line, "FAIL ") {
			out = append(out, line)
		}
	}
	return out
}
