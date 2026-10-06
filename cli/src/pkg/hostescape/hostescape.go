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

// Reason is one setting that lets code in the booth reach the host.
type Reason struct {
	Kind Kind   `json:"kind"`
	What string `json:"what"` // the setting itself, e.g. "--privileged"
}

// LabelKey is the container label that records the reasons a booth was created with.
const LabelKey = "cb.security-warning"

// DocURL is the page the warning links to; each kind has an anchor there.
const DocURL = "https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md"

// Impact says what untrusted code could do with a setting of this kind.
func Impact(kind Kind) string {
	switch kind {
	case KindDind:
		return "Untrusted code in the booth could drive the privileged Docker daemon and run commands on the host as root."
	case KindEngineSocket:
		return "Untrusted code in the booth could use the host's container engine to run commands on the host as root."
	case KindKernelAccess:
		return "Untrusted code in the booth could reach the host's kernel, devices, or processes, and from there get root on the host."
	case KindHostMounts:
		return "Untrusted code in the booth could change the host files there, which the host system may rely on."
	case KindHomeMounts:
		return "Untrusted code in the booth could change files your host account runs or loads (shell startup files, ~/.ssh, app config), and so run code as you."
	case KindHostNetwork:
		return "Untrusted code in the booth could reach every service listening on the host, including ones bound only to localhost."
	}
	return "Untrusted code in the booth could reach the host."
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
		fmt.Fprintf(&str, "      %s\n", Impact(reason.Kind))
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
