// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"strings"
	"testing"
)

func TestKataEgressForwards(t *testing.T) {
	got := strings.Join(kataEgressForwards([]string{"8080:8080", "127.0.0.1:5353:53/udp", "8080:8080"}), " ")
	want := "tcp/10000 tcp/8080 udp/53"
	if got != want {
		t.Errorf("forwards = %q, want %q", got, want)
	}
}

func TestKataEgressGatewayArgs(t *testing.T) {
	line := strings.Join(kataEgressGatewayArgs("b-1-egress-netns", "b-1-egress-net", "b", "b", "127.0.0.1:1:10000", []string{"8080:8080"}), " ")
	for _, want := range []string{
		"--network b-1-egress-net",
		"--sysctl net.ipv4.ip_forward=1",
		"-p 127.0.0.1:1:10000",
		"-p 8080:8080",
		"-e CB_BOOTH=b",
		"-e CB_FORWARD=tcp/10000 tcp/8080",
		// Nothing but the DNATed connections is forwarded.
		"iptables -P FORWARD DROP",
		"--ctstate DNAT -j ACCEPT",
	} {
		if !strings.Contains(line, want) {
			t.Errorf("missing %q:\n%s", want, line)
		}
	}
}

func TestKataEgressBoothArgs(t *testing.T) {
	line := joinArgs(kataEgressBoothArgs("b-1-egress-int", "b-1-egress-netns", "172.20.0.2"))
	for _, want := range []string{
		"--network b-1-egress-int",
		"--add-host b-1-egress-netns:172.20.0.2",
		"-e BOOTH_DIND_HOST=b-1-egress-netns",
		"-e BOOTH_DIND_FORWARD=15001",
	} {
		if !strings.Contains(line, want) {
			t.Errorf("missing %q:\n%s", want, line)
		}
	}
	if strings.Contains(line, "container:") {
		t.Errorf("a Kata booth cannot share a namespace:\n%s", line)
	}
}
