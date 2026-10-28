// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package completion answers shell tab-completion: given the words typed after
// `booth`, it returns the commands, flags, or values that may come next.
//
// The command line has no framework behind it — the commands are a switch in
// main.go and the flags are spread over hand-written parsers and flag.FlagSets
// — so the shape lives here as one table. A test in cmd/codingbooth checks it
// against those parsers, so a flag added there without a line here fails.
package completion

// Kind is what a flag value or positional argument is, which decides what is
// offered for it.
type Kind int

const (
	None             Kind = iota // a flag that takes no value
	Text                         // free text: nothing to offer
	File                         // a host file path: the shell completes it
	Dir                          // a host directory path: the shell completes it
	Enum                         // one of Values
	Booth                        // the name of an existing booth container
	Select                       // a template selection DSL (go+vscode-ext,python)
	Template                     // a single template name
	Profile                      // a profile name, or a comma list of them
	ConfigKey                    // a config.toml key
	ConfigSet                    // a config.toml key=value
	CommandName                  // the name of a top-level command
	Worktree                     // a git worktree's branch or folder name, or a branch to make one for
	ExistingWorktree             // a git worktree's branch or folder name
)

// Flag is one option. Names holds every spelling; the first is the canonical one.
type Flag struct {
	Names  []string
	Kind   Kind
	Values []string // for Enum
}

// Command is a command or subcommand.
type Command struct {
	Name    string
	Aliases []string
	Desc    string
	Flags   []Flag
	Subs    []*Command
	// Args are the kinds of the positional arguments in order; the last one
	// repeats when Variadic is set.
	Args     []Kind
	Variadic bool
	// Wrapper marks a command the ./booth wrapper script handles itself; the
	// binary never sees it.
	Wrapper bool
	// Hidden commands work but are not offered.
	Hidden bool
}

// Sub returns the subcommand called name (or one of its aliases).
func (c *Command) Sub(name string) *Command {
	for _, sub := range c.Subs {
		if sub.Name == name {
			return sub
		}
		for _, alias := range sub.Aliases {
			if alias == name {
				return sub
			}
		}
	}
	return nil
}

// Flag returns the flag spelled name, or nil.
func (c *Command) Flag(name string) *Flag {
	for i := range c.Flags {
		for _, n := range c.Flags[i].Names {
			if n == name {
				return &c.Flags[i]
			}
		}
	}
	return nil
}

func flag(kind Kind, names ...string) Flag { return Flag{Names: names, Kind: kind} }
func boolFlag(names ...string) Flag        { return Flag{Names: names, Kind: None} }
func enumFlag(name string, values ...string) Flag {
	return Flag{Names: []string{name}, Kind: Enum, Values: values}
}

func join(groups ...[]Flag) []Flag {
	var all []Flag
	for _, g := range groups {
		all = append(all, g...)
	}
	return all
}

// without is flags less those named, by any spelling.
func without(flags []Flag, names ...string) []Flag {
	drop := map[string]bool{}
	for _, n := range names {
		drop[n] = true
	}
	var kept []Flag
	for _, f := range flags {
		if !drop[f.Names[0]] {
			kept = append(kept, f)
		}
	}
	return kept
}

// The names `--variant` accepts, as the help lists them.
var variantValues = []string{"base", "notebook", "codeserver", "xfce", "kde", "lxqt", "wayland"}

var engineFlag = enumFlag("--engine", "docker", "podman", "apple")

// runFlags is what a run accepts: pkg/booth/init/initialize_app_context.go.
// A bare `booth [flags]`, `booth run` and `booth print-security-warning` share it.
var runFlags = []Flag{
	flag(Dir, "--code"),
	flag(Worktree, "--worktree"),
	flag(Dir, "--worktree-root"),
	flag(Text, "--worktree-from"),
	boolFlag("--keep-worktree"),
	boolFlag("--push"),
	flag(File, "--config"),
	flag(Dir, "--booth-dir"),
	flag(Profile, "--profile"),
	boolFlag("--verbose"),
	boolFlag("--dryrun"),
	flag(File, "--boothfile"),
	flag(File, "--dockerfile"),
	flag(Text, "--image"),
	boolFlag("--pull"),
	{Names: []string{"--variant"}, Kind: Enum, Values: variantValues},
	flag(Text, "--version"),
	boolFlag("--strict"),
	flag(Text, "--build-arg"),
	boolFlag("--silence-build"),
	boolFlag("--quiet", "-q"),
	flag(Text, "--name"),
	enumFlag("--port", "NEXT", "RANDOM"),
	flag(Text, "--offset-base"),
	flag(File, "--env-file"),
	flag(Text, "--startup"),
	boolFlag("--daemon"),
	boolFlag("--keep-alive"),
	boolFlag("--hide-welcome"),
	boolFlag("--persist-home"),
	boolFlag("--public"),
	boolFlag("--ok-public"),
	flag(File, "--tls-cert"),
	flag(File, "--tls-key"),
	boolFlag("--dind"),
	enumFlag("--dind-isolation", "kata", "none"),
	flag(Text, "--dind-vm-memory"),
	flag(Text, "--dind-vm-cpus"),
	boolFlag("--dind-allowed"),
	boolFlag("--privileged-allowed"),
	boolFlag("--rootless"),
	boolFlag("--egress"),
	enumFlag("--sudo", "true", "false"),
	boolFlag("--no-sudo"),
	engineFlag,
	boolFlag("--apple-low-ports"),
	flag(Text, "--vm-memory"),
	flag(Text, "--vm-cpus"),
	flag(Text, "--vm-shm-size"),
	boolFlag("--browser"),
	boolFlag("--no-browser"),
	enumFlag("--browser-port", "NEXT", "RANDOM"),
	boolFlag("--writable-booth"),
	boolFlag("--no-writable-booth"),
	boolFlag("--log-time"),
	flag(Text, "--console-spec"),
	flag(Text, "--idle-time"),
	flag(Text, "--idle-exit-code"),
	flag(Text, "--expected-viewer-count"),
	flag(Text, "--show-run-time"),
	flag(Text, "--show-count-down"),
	flag(Text, "--count-down-exit-code"),
	boolFlag("--keep-tmp-on-start"),
	boolFlag("--leave-tmp-on-exit"),
}

// expressOwnFlags are the flags express.go parses itself; the rest of a
// command line goes on to the run parser.
var expressOwnFlags = []Flag{
	flag(Select, "--select"),
	flag(Text, "--cmd"),
	flag(Text, "--expose"),
	flag(Text, "--env"),
	flag(Text, "--mount"),
	flag(ConfigSet, "--set"),
	flag(Dir, "--templates-path"),
	enumFlag("--apt-snapshot", "today", "none"),
}

// expressRefusedRunFlags are the run flags express refuses (expressRefused in
// cmd/codingbooth/express.go), so its completion does not offer them.
var expressRefusedRunFlags = []string{
	"--config", "--profile", "--booth-dir",
	"--worktree", "--worktree-root", "--worktree-from", "--keep-worktree", "--push",
	"--writable-booth", "--no-writable-booth", "--console-spec",
	"--keep-tmp-on-start", "--leave-tmp-on-exit",
}

// configFlags: cmd/codingbooth/init.go, parseInitFlags.
var configFlags = []Flag{
	flag(Select, "--select"),
	flag(Select, "--add-select"),
	flag(Template, "--remove-select"),
	boolFlag("--no-tui"),
	boolFlag("--web"),
	boolFlag("--dryrun"),
	{Names: []string{"--variant"}, Kind: Enum, Values: variantValues},
	enumFlag("--port", "NEXT", "RANDOM"),
	flag(Dir, "--templates-path"),
	flag(Text, "--version"),
	enumFlag("--apt-snapshot", "today", "none"),
	boolFlag("--overwrite"),
	boolFlag("--beside"),
	boolFlag("--start"),
	boolFlag("--debug"),
	flag(Text, "--cmd"),
	flag(Text, "--expose"),
	flag(Text, "--add-expose"),
	flag(Text, "--remove-expose"),
	flag(Text, "--env"),
	flag(Text, "--add-env"),
	flag(Text, "--remove-env"),
	flag(Text, "--mount"),
	flag(Text, "--add-mount"),
	flag(Text, "--remove-mount"),
	flag(ConfigSet, "--set"),
	flag(ConfigKey, "--unset"),
}

// templateFlags: the template subcommands share parseInitFlags.
var templateFlags = []Flag{
	flag(Dir, "--templates-path"),
	flag(Text, "--version"),
	boolFlag("--full"),
	boolFlag("--detail"),
}

// Selecting a booth: pkg/lifecycle.
var (
	nameFlag = flag(Booth, "--name")
	codeFlag = flag(Dir, "--code")
)

// connectFlags: pkg/lifecycle/connect.go, shared by shell and exec.
var connectFlags = []Flag{
	engineFlag,
	nameFlag,
	codeFlag,
	flag(Text, "--dir"),
	flag(File, "--envfile"),
	boolFlag("--run"),
	boolFlag("--keep-alive"),
	enumFlag("--port", "NEXT", "RANDOM"),
	boolFlag("--accept-existing"),
	boolFlag("--dind-allowed"),
	boolFlag("--privileged-allowed"),
	boolFlag("--silence-build"),
	boolFlag("--quiet", "-q"),
	boolFlag("--browser"),
	flag(Text, "-e"),
}

func observe(name, desc string, extra ...Flag) *Command {
	return &Command{
		Name:  name,
		Desc:  desc,
		Flags: join([]Flag{nameFlag, codeFlag, engineFlag}, extra),
		Args:  []Kind{Booth},
	}
}

// Spec is the whole command line. Its own flags are the run's, because a bare
// `booth --variant x` is a run.
func Spec() *Command {
	return &Command{
		Name:  "booth",
		Flags: runFlags,
		Subs: []*Command{
			// --- wrapper ---
			{Name: "install", Desc: "Install the CodingBooth binary", Wrapper: true,
				Flags: []Flag{enumFlag("--cache", "shared", "local")}, Args: []Kind{Text}},
			{Name: "update", Desc: "Update the binary to the latest (or a given) version", Wrapper: true,
				Flags: []Flag{enumFlag("--cache", "shared", "local")}, Args: []Kind{Text}},
			{Name: "uninstall", Desc: "Remove this project's booth", Wrapper: true,
				Flags: []Flag{
					boolFlag("--shared-binary"), boolFlag("--all-shared-binary"),
					boolFlag("--wrapper"), boolFlag("--all"), boolFlag("--yes", "-y"),
				}},
			{Name: "create", Desc: "Make a folder and install booth into it", Wrapper: true,
				Flags: []Flag{enumFlag("--cache", "shared", "local")}, Args: []Kind{Dir}},
			{Name: "shell-config", Desc: "Install booth() and completion into bash/zsh/fish", Wrapper: true,
				Subs: []*Command{
					{Name: "install", Desc: "Install the shell function and completion"},
					{Name: "uninstall", Desc: "Remove them"},
					{Name: "status", Desc: "Show whether they are installed"},
					{Name: "help", Desc: "Show help"},
				}},
			{Name: "completion", Desc: "Print the shell completion script", Wrapper: true,
				Subs: []*Command{{Name: "bash"}, {Name: "zsh"}, {Name: "fish"}}},

			// --- binary ---
			{Name: "version", Desc: "Show version information"},
			{Name: "help", Desc: "Show help", Args: []Kind{CommandName}},
			{Name: "run", Desc: "Run the booth", Flags: runFlags},
			{Name: "express", Desc: "Run from arguments, ignoring .booth/", Flags: join(expressOwnFlags, without(runFlags, expressRefusedRunFlags...))},
			{Name: "list", Desc: "List booth containers",
				Flags: []Flag{engineFlag, boolFlag("--running"), boolFlag("--stopped"), boolFlag("--name-only"), boolFlag("--json")}},
			{Name: "worktree", Desc: "List and remove git worktrees",
				Subs: []*Command{
					{Name: "list", Desc: "List git worktrees and their booths", Flags: []Flag{engineFlag, boolFlag("--json")}},
					{Name: "remove", Desc: "Remove a worktree, its booths and its branch", Args: []Kind{ExistingWorktree},
						Flags: []Flag{engineFlag, boolFlag("--force", "-f"), boolFlag("--yes", "-y")}},
					{Name: "help", Desc: "Show help"},
				}},
			{Name: "start", Desc: "Start a stopped keep-alive booth",
				Flags: []Flag{engineFlag, nameFlag, codeFlag, boolFlag("--daemon", "-d")}, Args: []Kind{Booth}},
			{Name: "stop", Desc: "Stop a running booth",
				Flags: []Flag{engineFlag, nameFlag, boolFlag("--force", "-f"), flag(Text, "--timeout")}, Args: []Kind{Booth}},
			{Name: "restart", Desc: "Restart a running booth",
				Flags: []Flag{engineFlag, nameFlag, flag(Text, "--timeout")}, Args: []Kind{Booth}},
			{Name: "remove", Desc: "Remove booth containers",
				Flags: []Flag{engineFlag, nameFlag, boolFlag("--force", "-f")}, Args: []Kind{Booth}, Variadic: true},
			{Name: "prune", Desc: "Remove stopped booth containers",
				Flags: []Flag{engineFlag, boolFlag("--yes", "-y")}},
			{Name: "home-volume-list", Desc: "List persisted home volumes", Flags: []Flag{engineFlag}},
			{Name: "home-volume-export", Desc: "Export a home volume to tar.gz",
				Flags: []Flag{engineFlag}, Args: []Kind{Text, File}},
			{Name: "home-volume-import", Desc: "Import a tar.gz into a home volume",
				Flags: []Flag{engineFlag}, Args: []Kind{Text, File}},
			{Name: "shell", Desc: "Open a shell in a booth",
				Flags: join(connectFlags, []Flag{flag(Text, "--shell")})},
			{Name: "exec", Desc: "Run a command in a booth",
				Flags: join(connectFlags, []Flag{boolFlag("--daemon", "-d"), boolFlag("-it")})},
			{Name: "cp", Desc: "Copy files between host and booth",
				Flags: []Flag{nameFlag, codeFlag, engineFlag}, Args: []Kind{File}, Variadic: true},
			observe("inspect", "Show a booth's engine-native configuration",
				boolFlag("--json"), flag(Text, "--format", "-f")),
			observe("stats", "Show a booth's resource usage",
				boolFlag("--no-stream"), flag(Text, "--format")),
			observe("top", "Show a booth's running processes"),
			observe("diff", "List changed container filesystem paths"),
			observe("wait", "Wait for a booth to stop"),
			{Name: "logs", Desc: "Show a booth's output or service logs",
				Flags: []Flag{
					engineFlag, nameFlag, codeFlag,
					boolFlag("--follow", "-f"), flag(Text, "--tail", "-n"),
					flag(Text, "--since"), flag(Text, "--until"),
					boolFlag("--timestamps", "-t"), boolFlag("--startup"), boolFlag("--list"),
				}},
			{Name: "message", Desc: "Send messages into a booth",
				Subs: []*Command{
					{Name: "send", Desc: "Send a message",
						Flags: []Flag{
							engineFlag, nameFlag, flag(Text, "--title"), flag(Text, "--body"),
							enumFlag("--type", "yes-no", "text", "ok", "choice", "password", "toast", "banner"),
							flag(Text, "--options"), flag(Text, "--expires"), flag(Text, "--id"),
						}},
					{Name: "adjust", Desc: "Change a message",
						Flags: []Flag{engineFlag, nameFlag, flag(Text, "--title"), flag(Text, "--body")}},
					{Name: "list", Desc: "List messages", Flags: []Flag{engineFlag, nameFlag}},
					{Name: "response", Desc: "Read a message's response", Flags: []Flag{engineFlag, nameFlag}},
				}},
			{Name: "expose", Desc: "Inspect a booth's ports",
				Subs: []*Command{
					{Name: "list", Aliases: []string{"ls"}, Desc: "List a booth's published ports",
						Flags: []Flag{engineFlag, nameFlag, boolFlag("--json")}, Args: []Kind{Booth}},
				}},
			{Name: "example", Desc: "Start from an example workspace",
				Subs: []*Command{
					{Name: "list", Desc: "List examples", Flags: []Flag{flag(Text, "--version")}},
					{Name: "try", Desc: "Download an example into a folder",
						Flags: []Flag{flag(Text, "--version")}, Args: []Kind{Text, Dir}},
					{Name: "help", Desc: "Show help"},
				}},
			{Name: "template", Desc: "Browse templates",
				Subs: []*Command{
					{Name: "list", Desc: "List templates", Flags: templateFlags},
					{Name: "search", Desc: "Search templates", Flags: templateFlags, Args: []Kind{Text}},
					{Name: "show", Desc: "Show a template", Flags: templateFlags, Args: []Kind{Template}},
					{Name: "cat", Desc: "Show a template's content", Flags: templateFlags, Args: []Kind{Template}},
					{Name: "help", Desc: "Show help"},
				}},
			{Name: "showcase", Desc: "Import a CodingBooths.online showcase",
				Subs: []*Command{
					{Name: "list", Desc: "List showcases", Args: []Kind{Text},
						Flags: []Flag{flag(Text, "--limit"), flag(Text, "--cursor"), boolFlag("--json")}},
					{Name: "show", Desc: "Show a showcase", Args: []Kind{Text},
						Flags: []Flag{flag(Text, "--version"), boolFlag("--json")}},
					{Name: "import", Desc: "Import a showcase into a folder", Args: []Kind{Text, Dir},
						Flags: []Flag{flag(Text, "--version")}},
					{Name: "help", Desc: "Show help"},
				}},
			{Name: "config", Desc: "Configure this project's booth", Flags: configFlags, Args: []Kind{Dir}},
			{Name: "just-init", Desc: "Write a starter Justfile",
				Flags: []Flag{boolFlag("--yes", "-y"), flag(Dir, "--code")}, Args: []Kind{Dir}},
			{Name: "tools-cache", Desc: "Manage the tools cache",
				Subs: []*Command{
					{Name: "list", Desc: "List cached tools"},
					{Name: "clean", Desc: "Remove cached tools",
						Flags: []Flag{boolFlag("--all"), boolFlag("--unused")}},
				}},
			{Name: "build", Desc: "Build and optionally push the image",
				Flags: []Flag{
					boolFlag("--push"), flag(Text, "--name"), flag(Text, "--tag"), flag(Text, "--build-arg"),
					flag(Dir, "--code"), {Names: []string{"--variant"}, Kind: Enum, Values: variantValues},
					flag(Text, "--version"), boolFlag("--silence-build"), boolFlag("--verbose"),
					boolFlag("--dryrun"), boolFlag("--rootless"), engineFlag,
				}},
			{Name: "emit-dockerfile", Desc: "Compile the Boothfile to a Dockerfile",
				Flags: []Flag{flag(Dir, "--code"), flag(File, "--boothfile"), boolFlag("--strict")}},
			{Name: "print-security-warning", Desc: "Print the run's security warning", Flags: runFlags},
			{Name: "print-default-allowlist.txt", Desc: "Print the built-in egress allowlist"},
			{Name: "__complete", Hidden: true},
		},
	}
}
