// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"sort"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// fieldKind identifies the type of a config field.
type fieldKind int

const (
	fieldKindCycle  fieldKind = iota // cycle through options (e.g., variant)
	fieldKindString                  // editable text (e.g., port, name)
	fieldKindBool                    // toggle on/off
	fieldKindList                    // dynamic list of strings (e.g., expose, env, mount)
	fieldKindInt                     // editable text restricted to digits (e.g., idle-time)
)

// configFieldDef defines a single config field as the renderer sees it.
//
// Kind is not written by hand — it is resolved from the config schema in
// buildConfigFields, so a field can never disagree with the TOML shape the key
// actually decodes from. Writing `idle-time = "30"` against an int field
// produces a config.toml booth refuses to load at all.
type configFieldDef struct {
	Key     string    // config.toml key, or a TUI-only key (see fieldDisplay.TUIOnly)
	Label   string    // display label
	Group   string    // group header (rendered when it changes)
	Kind    fieldKind // field type, resolved from the schema
	Options []string  // for cycle fields: list of options
	Detail  string    // help text for right panel

	// TUIOnly marks a field that is not a config.toml key. Saving must route it
	// somewhere other than a `--set`, and it is exempt from the schema join.
	TUIOnly bool
}

// fieldDisplay is the hand-written half of a field: how it looks and reads. The
// other half — what shape it is — comes from appctx.ConfigKeys().
//
// This split is the point. The field table used to carry its own idea of every
// key, which meant it could drift from AppConfig without anything noticing, and
// it did: for as long as it drifted, a TUI save deleted the settings it had
// fallen behind on. Now the only thing a new key needs here is a label and a
// sentence of help, and a key that disappears from AppConfig disappears from the
// TUI with it.
type fieldDisplay struct {
	Key     string
	Label   string
	Group   string
	Options []string // non-empty selects fieldKindCycle regardless of the schema shape
	Detail  string

	TUIOnly bool
	Kind    fieldKind // TUI-only fields only: nothing in the schema to resolve against
}

// fieldDisplays lists every rendered field in display order. Groups must stay
// contiguous — the renderer emits a header each time the group changes.
var fieldDisplays = []fieldDisplay{
	// --- Booth ---
	{Key: "booth-version", Label: "Booth Version", Group: "Booth", TUIOnly: true, Kind: fieldKindString,
		Detail: "Version of the CodingBooth CLI tool.\nChange this to upgrade or downgrade the booth binary.\n\nThe new version will be downloaded on the next run.\nUse 'latest' for the most recent release."},

	// --- General ---
	{Key: "variant", Label: "Variant", Group: "General",
		Options: []string{"", "base", "notebook", "codeserver", "desktop-xfce", "desktop-kde", "desktop-lxqt", "desktop-wayland", "terminal"},
		Detail:  "The booth variant determines the UI mode.\n\n(default) = auto-detect from config\nbase = minimal terminal\nnotebook = Jupyter Lab\ncodeserver = VS Code in browser\ndesktop-xfce = XFCE desktop\ndesktop-kde = KDE Plasma desktop\ndesktop-lxqt = LXQt desktop\ndesktop-wayland = labwc (Wayland) desktop\nterminal = direct bash session"},
	{Key: "port", Label: "Port", Group: "General",
		Detail: "Host port for accessing the booth UI.\n\nSpecial values:\n  NEXT   = next available port\n  RANDOM = random available port"},
	{Key: "offset-base", Label: "Offset Base", Group: "General",
		Detail: "What a +OFFSET host port counts from.\n\nEmpty = the booth port, so published ports follow it\nand two local booths never collide.\n\nSet a number where the booth owns the whole port\nrange and its port is fixed. 0 makes every +OFFSET\nan absolute port."},
	{Key: "name", Label: "Name", Group: "General",
		Detail: "Container name. If empty, inferred from the code directory name."},

	// Not the config.toml `version` key — see "Image Version" below.
	//
	// This is `booth config --version`, which picks the *template release* this
	// run compiles from. It has always been wired to that flag; it was labelled
	// "Version" and described as the image tag, which is a different setting
	// entirely and one this field has never written.
	{Key: "templates-version", Label: "Templates Version", Group: "General", TUIOnly: true, Kind: fieldKindString,
		Detail: "Compile from a specific CodingBooth release's templates.\n\nAffects this configure run only — it is recorded in the\n'Configured by' header, not as a config.toml setting.\nLeave empty to use the running binary's templates."},

	// --- Container ---
	{Key: "dind", Label: "Docker-in-Docker", Group: "Container",
		Detail: "Enable a Docker-in-Docker sidecar.\nRequires --privileged flag. Use only when needed."},
	{Key: "keep-alive", Label: "Keep Alive", Group: "Container",
		Detail: "Preserve container after exit.\nResume later with: booth start <name>"},
	{Key: "daemon", Label: "Daemon", Group: "Container",
		Detail: "Run the booth in the background (detached mode)."},
	{Key: "sudo", Label: "Sudo", Group: "Container",
		Options: []string{"", "true", "false"},
		Detail:  "Enable passwordless sudo for the coder user.\n\n(default) = leave to booth (enabled)\ntrue = explicitly enable\nfalse = explicitly disable"},
	{Key: "writable-booth", Label: "Writable .booth/", Group: "Container",
		Detail: "Allow writing to .booth/ inside the container.\nBy default, .booth/ is mounted read-only."},
	{Key: "persist-home", Label: "Persist Home", Group: "Container",
		Detail: "Keep /home/coder in a named volume across runs.\nWithout this, everything outside the mounted code\ndirectory is lost when the container goes away."},
	{Key: "project-name", Label: "Project Name", Group: "Container",
		Detail: "Name of the project, used in labels and derived names.\nIf empty, inferred from the code directory name."},
	{Key: "timezone", Label: "Timezone", Group: "Container",
		Detail: "Timezone inside the container (TZ database name).\n\nExample: Asia/Bangkok\n\nIf empty, the container's default is used."},
	{Key: "host-uid", Label: "Host UID", Group: "Container",
		Detail: "UID the coder user runs as, so files written to the\nmounted code directory belong to you on the host.\n\nIf empty, booth detects the invoking user's UID."},
	{Key: "host-gid", Label: "Host GID", Group: "Container",
		Detail: "GID the coder user runs as.\n\nIf empty, booth detects the invoking user's GID."},

	// --- Egress ---
	{Key: "egress", Label: "Egress", Group: "Egress",
		Detail: "Restrict outbound network to allowlisted domains.\nUses a filtering proxy plus firewall enforcement.\n\nThe rest of this group only applies when this is on."},
	{Key: "egress-mode", Label: "Egress Mode", Group: "Egress",
		Options: []string{"", "envoy", "squid", "tinyproxy", "none"},
		Detail:  "Which filtering proxy enforces the allowlist.\n\n(default) = envoy\nnone = no proxy (allowlist not enforced)"},
	{Key: "egress-enforcement", Label: "Egress Enforcement", Group: "Egress",
		Options: []string{"", "iptables", "nftables", "none"},
		Detail:  "How traffic is forced through the proxy.\n\n(default) = iptables\nnone = nothing stops a process bypassing the proxy"},
	{Key: "egress-allowlist", Label: "Egress Allowlist", Group: "Egress",
		Detail: "Domains reachable while egress is on.\nEach entry adds one host pattern.\n\nExamples:\n  github.com\n  .npmjs.org\n  pypi.org"},
	{Key: "egress-allowlist-file", Label: "Egress Allowlist File", Group: "Egress",
		Detail: "Path to a file of allowlist entries, one per line.\nMerged with the entries above."},
	{Key: "egress-policy-file", Label: "Egress Policy File", Group: "Egress",
		Detail: "Path to a full egress policy file, for rules the plain\nallowlist cannot express."},

	// --- Build ---
	{Key: "silence-build", Label: "Silence Build", Group: "Build",
		Detail: "Hide build progress output.\nShow output only on failure."},
	{Key: "pull", Label: "Always Pull", Group: "Build",
		Detail: "Always pull the image, even if it exists locally."},
	{Key: "strict", Label: "Strict", Group: "Build",
		Detail: "Treat Boothfile warnings as errors."},
	{Key: "emit-dockerfile", Label: "Emit Dockerfile", Group: "Build",
		Detail: "Write the Dockerfile compiled from the Boothfile to disk\ninstead of building it straight from memory.\n\nUseful for inspecting or hand-editing what booth builds."},
	{Key: "dockerfile", Label: "Dockerfile", Group: "Build",
		Detail: "Build from this Dockerfile instead of the Boothfile.\n\nPath relative to the code directory."},
	{Key: "boothfile", Label: "Boothfile", Group: "Build",
		Detail: "Use a Boothfile from this path instead of\n.booth/Boothfile."},
	{Key: "build-args", Label: "Build Args", Group: "Build",
		Detail: "Extra arguments passed to 'docker build'.\nEach entry is one argument.\n\nExample:\n  --build-arg\n  HTTP_PROXY=http://proxy:3128"},
	{Key: "common-args", Label: "Common Args", Group: "Build",
		Detail: "Arguments passed to both 'docker build' and\n'docker run'. Each entry is one argument."},

	// --- Advanced ---
	{Key: "image", Label: "Image", Group: "Advanced",
		Detail: "Use an existing local or remote image.\nExample: repo/name:tag\n\nIf set, skips building from Dockerfile/Boothfile."},
	{Key: "version", Label: "Image Version", Group: "Advanced",
		Detail: "Tag of the prebuilt booth image to run.\n\nThis is the config.toml 'version' key — the image the\nbooth runs, not the templates it was configured from.\nIf empty, 'latest' is used."},
	{Key: "startup", Label: "Startup Command", Group: "Advanced",
		Detail: "Custom startup command to run inside the container."},
	{Key: "env-file", Label: "Env File", Group: "Advanced",
		Detail: "Provide an --env-file to docker run.\nUse 'none' to disable the default .booth/.env."},
	{Key: "cmds", Label: "Commands", Group: "Advanced",
		Detail: "Command to run instead of the variant's default.\nEach entry is one argv element — no shell is involved.\n\nExample, for `echo hello`:\n  echo\n  hello"},

	// No fields for public / password / tls-cert / tls-key.
	//
	// They are real settings — `booth --public --tls-cert ... --tls-key ...`
	// works — but they are start-time only: AppConfig tags them `toml:"-"`, so
	// booth never reads them back from a file. Rendering them here wrote
	// `public = true` into config.toml and left the booth still bound to
	// loopback, which is the worst way to learn that exposure did not take.
	//
	// They are also the wrong thing to persist. config.toml is committed, so a
	// stored `public = true` would bind 0.0.0.0 for everyone who clones, while
	// the password it requires lives in a gitignored file they do not have.

	// --- Network & Volumes ---
	{Key: "expose", Label: "Expose", Group: "Network & Volumes", TUIOnly: true, Kind: fieldKindList,
		Detail: "Expose extra ports from the container.\nEach entry adds a -p mapping.\n\nExamples:\n  3000                    (same port on host)\n  3000:3000               (host:container)\n  +8080:8080              (host = offset base + 8080)\n  ${APP_PORT:-3000}:3000  (host from env at start)\n\nOnly the host side may use ${NAME} / ${NAME:-digits};\nthe container port stays a number."},
	{Key: "env", Label: "Env", Group: "Network & Volumes", TUIOnly: true, Kind: fieldKindList,
		Detail: "Set environment variables in the container.\nEach entry adds a -e flag.\n\nExamples:\n  NODE_ENV=development\n  PYTHONDONTWRITEBYTECODE=1\n  CARGO_NET_GIT_FETCH_WITH_CLI=true\n  GEOMETRY=1920x1080\n    (desktop resolution for XFCE/KDE)"},
	{Key: "mount", Label: "Mount", Group: "Network & Volumes", TUIOnly: true, Kind: fieldKindList,
		Detail: "Bind mount files or directories.\nEach entry adds a -v flag.\n\nExamples:\n  ~/.m2:/home/coder/.m2\n    (Maven cache)\n  ~/.cargo/registry:/home/coder/.cargo/registry\n    (Cargo cache)\n  ~/.aws:/etc/cb-home-seed/.aws:ro\n    (AWS credentials, read-only)\n  ~/.npmrc:/etc/cb-home-seed/.npmrc:ro\n    (npm config)"},

	// --- Cache ---
	{Key: "cache-files", Label: "Cache Files", Group: "Cache",
		Detail: "Container paths (relative to /) kept in the local\n.booth/cache/ bind mounts — host-only, gitignored.\n\nExamples:\n  home/coder/.bash_history\n  home/coder/.claude"},
	{Key: "cache-dirs", Label: "Cache Dirs", Group: "Cache",
		Detail: "Container directories kept under .booth/cache/ as whole-dir\nbind mounts (local only, gitignored).\n\nExamples:\n  home/coder/.mozilla\n  home/coder/.chrome-data"},

	// --- Shared (team / git) ---
	{Key: "shared-files", Label: "Shared Files", Group: "Shared",
		Detail: "Container paths kept under .booth/shared/ as live bind\nmounts. Intended for git — team-shared state.\n\nExamples:\n  home/coder/.chrome-data/Default/Bookmarks\n  home/coder/.local/share/code-server/User/settings.json\n\nDo not put secrets or passwords here."},
	{Key: "shared-dirs", Label: "Shared Dirs", Group: "Shared",
		Detail: "Container directories kept under .booth/shared/ as whole-dir\nbind mounts. Intended for git — team-shared state.\n\nDo not put secrets, cookies, or full browser profiles."},

	// --- Session ---
	{Key: "idle-time", Label: "Idle Time", Group: "Session",
		Detail: "Seconds of inactivity before the booth is considered\nidle. 0 disables idle tracking."},
	{Key: "idle-shutdown-time", Label: "Idle Shutdown Time", Group: "Session",
		Detail: "Seconds the booth may stay idle before it shuts itself\ndown. 0 means never shut down on idle."},
	{Key: "idle-exit-code", Label: "Idle Exit Code", Group: "Session",
		Detail: "Exit code reported when an idle shutdown fires."},
	{Key: "show-run-time", Label: "Show Run Time", Group: "Session",
		Detail: "Show elapsed session time in the booth UI.\n\nA Unix epoch (seconds) to count up from, or any\nnon-empty value to count from container launch."},
	{Key: "show-count-down", Label: "Show Count Down", Group: "Session",
		Detail: "Show time remaining until a Unix epoch (seconds).\n\nThe booth shuts down when it reaches zero.\nGet an epoch with: date +%s"},
	{Key: "count-down-exit-code", Label: "Count Down Exit Code", Group: "Session",
		Detail: "Exit code reported when the countdown expires."},

	// --- Temp Files ---
	{Key: "leave-tmp-on-exit", Label: "Leave Tmp On Exit", Group: "Temp Files",
		Detail: "Keep .booth/.tmp/ after the booth exits, instead of\nclearing it. Useful for inspecting a failed run."},
	{Key: "keep-tmp-on-start", Label: "Keep Tmp On Start", Group: "Temp Files",
		Detail: "Reuse whatever .booth/.tmp/ already holds instead of\nstarting from a clean one."},

	// --- Debug ---
	{Key: "verbose", Label: "Verbose", Group: "Debug",
		Detail: "Print extra debugging information during booth startup."},
	{Key: "dryrun", Label: "Dry Run", Group: "Debug",
		Detail: "Print docker commands without executing them."},
	{Key: "log-time", Label: "Log Time", Group: "Debug",
		Detail: "Prefix booth's own log lines with timestamps."},
	{Key: "debug", Label: "Debug", Group: "Debug", TUIOnly: true, Kind: fieldKindBool,
		Detail: "Print resolved selection and compiled output as JSON.\n\nAffects this configure run only — it is not a booth\nsetting and is not written to config.toml."},
}

// unrenderedKeys are config.toml keys deliberately left off the field table,
// with the reason. Every key in the schema is either rendered or listed here;
// TestFieldTableCoversSchema fails on anything that is neither, so a new
// AppConfig field cannot slip in unnoticed the way this table drifted before.
var unrenderedKeys = map[string]string{
	"public":   "start-time only (toml:\"-\") — and a committed `public = true` would expose every clone",
	"password": "start-time only (toml:\"-\") — resolved from a gitignored file or stdin, never persisted",
	"tlscert":  "start-time only (toml:\"-\"), paired with --public",
	"tlskey":   "start-time only (toml:\"-\"), paired with --public",

	"config": "names which config file to read — an argument to the run, not a setting inside it",
	"code":   "names which directory to configure — a committed absolute host path helps nobody",

	"run-args": "compiled from the Expose / Env / Mount fields; a raw field would fight them",
}

// allConfigFields is the field table the renderer walks, in display order.
var allConfigFields = buildConfigFields(appctx.ConfigKeys())

// buildConfigFields joins the display metadata with the config schema.
//
// A display entry whose key is not in the schema is dropped rather than
// rendered: it means the key was removed from AppConfig, and a field for a key
// booth no longer reads is exactly the dead-field problem this join exists to
// prevent. TUI-only entries carry their own Kind and are passed through.
func buildConfigFields(schema map[string]appctx.KeySpec) []configFieldDef {
	fields := make([]configFieldDef, 0, len(fieldDisplays))
	for _, d := range fieldDisplays {
		kind := d.Kind
		if !d.TUIOnly {
			spec, known := schema[d.Key]
			if !known {
				continue
			}
			kind = kindOfSpec(spec, d.Options)
		}
		fields = append(fields, configFieldDef{
			Key:     d.Key,
			Label:   d.Label,
			Group:   d.Group,
			Kind:    kind,
			Options: d.Options,
			Detail:  d.Detail,
			TUIOnly: d.TUIOnly,
		})
	}
	return fields
}

// kindOfSpec resolves the widget for a key from its TOML shape.
//
// Declared options win: a cycle field is how an enumerated value is offered,
// and it works for a bool key too — "sudo" is a tri-state ("" / true / false)
// because leaving it unset is meaningfully different from setting it false.
func kindOfSpec(spec appctx.KeySpec, options []string) fieldKind {
	if len(options) > 0 {
		return fieldKindCycle
	}
	switch spec.Kind {
	case appctx.KeyBool:
		return fieldKindBool
	case appctx.KeyInt:
		return fieldKindInt
	case appctx.KeyList:
		return fieldKindList
	default:
		return fieldKindString
	}
}

// ConfigFieldRole says how a save has to write a rendered field back out.
type ConfigFieldRole int

const (
	// ConfigFieldToggle is a checkbox: present as a bare `--set key`, absent otherwise.
	ConfigFieldToggle ConfigFieldRole = iota
	// ConfigFieldScalar is one value: `--set key=value`, omitted when empty.
	ConfigFieldScalar
	// ConfigFieldList is zero or more values: one `--set key=value` per entry.
	ConfigFieldList
)

// RenderedConfigKeys returns the config.toml keys the TUI renders, and how each
// has to be written back.
//
// These are the keys the TUI speaks for. A save strips exactly these from the
// baseline and re-derives them from the TUI result; every other key the booth
// holds is carried through untouched, because the TUI never showed it and
// therefore has no opinion about it. Callers must take the set from here rather
// than keep their own copy — a second list is how the first one drifted.
func RenderedConfigKeys() map[string]ConfigFieldRole {
	roles := make(map[string]ConfigFieldRole, len(allConfigFields))
	for _, f := range allConfigFields {
		if f.TUIOnly {
			continue
		}
		switch f.Kind {
		case fieldKindBool:
			roles[f.Key] = ConfigFieldToggle
		case fieldKindList:
			roles[f.Key] = ConfigFieldList
		default:
			// String, int and cycle fields all read back as one string. A cycle
			// over a bool key ("sudo") belongs here and not with the toggles:
			// its empty option means "unset", which a bare --set cannot say.
			roles[f.Key] = ConfigFieldScalar
		}
	}
	return roles
}

// SortedRenderedConfigKeys returns RenderedConfigKeys' keys in a stable order,
// so a save writes the same file twice for the same input.
func SortedRenderedConfigKeys() []string {
	roles := RenderedConfigKeys()
	keys := make([]string, 0, len(roles))
	for k := range roles {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// defaultBoolValues returns the default values for boolean fields.
func defaultBoolValues() map[string]bool {
	return map[string]bool{}
}
