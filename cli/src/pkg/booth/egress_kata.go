// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// --egress with --booth-isolation kata. An ordinary egress booth shares the
// netns sidecar's network namespace (--network container:<sidecar>); a Kata
// booth is a VM with a kernel of its own and cannot. Instead:
//
//   - the booth stands alone on an --internal network: no gateway, no route
//     out, so nothing leaves it except through the proxy — there is no firewall
//     rule inside the booth to undo;
//   - the netns sidecar (the gateway) is on that network and on the ordinary
//     egress network. Envoy runs in its namespace as usual, and the booth
//     reaches it as <gateway>:15001 — forwarded to the booth's own
//     127.0.0.1:15001 by booth--dind-forward, so HTTP_PROXY is unchanged;
//   - the gateway publishes the booth's ports (an internal network publishes
//     none) and DNATs them on to the booth. It forwards nothing else: FORWARD
//     drops all but those DNATed connections and their replies, so the booth
//     cannot route out through it either.

func getEgressInternalNet(ctx appctx.AppContext) string {
	return ctx.Name() + "-" + strconv.Itoa(ctx.PortNumber()) + "-egress-int"
}

// kataEgressForwards lists, as proto/port, the container ports the gateway
// DNATs on to the booth: the booth's own port and every port run-args publish
// (in the forms ParsePortMapping reads).
func kataEgressForwards(extraPorts []string) []string {
	forwards := []string{"tcp/10000"}
	seen := map[string]bool{"tcp/10000": true}
	for _, mapping := range extraPorts {
		m, ok := ParsePortMapping(mapping)
		if !ok {
			continue
		}
		port, _, _ := strings.Cut(m.Container, "/")
		forward := m.Proto + "/" + port
		if port != "" && !seen[forward] {
			seen[forward] = true
			forwards = append(forwards, forward)
		}
	}
	return forwards
}

// kataEgressGatewayScript runs in the gateway: it sets the forwarding policy,
// then keeps a DNAT chain pointed at the booth's address (Docker's DNS gives it
// once the booth is up, and again if a restart moves it).
const kataEgressGatewayScript = `set -u
iptables -P FORWARD DROP
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate DNAT -j ACCEPT
iptables -t nat -N CB_BOOTH
iptables -t nat -A PREROUTING -j CB_BOOTH
iptables -t nat -A POSTROUTING -m conntrack --ctstate DNAT -j MASQUERADE
current=""
while :; do
  set -- $(getent hosts "$CB_BOOTH" 2>/dev/null) ""
  if [ -n "$1" ] && [ "$1" != "$current" ]; then
    iptables -t nat -F CB_BOOTH
    for spec in $CB_FORWARD; do
      iptables -t nat -A CB_BOOTH -p "${spec%%/*}" --dport "${spec#*/}" -j DNAT --to-destination "$1"
    done
    current="$1"
  fi
  sleep 2
done
`

// kataEgressGatewayArgs is the gateway's `docker run`: on the ordinary egress
// network, publishing the booth's ports, and forwarding them on.
func kataEgressGatewayArgs(ownerName, netName, parentName, boothName, portMapping string, extraPorts []string) []string {
	args := []string{
		"run", "-d", "--rm",
		"--cap-add=NET_ADMIN",
		"--sysctl", "net.ipv4.ip_forward=1",
		"--name", ownerName,
		"--network", netName,
		"-p", portMapping,
		"--label", "cb.managed=true",
		"--label", "cb.role=sidecar",
		"--label", "cb.parent=" + parentName,
		"-e", "CB_BOOTH=" + boothName,
		"-e", "CB_FORWARD=" + strings.Join(kataEgressForwards(extraPorts), " "),
	}
	for _, port := range extraPorts {
		args = append(args, "-p", port)
	}
	return append(args, "--entrypoint", "sh", "docker:dind", "-c", kataEgressGatewayScript)
}

// startKataEgressGateway starts the gateway and joins it to the booth's
// internal network.
func startKataEgressGateway(ctx appctx.AppContext, ownerName, netName, intNet string, extraPorts []string) error {
	flags := docker.DockerFlags{Dryrun: ctx.Dryrun(), Verbose: ctx.Verbose(), Silent: true, Engine: ctx.Engine()}
	output, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("--filter", fmt.Sprintf("name=^/%s$", ownerName), "--format", "{{.Names}}"),
	))
	if err == nil && strings.TrimSpace(output) == ownerName {
		return nil
	}
	releasePortReservation()
	portMapping := formatPortMapping(ctx.Public(), ctx.PortNumber(), 10000)
	args := kataEgressGatewayArgs(ownerName, netName, ctx.Name(), ctx.Name(), portMapping, extraPorts)
	flags.Silent = false
	if err := docker.Docker(flags, args[0], ilist.NewList(ilist.NewListFromSlice(args[1:]))); err != nil {
		return err
	}
	return docker.Docker(flags, "network", ilist.NewList(ilist.NewList("connect", intNet, ownerName)))
}

// createInternalNetwork creates an --internal network (no route out) unless it
// is there already; it reports whether it created one.
func createInternalNetwork(ctx appctx.AppContext, name string) (bool, error) {
	flags := docker.DockerFlags{Dryrun: ctx.Dryrun(), Verbose: ctx.Verbose(), Silent: true, Engine: ctx.Engine()}
	if output, err := docker.DockerOutput(flags, "network", ilist.NewList(ilist.NewList("inspect", name))); err == nil && strings.TrimSpace(output) != "" {
		return false, nil
	}
	flags.Silent = false
	if err := docker.Docker(flags, "network", ilist.NewList(ilist.NewList("create", "--internal", name))); err != nil {
		return false, err
	}
	return true, nil
}

// kataEgressBoothArgs puts the booth on the internal network, gives it the
// gateway's name, and has booth--dind-forward carry its 127.0.0.1:15001 to the
// proxy (56-cb-dind-forward--startup.sh; the gateway has no Docker daemon, so
// the forwarder's port polling finds nothing more).
func kataEgressBoothArgs(intNet, ownerName, ownerAddress string) [][]string {
	return [][]string{
		{"--network", intNet},
		{"--add-host", ownerName + ":" + ownerAddress},
		{"-e", "BOOTH_DIND_HOST=" + ownerName},
		{"-e", "BOOTH_DIND_FORWARD=" + strconv.Itoa(egressProxyPort)},
	}
}
