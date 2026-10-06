// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package hostescape holds the security warning booth prints when a booth has settings that let
// code inside it reach the host. The booth package decides which settings those are; this package
// only says what each kind can lead to, formats the warning, and carries the reasons on the
// container's label so lifecycle commands (start, shell, exec) can print the same warning when they
// start a booth again. See docs/BOOTH_SECURITY.md.
package hostescape

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Kind groups the settings by what untrusted code could do with them.
type Kind string

const (
	KindDind         Kind = "dind"          // the --dind sidecar
	KindEngineSocket Kind = "engine-socket" // a docker/podman/containerd socket mount
	KindKernelAccess Kind = "kernel-access" // --privileged, capabilities, devices, host namespaces, ...
	KindHostMounts   Kind = "host-mounts"   // a writable mount of a host system path
	KindHomeMounts   Kind = "home-mounts"   // a writable mount of the home directory or its dotfiles
	KindHostNetwork  Kind = "host-network"  // --network=host
)

// Where is where a way out of the container lands, which depends on the engine. See
// docs/BOOTH_ENGINES.md.
type Where string

const (
	// WhereHost: the engine runs on this machine as root (Docker or Podman, rootful, on Linux).
	WhereHost Where = ""
	// WhereAccount: rootless Podman; the container's root is the user's own account.
	WhereAccount Where = "account"
	// WhereVM: the engine runs in a Linux VM (Docker Desktop, Colima, Podman machine, ...) that
	// shares some of this machine's folders.
	WhereVM Where = "vm"
	// WhereWSL: the engine's VM is the WSL 2 VM, which also runs the user's other WSL distros.
	WhereWSL Where = "wsl"
	// WhereApple: Apple container; each container is its own VM.
	WhereApple Where = "apple"
)

// Reason is one setting that lets code in the booth reach the host.
type Reason struct {
	Kind  Kind   `json:"kind"`
	What  string `json:"what"`            // the setting itself, e.g. "--privileged"
	Where Where  `json:"where,omitempty"` // where it lands; "" is the host itself
}

// LabelKey is the container label that records the reasons a booth was created with.
const LabelKey = "cb.security-warning"

// DocURL is the page the warning links to; each kind has an anchor there.
const DocURL = "https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md"

// Impact says what untrusted code could do with a setting of this kind, on an engine where a way
// out lands at where.
func Impact(kind Kind, where Where) string {
	const could = "Untrusted code in the booth could "
	inVM := "get root in the engine's Linux VM (not this machine itself), and through it change the folders the VM shares from this machine, such as your home, as you."
	if where == WhereWSL {
		inVM = "get root in the WSL 2 VM the engine runs in (not Windows itself) — the VM that also runs your other WSL distros — and through it change your Windows files that it shares, as you."
	}

	switch kind {
	case KindDind, KindEngineSocket, KindKernelAccess:
		switch where {
		case WhereVM, WhereWSL:
			return could + inVM
		case WhereAccount:
			return could + "act as your own account on this machine (rootless Podman) — your account, not root."
		case WhereApple:
			return could + "get root in the booth's own VM; it cannot reach this machine that way."
		}
		switch kind {
		case KindDind:
			return could + "drive the privileged Docker daemon and run commands on the host as root."
		case KindEngineSocket:
			return could + "use the host's container engine to run commands on the host as root."
		default:
			return could + "reach the host's kernel, devices, or processes, and from there get root on the host."
		}
	case KindHostMounts:
		switch where {
		case WhereAccount:
			return could + "change the files there that your account can write."
		case WhereVM, WhereWSL, WhereApple:
			return could + "change the files there, as you."
		}
		return could + "change the host files there, which the host system may rely on."
	case KindHomeMounts:
		return could + "change files your account runs or loads (shell startup files, ~/.ssh, app config), and so run code as you."
	case KindHostNetwork:
		switch where {
		case WhereVM, WhereWSL, WhereApple:
			return could + "reach every service on the network it shares — the engine's VM, and on engines that forward host networking, this machine's localhost-only services too."
		}
		return could + "reach every service listening on the host, including ones bound only to localhost."
	}
	return could + "reach the host."
}

// Link is the documentation link for a kind.
func Link(kind Kind) string {
	return DocURL + "#" + string(kind)
}

// Format returns the warning for reasons, without any closing line (the caller adds the prompt or
// the note that fits). It is "" when there are no reasons.
func Format(reasons []Reason) string {
	if len(reasons) == 0 {
		return ""
	}
	var str strings.Builder
	str.WriteString("\n⚠️  This booth has settings that let code inside it reach the host:\n")
	for _, reason := range reasons {
		fmt.Fprintf(&str, "\n  - %s\n", reason.What)
		fmt.Fprintf(&str, "      %s\n", Impact(reason.Kind, reason.Where))
		fmt.Fprintf(&str, "      %s\n", Link(reason.Kind))
	}
	str.WriteString("\n" +
		"  This only matters if the booth runs code you do not trust.\n" +
		"  If you trust what it runs, go ahead.\n")
	return str.String()
}

// EncodeLabel is the label value that records reasons; "" when there are none.
func EncodeLabel(reasons []Reason) string {
	if len(reasons) == 0 {
		return ""
	}
	data, err := json.Marshal(reasons)
	if err != nil {
		return ""
	}
	return string(data)
}

// DecodeLabel reads the reasons back from a label value. A missing or unreadable label is no
// reasons: the warning is a courtesy on restart, and consent was already given at creation.
func DecodeLabel(value string) []Reason {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	var reasons []Reason
	if err := json.Unmarshal([]byte(value), &reasons); err != nil {
		return nil
	}
	return reasons
}

// StartNote is the closing line for a booth that is started again with the settings it was created
// with: nothing to ask, because consent was given when it was created.
const StartNote = "  This booth was created with these settings.\n"
