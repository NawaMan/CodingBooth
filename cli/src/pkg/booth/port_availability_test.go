// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/stretchr/testify/assert"
)

func hostPortsCtx(port string, portNumber int, generated bool, runArgs []string) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs:    ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:     ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:       ilist.NewAppendableList[ilist.List[string]](),
		Cmds:          ilist.NewAppendableList[ilist.List[string]](),
		PortNumber:    portNumber,
		PortGenerated: generated,
	}
	builder.Config.Port = port
	if len(runArgs) > 0 {
		builder.RunArgs.Append(ilist.NewListFromSlice(runArgs))
	}
	return builder.Build()
}

// takenOnly reports every port in taken as busy, and the rest as free.
func takenOnly(taken ...int) func(int) bool {
	return func(port int) bool {
		for _, t := range taken {
			if t == port {
				return false
			}
		}
		return true
	}
}

func busyPorts(busy []HostPortBusy) []int {
	ports := []int{}
	for _, b := range busy {
		ports = append(ports, b.Port)
	}
	return ports
}

func TestBusyHostPorts_FixedBoothPortInUse(t *testing.T) {
	busy := busyHostPorts(hostPortsCtx("10000", 10000, false, nil), takenOnly(10000))
	assert.Equal(t, []HostPortBusy{{Port: 10000, Source: "--port 10000"}}, busy)
}

func TestBusyHostPorts_GeneratedBoothPortIsNotProbed(t *testing.T) {
	// This process holds the NEXT pick itself, so it always reads as taken.
	busy := busyHostPorts(hostPortsCtx("NEXT", 12000, true, nil), takenOnly(12000))
	assert.Empty(t, busy)
}

func TestBusyHostPorts_FixedExposeInUse(t *testing.T) {
	ctx := hostPortsCtx("NEXT", 12000, true, []string{"-p", "4566:4566", "--publish", "18610:18610"})
	busy := busyHostPorts(ctx, takenOnly(4566))
	assert.Equal(t, []HostPortBusy{{Port: 4566, Raw: "4566:4566", Source: "run-args"}}, busy)
}

func TestBusyHostPorts_AllFree(t *testing.T) {
	ctx := hostPortsCtx("10000", 10000, false, []string{"-p", "4566:4566"})
	assert.Empty(t, busyHostPorts(ctx, takenOnly()))
}

func TestBusyHostPorts_Skips(t *testing.T) {
	ctx := hostPortsCtx("NEXT", 12000, true, []string{
		"-p", "80:80", // privileged: a failed bind does not mean taken
		"-p", "5353:5353/udp", // UDP: a TCP probe says nothing
		"-p", "192.168.1.5:8080:80", // another address than the probe's
		"-p", "12000:9000", // the booth port, already refused as a clash elsewhere
	})
	assert.Empty(t, busyHostPorts(ctx, takenOnly(80, 5353, 8080, 12000)))
}

func TestBusyHostPorts_LoopbackAndRepeatsProbedOnce(t *testing.T) {
	ctx := hostPortsCtx("8080", 8080, false, []string{"-p", "127.0.0.1:8080:80", "-p", "0.0.0.0:9090:90", "-p", "9090:90"})
	assert.Equal(t, []int{8080, 9090}, busyPorts(busyHostPorts(ctx, takenOnly(8080, 9090))))
}
