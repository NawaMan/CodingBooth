// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// A booth is only as isolated as the container it runs in. Some settings hand code in the booth a
// way out onto the host as root: the --dind sidecar (privileged, with an unauthenticated daemon the
// booth can drive), and run-args such as --privileged, --pid=host, or a docker.sock mount. Any of
// them can come from a cloned repo's .booth/config.toml, so booth stops and asks before starting
// one. See docs/BOOTH_SECURITY.md.
//
// Consent is per run. The only non-interactive override is a command-line flag (--dind-allowed,
// --privileged-allowed); neither has a config.toml key or an environment variable, so a repo can
// never grant it to itself.

// hostEscapeReason is one setting that needs consent, and which override flag covers it.
type hostEscapeReason struct {
	What string // shown to the user, e.g. "--dind (privileged Docker-in-Docker sidecar)"
	Dind bool   // true: covered by --dind-allowed; false: covered by --privileged-allowed
}

// consentEnv is what the consent check reads from the host, so tests can fake it.
type consentEnv struct {
	euid     int
	home     string
	exists   func(path string) bool
	openTTY  func() (io.ReadWriteCloser, error)
	warnings io.Writer
}

func defaultConsentEnv() consentEnv {
	return consentEnv{
		euid: os.Geteuid(),
		home: os.Getenv("HOME"),
		exists: func(path string) bool {
			_, err := os.Stat(path)
			return err == nil
		},
		// The prompt goes to the controlling terminal, not stdin/stdout, so it still works when
		// booth is started by `booth shell --run` (whose stdout is redirected) and cannot be
		// answered by whatever is piped into stdin.
		openTTY: func() (io.ReadWriteCloser, error) {
			return os.OpenFile("/dev/tty", os.O_RDWR, 0)
		},
		warnings: os.Stderr,
	}
}

// approvedReasons remembers what the user already agreed to in this process, so a booth--restart
// of the same booth does not ask again. Anything new since then still asks.
var approvedReasons = map[string]bool{}

// EnsureHostEscapeConsent stops before anything is built or started when the booth would get a way
// out onto the host, and asks the user to confirm. It returns an error (and starts nothing) when
// the user declines or there is no terminal to ask on.
func EnsureHostEscapeConsent(ctx appctx.AppContext) error {
	return ensureHostEscapeConsent(ctx, defaultConsentEnv())
}

func ensureHostEscapeConsent(ctx appctx.AppContext, env consentEnv) error {
	if ctx.Dryrun() {
		return nil
	}

	var pending []hostEscapeReason
	for _, reason := range hostEscapeReasons(ctx, env) {
		covered := (reason.Dind && ctx.DindAllowed()) || (!reason.Dind && ctx.PrivilegedAllowed())
		if !covered && !approvedReasons[reason.What] {
			pending = append(pending, reason)
		}
	}
	if len(pending) == 0 {
		return nil
	}

	fmt.Fprint(env.warnings, hostEscapeWarning(pending))

	tty, err := env.openTTY()
	if err != nil {
		return fmt.Errorf("refusing to start: this booth needs consent and there is no terminal to ask on.\n"+
			"To allow it, re-run with %s.", overrideFlags(pending))
	}
	defer tty.Close()

	fmt.Fprint(tty, "\nStart this booth anyway? [y/N]: ")
	line, _ := bufio.NewReader(tty).ReadString('\n')
	switch strings.ToLower(strings.TrimSpace(line)) {
	case "y", "yes":
		for _, reason := range pending {
			approvedReasons[reason.What] = true
		}
		return nil
	default:
		return fmt.Errorf("aborted: not starting a booth that can reach the host")
	}
}

func hostEscapeWarning(reasons []hostEscapeReason) string {
	var str strings.Builder
	str.WriteString("\n⚠️  This booth can break out of its container onto the host:\n")
	for _, reason := range reasons {
		fmt.Fprintf(&str, "      - %s\n", reason.What)
	}
	str.WriteString("" +
		"    Any code running in the booth could then read and write the host filesystem and run\n" +
		"    commands on the host as root. Only continue if you trust everything this booth runs.\n" +
		"    See docs/BOOTH_SECURITY.md.\n")
	return str.String()
}

func overrideFlags(reasons []hostEscapeReason) string {
	var dind, privileged bool
	for _, reason := range reasons {
		if reason.Dind {
			dind = true
		} else {
			privileged = true
		}
	}
	switch {
	case dind && privileged:
		return "--dind-allowed --privileged-allowed"
	case dind:
		return "--dind-allowed"
	default:
		return "--privileged-allowed"
	}
}

// rootlessPodman is the one engine where "privileged" stays inside the user's own account: the
// container's root is the host user, so a breakout lands as that user, not as host root.
func rootlessPodman(ctx appctx.AppContext, env consentEnv) bool {
	return ctx.Engine() == "podman" && env.euid != 0
}

// hostEscapeReasons lists the settings of this booth that give it a way onto the host.
func hostEscapeReasons(ctx appctx.AppContext, env consentEnv) []hostEscapeReason {
	var reasons []hostEscapeReason
	rootless := rootlessPodman(ctx, env)

	if ctx.Dind() && !rootless {
		reasons = append(reasons, hostEscapeReason{What: "--dind (privileged Docker-in-Docker sidecar)", Dind: true})
	}
	for _, what := range dangerousRunArgs(flattenUserArgs(ctx), env, rootless) {
		reasons = append(reasons, hostEscapeReason{What: what})
	}
	return reasons
}

// flattenUserArgs collects the user's run-args and common-args. It runs before booth adds its own
// args (the project mount, --network, ...), so it sees only what the user or config asked for.
func flattenUserArgs(ctx appctx.AppContext) []string {
	var out []string
	for _, group := range ctx.RunArgs().Slice() {
		out = append(out, group.Slice()...)
	}
	for _, group := range ctx.CommonArgs().Slice() {
		out = append(out, group.Slice()...)
	}
	return out
}

// safeDevices are device nodes that templates pass on purpose and that do not open the host up:
// KVM (Android emulator), GPU render nodes, TUN, and FUSE.
var safeDevices = []string{"/dev/kvm", "/dev/dri", "/dev/net/tun", "/dev/fuse"}

// sensitiveHostPaths are host directories whose writable bind mount is a way to run code as root
// on the host (or to read every secret on it).
var sensitiveHostPaths = []string{
	"/etc", "/root", "/boot", "/dev", "/proc", "/sys", "/run", "/var/run",
	"/usr", "/bin", "/sbin", "/lib", "/lib64", "/var/lib/docker", "/var/lib/containers",
}

// dangerousRunArgs returns a description of each run-arg that gives the booth a way onto the
// host. It is a list of known ways, not a proof of safety: run-args is a raw passthrough to the
// engine, so docs/BOOTH_SECURITY.md still tells users to read what they pass.
//
// Under rootless Podman only an engine-socket mount is reported: every other way out lands as the
// user's own account.
func dangerousRunArgs(args []string, env consentEnv, rootless bool) []string {
	var hits []string
	seen := map[string]bool{}
	add := func(what string) {
		if !seen[what] {
			seen[what] = true
			hits = append(hits, what)
		}
	}

	for i := 0; i < len(args); i++ {
		arg := args[i]
		flag, value, hasValue := strings.Cut(arg, "=")
		next := func() string {
			if hasValue {
				return value
			}
			if i+1 < len(args) {
				i++
				return args[i]
			}
			return ""
		}

		switch flag {
		case "-v", "--volume":
			source, _, _ := strings.Cut(next(), ":")
			spec := args[i]
			if hasValue {
				spec = value
			}
			if what := dangerousMount(source, isReadOnlyVolume(spec), env, rootless); what != "" {
				add(what)
			}
		case "--mount":
			source, readOnly := parseMountSpec(next())
			if what := dangerousMount(source, readOnly, env, rootless); what != "" {
				add(what)
			}
		}
		if rootless {
			continue
		}

		switch flag {
		case "--privileged":
			if !hasValue || strings.EqualFold(value, "true") {
				add("--privileged")
			}
		case "--cap-add":
			for _, capability := range strings.Split(next(), ",") {
				if isDangerousCapability(capability) {
					add("--cap-add " + capability)
				}
			}
		case "--device-cgroup-rule":
			add("--device-cgroup-rule " + next())
		case "--device":
			path, _, _ := strings.Cut(next(), ":")
			// A device the host does not have is dropped before the run (FilterMissingDevices).
			if !isSafeDevice(path) && env.exists(path) {
				add("--device " + path)
			}
		case "--pid", "--ipc", "--userns":
			if v := next(); v == "host" {
				add(flag + "=host")
			}
		case "--network", "--net":
			if v := next(); v == "host" {
				add(flag + "=host (reaches every service listening on the host)")
			}
		case "--security-opt":
			if v := next(); strings.Contains(v, "unconfined") || strings.HasPrefix(v, "label=disable") ||
				strings.HasPrefix(v, "label:disable") {
				add("--security-opt " + v)
			}
		}
	}
	return hits
}

// dangerousCapabilities are the ones a container can use to reach the host kernel, its disks, or
// files it could not otherwise open. Capabilities that only act inside the booth's own namespaces
// (NET_ADMIN, SYS_PTRACE without --pid=host, ...) are left alone.
var dangerousCapabilities = map[string]bool{
	"ALL": true, "SYS_ADMIN": true, "SYS_MODULE": true, "SYS_RAWIO": true, "DAC_READ_SEARCH": true,
	"BPF": true, "PERFMON": true, "SYS_BOOT": true, "MAC_ADMIN": true, "MAC_OVERRIDE": true,
}

func isDangerousCapability(capability string) bool {
	name := strings.ToUpper(strings.TrimSpace(capability))
	return dangerousCapabilities[strings.TrimPrefix(name, "CAP_")]
}

func isSafeDevice(path string) bool {
	for _, safe := range safeDevices {
		if path == safe || strings.HasPrefix(path, safe+"/") {
			return true
		}
	}
	return false
}

// isReadOnlyVolume reports whether a -v spec (src:dst[:opts]) is mounted read-only.
func isReadOnlyVolume(spec string) bool {
	parts := strings.Split(spec, ":")
	if len(parts) < 3 {
		return false
	}
	for _, opt := range strings.Split(parts[len(parts)-1], ",") {
		if opt == "ro" || opt == "readonly" {
			return true
		}
	}
	return false
}

// parseMountSpec pulls the source and read-only flag out of a --mount spec. Only bind mounts have
// a host source; volumes and tmpfs return "".
func parseMountSpec(spec string) (source string, readOnly bool) {
	bind := false
	for _, field := range strings.Split(spec, ",") {
		key, value, _ := strings.Cut(field, "=")
		switch key {
		case "type":
			bind = value == "bind"
		case "source", "src":
			source = value
		case "readonly", "ro":
			readOnly = value == "" || value == "true" || value == "1"
		}
	}
	if !bind {
		return "", readOnly
	}
	return source, readOnly
}

// dangerousMount describes a bind mount that gives the booth a way onto the host, or "" if it
// does not. A container-engine socket is dangerous even read-only (read-only does not stop anyone
// talking to the daemon behind it); other paths only when writable.
func dangerousMount(source string, readOnly bool, env consentEnv, rootless bool) string {
	if strings.HasPrefix(source, "~") && env.home != "" {
		source = env.home + source[1:]
	}
	if !strings.HasPrefix(source, "/") {
		return "" // a named volume, not a host path
	}
	source = filepath.Clean(source)

	base := filepath.Base(source)
	if strings.HasSuffix(base, ".sock") &&
		(strings.Contains(base, "docker") || strings.Contains(base, "podman") || strings.Contains(base, "containerd")) {
		return "container engine socket mount (" + source + ")"
	}
	if readOnly || rootless {
		return ""
	}

	if source == "/" {
		return "writable mount of the host root filesystem (/)"
	}
	for _, sensitive := range sensitiveHostPaths {
		if source == sensitive || strings.HasPrefix(source, sensitive+"/") {
			return "writable mount of host " + source
		}
	}
	// Writing the home directory or its dotfiles (~/.bashrc, ~/.ssh, ~/.config/...) runs code as
	// the user the next time they log in.
	if env.home != "" {
		home := filepath.Clean(env.home)
		if source == home || source == filepath.Dir(home) {
			return "writable mount of host " + source
		}
		if rel, err := filepath.Rel(home, source); err == nil && strings.HasPrefix(rel, ".") && !strings.HasPrefix(rel, "..") {
			return "writable mount of host " + source
		}
	}
	return ""
}
