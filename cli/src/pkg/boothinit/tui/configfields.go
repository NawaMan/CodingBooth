// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

// fieldKind identifies the type of a config field.
type fieldKind int

const (
	fieldKindCycle  fieldKind = iota // cycle through options (e.g., variant)
	fieldKindString                  // editable text (e.g., port, name)
	fieldKindBool                    // toggle on/off
	fieldKindList                    // dynamic list of strings (e.g., expose, env, mount)
)

// configFieldDef defines a single config field.
type configFieldDef struct {
	Key     string    // unique key for storage
	Label   string    // display label
	Group   string    // group header (rendered when it changes)
	Kind    fieldKind // field type
	Options []string  // for cycle fields: list of options
	Detail  string    // help text for right panel
}

// allConfigFields defines all config fields in display order.
var allConfigFields = []configFieldDef{
	// --- Booth ---
	{Key: "booth-version", Label: "Booth Version", Group: "Booth", Kind: fieldKindString,
		Detail: "Version of the CodingBooth CLI tool.\nChange this to upgrade or downgrade the booth binary.\n\nThe new version will be downloaded on the next run.\nUse 'latest' for the most recent release."},

	// --- General ---
	{Key: "variant", Label: "Variant", Group: "General", Kind: fieldKindCycle,
		Options: []string{"", "base", "notebook", "codeserver", "desktop-xfce", "desktop-kde", "desktop-lxqt", "desktop-wayland", "terminal"},
		Detail:  "The booth variant determines the UI mode.\n\n(default) = auto-detect from config\nbase = minimal terminal\nnotebook = Jupyter Lab\ncodeserver = VS Code in browser\ndesktop-xfce = XFCE desktop\ndesktop-kde = KDE Plasma desktop\ndesktop-lxqt = LXQt desktop\ndesktop-wayland = labwc (Wayland) desktop\nterminal = direct bash session"},
	{Key: "port", Label: "Port", Group: "General", Kind: fieldKindString,
		Detail: "Host port for accessing the booth UI.\n\nSpecial values:\n  NEXT   = next available port\n  RANDOM = random available port"},
	{Key: "name", Label: "Name", Group: "General", Kind: fieldKindString,
		Detail: "Container name. If empty, inferred from the code directory name."},
	{Key: "version", Label: "Version", Group: "General", Kind: fieldKindString,
		Detail: "Prebuilt image version tag. If empty, uses 'latest'."},

	// --- Container ---
	{Key: "dind", Label: "Docker-in-Docker", Group: "Container", Kind: fieldKindBool,
		Detail: "Enable a Docker-in-Docker sidecar.\nRequires --privileged flag. Use only when needed."},
	{Key: "keep-alive", Label: "Keep Alive", Group: "Container", Kind: fieldKindBool,
		Detail: "Preserve container after exit.\nResume later with: booth start <name>"},
	{Key: "daemon", Label: "Daemon", Group: "Container", Kind: fieldKindBool,
		Detail: "Run the booth in the background (detached mode)."},
	{Key: "sudo", Label: "Sudo", Group: "Container", Kind: fieldKindCycle,
		Options: []string{"", "true", "false"},
		Detail:  "Enable passwordless sudo for the coder user.\n\n(default) = leave to booth (enabled)\ntrue = explicitly enable\nfalse = explicitly disable"},
	{Key: "writable-booth", Label: "Writable .booth/", Group: "Container", Kind: fieldKindBool,
		Detail: "Allow writing to .booth/ inside the container.\nBy default, .booth/ is mounted read-only."},
	{Key: "public", Label: "Public", Group: "Container", Kind: fieldKindBool,
		Detail: "Bind to all interfaces with password authentication.\nUseful for accessing the booth from other machines."},
	{Key: "egress", Label: "Egress", Group: "Container", Kind: fieldKindBool,
		Detail: "Restrict outbound network to allowlisted domains.\nUses Envoy proxy + iptables."},

	// --- Build ---
	{Key: "silence-build", Label: "Silence Build", Group: "Build", Kind: fieldKindBool,
		Detail: "Hide build progress output.\nShow output only on failure."},
	{Key: "pull", Label: "Always Pull", Group: "Build", Kind: fieldKindBool,
		Detail: "Always pull the image, even if it exists locally."},
	{Key: "strict", Label: "Strict", Group: "Build", Kind: fieldKindBool,
		Detail: "Treat Boothfile warnings as errors."},

	// --- Advanced ---
	{Key: "image", Label: "Image", Group: "Advanced", Kind: fieldKindString,
		Detail: "Use an existing local or remote image.\nExample: repo/name:tag\n\nIf set, skips building from Dockerfile/Boothfile."},
	{Key: "startup", Label: "Startup Command", Group: "Advanced", Kind: fieldKindString,
		Detail: "Custom startup command to run inside the container."},
	{Key: "env-file", Label: "Env File", Group: "Advanced", Kind: fieldKindString,
		Detail: "Provide an --env-file to docker run.\nUse 'none' to disable the default .booth/.env."},
	{Key: "tls-cert", Label: "TLS Cert", Group: "Advanced", Kind: fieldKindString,
		Detail: "TLS certificate file for HTTPS.\nUsed with --public for secure remote access."},
	{Key: "tls-key", Label: "TLS Key", Group: "Advanced", Kind: fieldKindString,
		Detail: "TLS private key file for HTTPS.\nUsed with --public for secure remote access."},

	// --- Network & Volumes ---
	{Key: "expose", Label: "Expose", Group: "Network & Volumes", Kind: fieldKindList,
		Detail: "Expose extra ports from the container.\nEach entry adds a -p mapping.\n\nExamples:\n  3000                    (same port on host)\n  3000:3000               (host:container)\n  +8080:8080              (host = booth port + 8080)\n  ${APP_PORT:-3000}:3000  (host from env at start)\n\nOnly the host side may use ${NAME} / ${NAME:-digits};\nthe container port stays a number."},
	{Key: "env", Label: "Env", Group: "Network & Volumes", Kind: fieldKindList,
		Detail: "Set environment variables in the container.\nEach entry adds a -e flag.\n\nExamples:\n  NODE_ENV=development\n  PYTHONDONTWRITEBYTECODE=1\n  CARGO_NET_GIT_FETCH_WITH_CLI=true\n  GEOMETRY=1920x1080\n    (desktop resolution for XFCE/KDE)"},
	{Key: "mount", Label: "Mount", Group: "Network & Volumes", Kind: fieldKindList,
		Detail: "Bind mount files or directories.\nEach entry adds a -v flag.\n\nExamples:\n  ~/.m2:/home/coder/.m2\n    (Maven cache)\n  ~/.cargo/registry:/home/coder/.cargo/registry\n    (Cargo cache)\n  ~/.aws:/etc/cb-home-seed/.aws:ro\n    (AWS credentials, read-only)\n  ~/.npmrc:/etc/cb-home-seed/.npmrc:ro\n    (npm config)"},

	// --- Debug ---
	{Key: "verbose", Label: "Verbose", Group: "Debug", Kind: fieldKindBool,
		Detail: "Print extra debugging information during booth startup."},
	{Key: "dryrun", Label: "Dry Run", Group: "Debug", Kind: fieldKindBool,
		Detail: "Print docker commands without executing them."},
	{Key: "debug", Label: "Debug", Group: "Debug", Kind: fieldKindBool,
		Detail: "Print resolved selection and compiled output as JSON."},
}

// defaultBoolValues returns the default values for boolean fields.
func defaultBoolValues() map[string]bool {
	return map[string]bool{}
}
