// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"net"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

func hostAccessBuilder() *appctx.AppContextBuilder {
	builder := &appctx.AppContextBuilder{
		CbVersion:  "v-test",
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Name = "demo"
	builder.Config.ProjectName = "demo"
	builder.Config.Variant = "base"
	builder.Config.Code = nillable.NewNillableString(".")
	builder.Config.HostUID = "1000"
	builder.Config.HostGID = "1000"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	return builder
}

func TestPrepareCommonArgs_AddsHostGatewayAlias(t *testing.T) {
	ctx := PrepareCommonArgs(hostAccessBuilder().Build())

	assertContainsArgPair(t, ctx.CommonArgs(), "--add-host", "host.docker.internal:host-gateway")
	assertContainsArgPair(t, ctx.CommonArgs(), "-e", "BOOTH_HOST_NAME=host.docker.internal")
}

// Docker rejects --add-host on a container that borrows another container's
// network namespace ("conflicting options: custom host-to-IP mapping and the
// network mode"), which is how a booth runs under --dind and --egress. The
// alias is set on the sidecar that owns the namespace instead, so the booth
// itself must not ask for it — otherwise the run fails outright.
func TestPrepareCommonArgs_NoHostGatewayAliasWithSharedNetns(t *testing.T) {
	for _, tt := range []struct {
		name  string
		apply func(builder *appctx.AppContextBuilder)
	}{
		{"Dind", func(builder *appctx.AppContextBuilder) { builder.Config.Dind = true }},
		{"Egress", func(builder *appctx.AppContextBuilder) { builder.Config.Egress = true }},
	} {
		t.Run(tt.name, func(t *testing.T) {
			builder := hostAccessBuilder()
			tt.apply(builder)

			ctx := PrepareCommonArgs(builder.Build())

			ctx.CommonArgs().Range(func(_ int, group ilist.List[string]) bool {
				if group.Length() > 0 && group.At(0) == "--add-host" {
					t.Fatalf("booth container must not carry --add-host when it shares a netns")
				}
				return true
			})
			// The name is still advertised: the sidecar provides the alias.
			assertContainsArgPair(t, ctx.CommonArgs(), "-e", "BOOTH_HOST_NAME=host.docker.internal")
		})
	}
}

func TestGetHostIP_IsAUsableAddressOrEmpty(t *testing.T) {
	// The value depends on the machine's networking, so assert the contract
	// rather than an address: either a dialable IPv4 for the host, or nothing.
	got := getHostIP()
	if got == "" {
		t.Log("no non-loopback IPv4 on this machine; BOOTH_HOST_IP is left unset")
		return
	}

	ip := net.ParseIP(got)
	if ip == nil {
		t.Fatalf("getHostIP() = %q, which is not an IP address", got)
	}
	if !isUsableHostIP(ip) {
		t.Fatalf("getHostIP() = %q, which is not a usable host address", got)
	}
}

func TestIsUsableHostIP_RejectsWhatCannotNameTheHost(t *testing.T) {
	tests := []struct {
		name string
		ip   string
		want bool
	}{
		{"LAN", "192.168.1.42", true},
		{"Routable", "203.0.113.7", true},
		{"DockerBridge", "172.17.0.1", true},
		{"Loopback", "127.0.0.1", false},
		{"LinkLocal", "169.254.13.7", false},
		{"IPv6", "fd00::1", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isUsableHostIP(net.ParseIP(tt.ip)); got != tt.want {
				t.Fatalf("isUsableHostIP(%s) = %v, want %v", tt.ip, got, tt.want)
			}
		})
	}

	if isUsableHostIP(nil) {
		t.Fatal("isUsableHostIP(nil) must be false")
	}
}
