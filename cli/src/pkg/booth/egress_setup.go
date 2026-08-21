// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

const (
	egressProxyImage      = "envoyproxy/envoy:v1.31-latest"
	egressProxyUID        = 101
	egressProxyPort       = 15001
	egressProxyConfigPath = "/etc/envoy/envoy.yaml"
)

// SetupEgress sets up egress sidecars and firewall policy.
//
// Behavior:
// - If --egress is off: no-op.
// - If --egress + --dind: reuse DinD sidecar network namespace.
// - If --egress only: create a dedicated netns-owner sidecar and share its namespace.
func SetupEgress(ctx appctx.AppContext) appctx.AppContext {
	if !ctx.Egress() {
		return ctx
	}

	if mode := strings.TrimSpace(strings.ToLower(ctx.EgressMode())); mode != "" && mode != "envoy" {
		fmt.Fprintf(os.Stderr, "❌ egress mode %q is not implemented yet.\n", mode)
		os.Exit(1)
	}

	builder := ctx.ToBuilder()
	netnsOwner := getEgressNetnsOwnerName(ctx)

	// If not using DinD, create dedicated network + owner sidecar.
	if !ctx.Dind() {
		netName := getEgressNet(ctx)
		createdNet := createDindNetwork(ctx, netName)
		builder.CreatedEgressNet = createdNet

		extraPorts := extractPortFlags(ctx.RunArgs())
		if err := startEgressNetnsOwner(ctx, netnsOwner, netName, ctx.PortNumber(), extraPorts); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to start egress netns sidecar: %v\n", err)
			os.Exit(1)
		}

		builder.RunArgs = stripNetworkAndPortFlags(ctx.RunArgs())
		builder.CommonArgs.Append(ilist.NewList[string]("--network", fmt.Sprintf("container:%s", netnsOwner)))
	}

	ctx = builder.Build()

	// Resolve and materialize proxy config.
	configPath, err := resolveEgressProxyConfig(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "❌ Failed to prepare egress proxy config: %v\n", err)
		os.Exit(1)
	}

	// Start Envoy sidecar in the shared namespace.
	proxyName := getEgressProxyName(ctx)
	if err := startEgressProxy(ctx, proxyName, netnsOwner, configPath); err != nil {
		fmt.Fprintf(os.Stderr, "❌ Failed to start egress proxy sidecar: %v\n", err)
		os.Exit(1)
	}

	// Wait for proxy and then enforce firewall.
	if err := waitForEgressProxyReady(ctx, netnsOwner); err != nil {
		fmt.Fprintf(os.Stderr, "❌ Egress proxy did not become ready: %v\n", err)
		os.Exit(1)
	}
	if err := applyEgressFirewall(ctx, netnsOwner); err != nil {
		fmt.Fprintf(os.Stderr, "❌ Failed to apply egress firewall rules: %v\n", err)
		os.Exit(1)
	}

	// Set proxy env for the workspace container.
	builder = ctx.ToBuilder()
	proxyURL := fmt.Sprintf("http://127.0.0.1:%d", egressProxyPort)
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "http_proxy="+proxyURL))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "HTTP_PROXY="+proxyURL))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "https_proxy="+proxyURL))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "HTTPS_PROXY="+proxyURL))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "no_proxy=127.0.0.1,localhost"))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "NO_PROXY=127.0.0.1,localhost"))
	return builder.Build()
}

func getEgressNet(ctx appctx.AppContext) string {
	return ctx.Name() + "-" + fmt.Sprintf("%d", ctx.PortNumber()) + "-egress-net"
}

func getEgressNetnsName(ctx appctx.AppContext) string {
	return ctx.Name() + "-" + fmt.Sprintf("%d", ctx.PortNumber()) + "-egress-netns"
}

func getEgressProxyName(ctx appctx.AppContext) string {
	return ctx.Name() + "-" + fmt.Sprintf("%d", ctx.PortNumber()) + "-egress-proxy"
}

func getEgressNetnsOwnerName(ctx appctx.AppContext) string {
	if ctx.Dind() {
		return getDindName(ctx)
	}
	return getEgressNetnsName(ctx)
}

func startEgressNetnsOwner(ctx appctx.AppContext, ownerName, netName string, hostPort int, extraPorts []string) error {
	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  true,
	}

	output, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("--filter", fmt.Sprintf("name=^/%s$", ownerName), "--format", "{{.Names}}"),
	))
	if err == nil && strings.TrimSpace(output) == ownerName {
		return nil
	}

	parentName := ctx.Name()
	// This sidecar owns the network namespace, so it publishes the booth port.
	// Release the reservation or its -p mapping cannot bind.
	releasePortReservation()
	portMapping := formatPortMapping(ctx.Public(), hostPort, 10000)
	args := []string{
		"run", "-d", "--rm",
		"--cap-add=NET_ADMIN",
		"--name", ownerName,
		"--network", netName,
		// The booth shares this namespace, so the host alias must live here —
		// docker refuses --add-host on a container that borrows a netns.
		"--add-host", hostGatewayMapping,
		"-p", portMapping,
		"--label", "cb.managed=true",
		"--label", "cb.role=sidecar",
		"--label", "cb.parent=" + parentName,
	}
	for _, port := range extraPorts {
		args = append(args, "-p", port)
	}
	args = append(args, "docker:dind", "sleep", "infinity")

	flags.Silent = false
	return docker.Docker(flags, args[0], ilist.NewList(ilist.NewListFromSlice(args[1:])))
}

func resolveEgressProxyConfig(ctx appctx.AppContext) (string, error) {
	policyFile := strings.TrimSpace(ctx.EgressPolicyFile())
	if policyFile != "" {
		return resolvePolicyPath(ctx, policyFile), nil
	}
	return renderEgressEnvoyConfigFromAllowlist(ctx)
}

func resolvePolicyPath(ctx appctx.AppContext, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(ctx.Code(), path)
}

func renderEgressEnvoyConfigFromAllowlist(ctx appctx.AppContext) (string, error) {
	allowlistPath := strings.TrimSpace(ctx.EgressAllowlistFile())
	var patterns []string
	if allowlistPath != "" {
		content, err := os.ReadFile(resolvePolicyPath(ctx, allowlistPath))
		if err != nil {
			return "", fmt.Errorf("failed to read allowlist file: %w", err)
		}
		patterns = parseAllowlistPatterns(mergeAllowlistContent(string(content), ctx.EgressAllowlist()))
	} else if len(ctx.EgressAllowlist()) > 0 {
		patterns = parseAllowlistPatterns(mergeAllowlistContent("", ctx.EgressAllowlist()))
	}

	outDir := filepath.Join(ctx.Code(), ".booth", "tools", "egress")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return "", fmt.Errorf("failed to create egress output dir: %w", err)
	}

	outPath := filepath.Join(outDir, "envoy.generated.yaml")
	if err := os.WriteFile(outPath, []byte(buildEnvoyConfigFromPatterns(patterns)), 0o644); err != nil {
		return "", fmt.Errorf("failed to write generated envoy config: %w", err)
	}
	if ctx.Verbose() {
		fmt.Printf("EGRESS_ENVOY_CONFIG: %s\n", outPath)
		fmt.Println("EGRESS_ENVOY_CONFIG_CONTENT:")
		fmt.Println(buildEnvoyConfigFromPatterns(patterns))
	}
	return outPath, nil
}

func parseAllowlistPatterns(content string) []string {
	lines := strings.Split(content, "\n")
	patterns := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		domain := line
		if idx := strings.Index(domain, "#"); idx >= 0 {
			domain = strings.TrimSpace(domain[:idx])
		}
		if domain == "" {
			continue
		}
		escaped := regexp.QuoteMeta(domain)
		patterns = append(patterns, fmt.Sprintf("(^|.*\\.)%s(:[0-9]+)?$", escaped))
	}
	return patterns
}

func parseAllowlistEntries(content string) []string {
	lines := strings.Split(content, "\n")
	entries := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		domain := line
		if idx := strings.Index(domain, "#"); idx >= 0 {
			domain = strings.TrimSpace(domain[:idx])
		}
		if domain == "" {
			continue
		}
		entries = append(entries, domain)
	}
	return entries
}

func mergeAllowlistContent(content string, extra []string) string {
	if len(extra) == 0 {
		return content
	}
	var builder strings.Builder
	builder.WriteString(content)
	if content != "" && !strings.HasSuffix(content, "\n") {
		builder.WriteString("\n")
	}
	for _, entry := range extra {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		builder.WriteString(entry)
		builder.WriteString("\n")
	}
	return builder.String()
}

func effectiveEgressAllowlist(ctx appctx.AppContext) (entries []string, note string) {
	allowlistPath := strings.TrimSpace(ctx.EgressAllowlistFile())
	content := ""
	if allowlistPath != "" {
		path := resolvePolicyPath(ctx, allowlistPath)
		b, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Sprintf("EGRESS_ALLOWLIST_ERROR: %v", err)
		}
		content = string(b)
	}
	if content == "" && len(ctx.EgressAllowlist()) == 0 {
		return nil, ""
	}
	merged := mergeAllowlistContent(content, ctx.EgressAllowlist())
	return parseAllowlistEntries(merged), ""
}

func buildEnvoyConfigFromPatterns(patterns []string) string {
	var policyBuilder strings.Builder
	for i, pattern := range patterns {
		fmt.Fprintf(&policyBuilder, "                  allow_%d:\n", i)
		policyBuilder.WriteString("                    permissions:\n")
		policyBuilder.WriteString("                    - header:\n")
		policyBuilder.WriteString("                        name: \":authority\"\n")
		policyBuilder.WriteString("                        string_match:\n")
		policyBuilder.WriteString("                          safe_regex:\n")
		policyBuilder.WriteString("                            google_re2: {}\n")
		fmt.Fprintf(&policyBuilder, "                            regex: %q\n", pattern)
		policyBuilder.WriteString("                    principals:\n")
		policyBuilder.WriteString("                    - any: true\n")
	}

	if policyBuilder.Len() == 0 {
		policyBuilder.WriteString("                  deny_all:\n")
		policyBuilder.WriteString("                    permissions:\n")
		policyBuilder.WriteString("                    - header:\n")
		policyBuilder.WriteString("                        name: \":authority\"\n")
		policyBuilder.WriteString("                        string_match:\n")
		policyBuilder.WriteString("                          exact: \"__deny_all__\"\n")
		policyBuilder.WriteString("                    principals:\n")
		policyBuilder.WriteString("                    - any: true\n")
	}

	return fmt.Sprintf(`static_resources:
  listeners:
  - name: egress_proxy
    address:
      socket_address:
        address: 0.0.0.0
        port_value: %d
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: egress_http
          codec_type: AUTO
          route_config:
            name: proxy_routes
            virtual_hosts:
            - name: forward_proxy
              domains: ["*"]
              routes:
              - match:
                  connect_matcher: {}
                route:
                  cluster: dynamic_forward_proxy_cluster
                  upgrade_configs:
                  - upgrade_type: CONNECT
                    connect_config: {}
              - match:
                  prefix: "/"
                redirect:
                  https_redirect: true
          http_filters:
          - name: envoy.filters.http.rbac
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC
              rules:
                action: ALLOW
                policies:
%s
          - name: envoy.filters.http.dynamic_forward_proxy
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.dynamic_forward_proxy.v3.FilterConfig
              dns_cache_config:
                name: dynamic_forward_proxy_cache_config
                dns_lookup_family: V4_ONLY
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          upgrade_configs:
          - upgrade_type: CONNECT

  clusters:
  - name: dynamic_forward_proxy_cluster
    connect_timeout: 5s
    lb_policy: CLUSTER_PROVIDED
    cluster_type:
      name: envoy.clusters.dynamic_forward_proxy
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.clusters.dynamic_forward_proxy.v3.ClusterConfig
        dns_cache_config:
          name: dynamic_forward_proxy_cache_config
          dns_lookup_family: V4_ONLY

admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901
`, egressProxyPort, policyBuilder.String())
}

func startEgressProxy(ctx appctx.AppContext, proxyName, netnsOwnerName, configPath string) error {
	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  true,
	}
	output, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("--filter", fmt.Sprintf("name=^/%s$", proxyName), "--format", "{{.Names}}"),
	))
	if err == nil && strings.TrimSpace(output) == proxyName {
		return nil
	}

	parentName := ctx.Name()
	args := []string{
		"run", "-d", "--rm",
		"--name", proxyName,
		"--network", fmt.Sprintf("container:%s", netnsOwnerName),
		"--label", "cb.managed=true",
		"--label", "cb.role=sidecar",
		"--label", "cb.parent=" + parentName,
		"-v", fmt.Sprintf("%s:%s:ro", configPath, egressProxyConfigPath),
		egressProxyImage,
		"-c", egressProxyConfigPath,
		"--log-level", "warning",
	}
	flags.Silent = false
	return docker.Docker(flags, args[0], ilist.NewList(ilist.NewListFromSlice(args[1:])))
}

func waitForEgressProxyReady(ctx appctx.AppContext, netnsOwnerName string) error {
	if ctx.Dryrun() {
		return nil
	}

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: ctx.Verbose(),
		Silent:  true,
	}
	checkCmd := fmt.Sprintf("nc -z 127.0.0.1 %d", egressProxyPort)
	for i := 0; i < 30; i++ {
		_, err := docker.DockerOutput(flags, "exec", ilist.NewList(
			ilist.NewList(netnsOwnerName, "sh", "-lc", checkCmd),
		))
		if err == nil {
			return nil
		}
		time.Sleep(250 * time.Millisecond)
	}
	return fmt.Errorf("proxy port %d did not open in time", egressProxyPort)
}

func applyEgressFirewall(ctx appctx.AppContext, netnsOwnerName string) error {
	if strings.ToLower(strings.TrimSpace(ctx.EgressEnforcement())) != "iptables" {
		return nil
	}

	cmd := fmt.Sprintf(`
set -eu
iptables -F OUTPUT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp -d 127.0.0.1 --dport %d -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner %d -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner %d -p tcp --dport 443 -j ACCEPT
iptables -P OUTPUT DROP
`, egressProxyPort, egressProxyUID, egressProxyUID)

	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  true,
	}
	return docker.Docker(flags, "exec", ilist.NewList(
		ilist.NewList(netnsOwnerName, "sh", "-lc", cmd),
	))
}

func cleanupEgressResources(ctx appctx.AppContext, flags *docker.DockerFlags) {
	if !ctx.Egress() {
		return
	}

	_ = docker.Docker(*flags, "stop", ilist.NewList(ilist.NewList(getEgressProxyName(ctx))))

	if ctx.Dind() {
		return
	}

	_ = docker.Docker(*flags, "stop", ilist.NewList(ilist.NewList(getEgressNetnsName(ctx))))
	if ctx.CreatedEgressNet() {
		_ = docker.Docker(*flags, "network", ilist.NewList(ilist.NewList("rm", getEgressNet(ctx))))
	}
}
