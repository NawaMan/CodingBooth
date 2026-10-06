// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/hostescape"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// A booth is only as isolated as the container it runs in. Some settings hand code in the booth a
// way out onto the host — several of them as root: the --dind sidecar (privileged, with an
// unauthenticated daemon the booth can drive), and run-args such as --privileged, --pid=host, or a
// docker.sock mount. Any of them can come from a cloned repo's .booth/config.toml, so booth warns,
// with what each setting could lead to (hostescape.Impact), and asks before starting one. See
// docs/BOOTH_SECURITY.md.
//
// Consent is per run. The only non-interactive override is a command-line flag (--dind-allowed,
// --privileged-allowed); neither has a config.toml key or an environment variable, so a repo can
// never grant it to itself. The flag skips the question, not the warning.

// consentEnv is what the consent check reads from the host, so tests can fake it.
type consentEnv struct {
	euid          int
	home          string
	goos          string      // runtime.GOOS: Docker on macOS or Windows always runs in a VM
	wsl           bool        // running inside WSL, where Docker Desktop's VM is the WSL 2 VM
	dockerDesktop func() bool // the docker engine is Docker Desktop (a VM) rather than Docker Engine
	exists        func(path string) bool
	openTTY       func() (io.ReadWriteCloser, error)
	warnings      io.Writer
}

func defaultConsentEnv() consentEnv {
	return consentEnv{
		euid:          os.Geteuid(),
		home:          os.Getenv("HOME"),
		goos:          runtime.GOOS,
		wsl:           runningInWSL(),
		dockerDesktop: engineIsDockerDesktop,
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
// the user declines or there is no terminal to ask on. The warning is printed even when an
// --*-allowed flag covers every reason: the flag skips the question, not the warning.
func EnsureHostEscapeConsent(ctx appctx.AppContext) error {
	return ensureHostEscapeConsent(ctx, defaultConsentEnv())
}

func ensureHostEscapeConsent(ctx appctx.AppContext, env consentEnv) error {
	if ctx.Dryrun() {
		return nil
	}

	reasons := hostEscapeReasons(ctx, env)
	if len(reasons) == 0 {
		return nil
	}

	var pending []hostescape.Reason
	var flags []string
	earlier := false
	for _, reason := range reasons {
		switch {
		case reason.Kind == hostescape.KindDind && ctx.DindAllowed():
			flags = appendOnce(flags, "--dind-allowed")
		case reason.Kind != hostescape.KindDind && ctx.PrivilegedAllowed():
			flags = appendOnce(flags, "--privileged-allowed")
		case approvedReasons[reason.What]:
			earlier = true
		default:
			pending = append(pending, reason)
		}
	}

	fmt.Fprint(env.warnings, hostescape.Format(reasons))
	if len(pending) == 0 {
		fmt.Fprint(env.warnings, allowedNote(flags, earlier))
		return nil
	}

	tty, err := env.openTTY()
	if err != nil {
		return fmt.Errorf("refusing to start: this booth needs consent and there is no terminal to ask on.\n"+
			"To allow it, re-run with %s.", overrideFlags(pending))
	}
	defer tty.Close()

	fmt.Fprint(tty, "\nStart this booth? [y/N]: ")
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

// allowedNote is the closing line when nothing is left to ask: which flag, or an earlier "yes" in
// this process (a booth--restart), covered the reasons.
func allowedNote(flags []string, earlier bool) string {
	var why []string
	if len(flags) > 0 {
		why = append(why, "allowed by "+strings.Join(flags, " and "))
	}
	if earlier {
		why = append(why, "approved earlier in this session")
	}
	return "  " + capitalize(strings.Join(why, "; ")) + " — starting without asking.\n"
}

func capitalize(text string) string {
	if text == "" {
		return text
	}
	return strings.ToUpper(text[:1]) + text[1:]
}

func appendOnce(list []string, item string) []string {
	for _, existing := range list {
		if existing == item {
			return list
		}
	}
	return append(list, item)
}

func overrideFlags(reasons []hostescape.Reason) string {
	var dind, privileged bool
	for _, reason := range reasons {
		if reason.Kind == hostescape.KindDind {
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

// SecurityWarning is the warning for this booth's settings, without a prompt or closing line, and
// whether there is anything to warn about. It ignores --dind-allowed / --privileged-allowed: it
// reports what the booth would get, not whether the user agreed to it.
func SecurityWarning(ctx appctx.AppContext) (string, bool) {
	reasons := hostEscapeReasons(ctx, defaultConsentEnv())
	return hostescape.Format(reasons), len(reasons) > 0
}

// LabelHostEscape records the booth's reasons on its container (hostescape.LabelKey), so a later
// `booth start`, `booth shell`, or `booth exec` that starts it again can print the same warning.
// Run it right after EnsureHostEscapeConsent, before booth adds its own run arguments.
func LabelHostEscape(ctx appctx.AppContext) appctx.AppContext {
	value := hostescape.EncodeLabel(hostEscapeReasons(ctx, defaultConsentEnv()))
	if value == "" {
		return ctx
	}
	builder := ctx.ToBuilder()
	builder.CommonArgs.Append(ilist.NewList[string]("--label", hostescape.LabelKey+"="+value))
	return builder.Build()
}

// escapeTarget is where a way out of the container lands on this booth's engine. Every setting is
// still reported on a VM-based engine (root in that VM reaches the folders it shares from this
// machine, as the user), only its impact line changes. docker info is asked only when there is
// something to report, to tell Docker Desktop for Linux (a VM) from Docker Engine.
func escapeTarget(ctx appctx.AppContext, env consentEnv) hostescape.Where {
	engine := ctx.Engine()
	switch {
	case engine == docker.EngineApple:
		return hostescape.WhereApple
	case env.goos == "windows":
		return hostescape.WhereWSL
	case env.goos == "darwin":
		return hostescape.WhereVM
	case engine == "podman" && env.euid != 0:
		return hostescape.WhereAccount
	case engine == "podman":
		return hostescape.WhereHost
	case env.dockerDesktop():
		if env.wsl {
			return hostescape.WhereWSL
		}
		return hostescape.WhereVM
	}
	return hostescape.WhereHost
}

// hostEscapeReasons lists the settings of this booth that give it a way onto the host, each with
// where it lands on this engine.
//
// Under rootless Podman (the container's root is the user's own account) and Apple container
// (each container is its own VM, and the engine rejects most of these flags anyway), --dind and the
// kernel-access settings do not reach this machine by themselves and are left out. Mounts, engine
// sockets, and host networking still do.
func hostEscapeReasons(ctx appctx.AppContext, env consentEnv) []hostescape.Reason {
	var found []hostescape.Reason
	if ctx.Dind() {
		found = append(found, hostescape.Reason{Kind: hostescape.KindDind, What: "--dind (privileged Docker-in-Docker sidecar)"})
	}
	found = append(found, dangerousRunArgs(flattenUserArgs(ctx), env)...)
	if len(found) == 0 {
		return nil
	}

	where := escapeTarget(ctx, env)
	var reasons []hostescape.Reason
	for _, reason := range found {
		ownVMOrAccount := where == hostescape.WhereAccount || where == hostescape.WhereApple
		if ownVMOrAccount && (reason.Kind == hostescape.KindDind || reason.Kind == hostescape.KindKernelAccess) {
			continue
		}
		reason.Where = where
		// A socket mounted into a rootless booth may belong to a rootful daemon on the host.
		if where == hostescape.WhereAccount && reason.Kind == hostescape.KindEngineSocket {
			reason.Where = hostescape.WhereHost
		}
		reasons = append(reasons, reason)
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
// host, as on rootful Docker on Linux; hostEscapeReasons adjusts for the engine. It is a list of
// known ways, not a proof of safety: run-args is a raw passthrough to the engine, so
// docs/BOOTH_SECURITY.md still tells users to read what they pass.
func dangerousRunArgs(args []string, env consentEnv) []hostescape.Reason {
	var hits []hostescape.Reason
	seen := map[string]bool{}
	add := func(kind hostescape.Kind, what string) {
		if !seen[what] {
			seen[what] = true
			hits = append(hits, hostescape.Reason{Kind: kind, What: what})
		}
	}
	addMount := func(hit hostescape.Reason) {
		if hit.What != "" {
			add(hit.Kind, hit.What)
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
			addMount(dangerousMount(source, isReadOnlyVolume(spec), env))
		case "--mount":
			source, readOnly := parseMountSpec(next())
			addMount(dangerousMount(source, readOnly, env))
		}

		switch flag {
		case "--privileged":
			if !hasValue || strings.EqualFold(value, "true") {
				add(hostescape.KindKernelAccess, "--privileged")
			}
		case "--cap-add":
			for _, capability := range strings.Split(next(), ",") {
				if isDangerousCapability(capability) {
					add(hostescape.KindKernelAccess, "--cap-add "+capability)
				}
			}
		case "--device-cgroup-rule":
			add(hostescape.KindKernelAccess, "--device-cgroup-rule "+next())
		case "--device":
			path, _, _ := strings.Cut(next(), ":")
			// A device the host does not have is dropped before the run (FilterMissingDevices).
			if !isSafeDevice(path) && env.exists(path) {
				add(hostescape.KindKernelAccess, "--device "+path)
			}
		case "--pid", "--ipc", "--userns":
			if v := next(); v == "host" {
				add(hostescape.KindKernelAccess, flag+"=host")
			}
		case "--network", "--net":
			if v := next(); v == "host" {
				add(hostescape.KindHostNetwork, flag+"=host")
			}
		case "--security-opt":
			if v := next(); strings.Contains(v, "unconfined") || strings.HasPrefix(v, "label=disable") ||
				strings.HasPrefix(v, "label:disable") {
				add(hostescape.KindKernelAccess, "--security-opt "+v)
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

// dangerousMount describes a bind mount that gives the booth a way onto the host, or a Reason with
// an empty What if it does not. A container-engine socket is dangerous even read-only (read-only
// does not stop anyone talking to the daemon behind it); other paths only when writable.
func dangerousMount(source string, readOnly bool, env consentEnv) hostescape.Reason {
	none := hostescape.Reason{}
	hostMount := func(what string) hostescape.Reason {
		return hostescape.Reason{Kind: hostescape.KindHostMounts, What: what}
	}
	homeMount := func(what string) hostescape.Reason {
		return hostescape.Reason{Kind: hostescape.KindHomeMounts, What: what}
	}
	if strings.HasPrefix(source, "~") && env.home != "" {
		source = env.home + source[1:]
	}
	if !strings.HasPrefix(source, "/") {
		return none // a named volume, not a host path
	}
	source = filepath.Clean(source)

	base := filepath.Base(source)
	if strings.HasSuffix(base, ".sock") &&
		(strings.Contains(base, "docker") || strings.Contains(base, "podman") || strings.Contains(base, "containerd")) {
		return hostescape.Reason{Kind: hostescape.KindEngineSocket, What: "container engine socket mount (" + source + ")"}
	}
	if readOnly {
		return none
	}

	if source == "/" {
		return hostMount("writable mount of the host root filesystem (/)")
	}
	for _, sensitive := range sensitiveHostPaths {
		if source == sensitive || strings.HasPrefix(source, sensitive+"/") {
			return hostMount("writable mount of host " + source)
		}
	}
	// Writing the home directory or its dotfiles (~/.bashrc, ~/.ssh, ~/.config/...) runs code as
	// the user the next time they log in.
	if env.home != "" {
		home := filepath.Clean(env.home)
		if source == home || source == filepath.Dir(home) {
			return homeMount("writable mount of host " + source)
		}
		if rel, err := filepath.Rel(home, source); err == nil && strings.HasPrefix(rel, ".") && !strings.HasPrefix(rel, "..") {
			return homeMount("writable mount of host " + source)
		}
	}
	return none
}

// engineIsDockerDesktop asks the docker engine (once per process) whether it is Docker Desktop, which
// runs containers in a VM even on Linux. Any failure counts as no: the warning then says "host",
// the stronger claim.
var engineIsDockerDesktop = sync.OnceValue(func() bool {
	out, err := exec.Command("docker", "info", "--format", "{{.OperatingSystem}}").Output()
	return err == nil && strings.Contains(string(out), "Docker Desktop")
})

// runningInWSL reports whether booth runs inside WSL, where /proc/version names Microsoft.
func runningInWSL() bool {
	data, err := os.ReadFile("/proc/version")
	return err == nil && strings.Contains(strings.ToLower(string(data)), "microsoft")
}
