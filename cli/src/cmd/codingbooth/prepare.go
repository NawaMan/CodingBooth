// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/term"

	"github.com/nawaman/codingbooth/src/pkg/prepare"
)

// runPrepare is `booth prepare gha|ubuntu [options]` (EXPERIMENT): make this
// machine run the project's booth code without a container. See docs/REUSE_BOOTH.md.
func runPrepare() {
	os.Exit(prepareCmd(os.Args[2:], os.Stdin, os.Stdout, os.Stderr, term.IsTerminal(int(os.Stdin.Fd()))))
}

func prepareCmd(args []string, stdin io.Reader, stdout, stderr io.Writer, interactive bool) int {
	o, code, ok := parsePrepareArgs(args, stderr)
	if !ok {
		return code
	}
	o.Stdin, o.Stdout, o.Stderr, o.Interactive = stdin, stdout, stderr, interactive
	return prepare.Run(o)
}

// parsePrepareArgs returns the options, or ok=false with the exit code (0 after --help).
func parsePrepareArgs(args []string, stderr io.Writer) (o prepare.Options, code int, ok bool) {
	o.ProjectDir = "."
	value := func(i *int, name string) (string, bool) {
		if *i+1 >= len(args) {
			fmt.Fprintf(stderr, "Error: %s needs a value\n", name)
			return "", false
		}
		*i++
		return args[*i], true
	}
	var target string
	for i := 0; i < len(args); i++ {
		a := args[i]
		name, inline, hasInline := strings.Cut(a, "=")
		if !strings.HasPrefix(a, "--") {
			hasInline = false
			name = a
		}
		get := func() (string, bool) {
			if hasInline {
				return inline, true
			}
			return value(&i, name)
		}
		var v string
		var good bool
		switch name {
		case "-h", "--help", "help":
			showHelpPrepare()
			return o, 0, false
		case "-y", "--yes":
			o.Yes = true
			continue
		case "--variant":
			v, good = get()
			o.Variant = v
		case "--add-user":
			v, good = get()
			o.AddUser = v
		case "--source":
			v, good = get()
			o.Source = v
		case "--report":
			v, good = get()
			o.Report = v
		case "--code":
			v, good = get()
			o.ProjectDir = v
		default:
			if strings.HasPrefix(a, "-") {
				fmt.Fprintf(stderr, "Error: unknown option %s\nRun '%s prepare --help' for usage.\n", a, scriptName())
				return o, 2, false
			}
			if target != "" {
				fmt.Fprintf(stderr, "Error: unexpected argument %s\nRun '%s prepare --help' for usage.\n", a, scriptName())
				return o, 2, false
			}
			target, good = a, true
		}
		if !good {
			return o, 2, false
		}
	}
	if target == "" {
		fmt.Fprintf(stderr, "Error: booth prepare needs a target: gha or ubuntu\nRun '%s prepare --help' for usage.\n", scriptName())
		return o, 2, false
	}
	t, err := prepare.ParseTarget(target)
	if err != nil {
		fmt.Fprintf(stderr, "Error: %v\n", err)
		return o, 2, false
	}
	o.Target = t
	return o, 0, true
}

func showHelpPrepare() {
	s := scriptName()
	fmt.Printf(`%s prepare — [Experimental] make this machine run the project's booth code, without a container

USAGE:
  %s prepare gha    [options]   on a GitHub Actions runner (runs-on: ubuntu-26.04)
  %s prepare ubuntu [options]   on an Ubuntu 26.04 machine

Replays, on the machine itself, what building and starting the booth does in a
container: the base image, the variant, the project's .booth/Boothfile, and
booth-entry's user steps (profile, home seeds, startup hooks). Each failing
line is reported, the run goes on, and the exit status is 1 if anything failed.

  gha     Always a base booth: graphic and notebook parts are skipped. Later
          steps get the login shell's environment through GITHUB_ENV and
          GITHUB_PATH, so they need no 'bash -l'.
  ubuntu  Takes --variant (else config.toml's variant, else base). Changes the
          whole machine (apt, /opt, /usr/local, /etc/profile.d), so it asks
          first unless --yes.

Run it as an ordinary user that can sudo; the machine is set up for that user
and the current folder is the project. As root, name the user with --add-user.

OPTIONS:
  --variant <name>     ubuntu: base | notebook | codeserver | xfce | kde | lxqt | wayland
  --add-user <name>    As root: create the user if missing, add it to sudo, prepare for it
  --code <dir>         The project folder (default: the current folder)
  --source <dir>       Use the scripts of a CodingBooth checkout, not the embedded ones
  --report <file>      Write the provisioning report there (default: a temp file)
  -y, --yes            ubuntu: do not ask before changing the machine

EXAMPLE (a workflow step):
  - run: ./booth prepare gha
  - run: just test

See docs/REUSE_BOOTH.md.
`, s, s, s)
}
