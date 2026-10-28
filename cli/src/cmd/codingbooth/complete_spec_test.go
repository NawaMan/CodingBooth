// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/completion"
)

// The completion spec is a hand-kept copy of what the parsers accept, so these
// tests read the parsers' source and fail when the two disagree: a flag added to
// a parser without a line in pkg/completion/spec.go, or a spec line for a flag
// no parser knows.

func readSource(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

type nameSet map[string]bool

func (s nameSet) sorted() []string {
	var out []string
	for k := range s {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// bare drops the dashes, so `-it`, `--it` and the flag package's "it" compare equal.
func bare(flag string) string { return strings.TrimLeft(flag, "-") }

var (
	caseLine    = regexp.MustCompile(`(?m)^\s*case\b.*$`)
	flagLiteral = regexp.MustCompile(`"(-{1,2}[A-Za-z][A-Za-z0-9-]*)"`)
)

// caseFlags: the flags a hand-written parser matches in its case labels.
func caseFlags(t *testing.T, paths ...string) nameSet {
	set := nameSet{}
	for _, path := range paths {
		for _, line := range caseLine.FindAllString(readSource(t, path), -1) {
			for _, m := range flagLiteral.FindAllStringSubmatch(line, -1) {
				if name := bare(m[1]); name != "h" && name != "help" {
					set[name] = true
				}
			}
		}
	}
	return set
}

// argsCompareFlags: the flags a parser finds by scanning os.Args with ==.
func argsCompareFlags(t *testing.T, path string) nameSet {
	set := nameSet{}
	compare := regexp.MustCompile(`os\.Args\[i\] == "(-{1,2}[A-Za-z][A-Za-z0-9-]*)"`)
	for _, m := range compare.FindAllStringSubmatch(readSource(t, path), -1) {
		set[bare(m[1])] = true
	}
	return set
}

var (
	newFlagSet    = regexp.MustCompile(`flag\.NewFlagSet\(("([^"]*)"|[A-Za-z]+)`)
	flagSetDefine = regexp.MustCompile(`flagSet\.(?:String|Bool|Int|Duration|Func|Var|StringVar|BoolVar|IntVar|DurationVar)\((?:[^,()"]+,\s*)?"([A-Za-z][A-Za-z0-9-]*)"`)
)

// flagSetFlags: the flags each flag.FlagSet in a file defines, by the set's name
// ("<expr>" when the name is not a literal).
func flagSetFlags(t *testing.T, path string) map[string]nameSet {
	src := readSource(t, path)
	starts := newFlagSet.FindAllStringSubmatchIndex(src, -1)
	sets := map[string]nameSet{}
	for i, s := range starts {
		end := len(src)
		if i+1 < len(starts) {
			end = starts[i+1][0]
		}
		name := "<expr>"
		if s[4] >= 0 {
			name = src[s[4]:s[5]]
		}
		chunk := src[s[0]:end]
		set := nameSet{}
		for _, m := range flagSetDefine.FindAllStringSubmatch(chunk, -1) {
			set[m[1]] = true
		}
		if strings.Contains(chunk, "engineFlag(flagSet)") {
			set["engine"] = true
		}
		sets[name] = set
	}
	return sets
}

func specCommand(t *testing.T, path string) *completion.Command {
	t.Helper()
	cmd := completion.Spec()
	for _, word := range strings.Fields(path) {
		if cmd = cmd.Sub(word); cmd == nil {
			t.Fatalf("spec has no command %q", path)
		}
	}
	return cmd
}

func specFlags(t *testing.T, path string) nameSet {
	set := nameSet{}
	for _, f := range specCommand(t, path).Flags {
		for _, n := range f.Names {
			set[bare(n)] = true
		}
	}
	return set
}

// checkGroup: the commands in cmds share the parser whose flags are source.
// Together they must offer every flag the parser takes, and each may offer only
// flags the parser (or extra, a parser it hands the rest to) takes.
func checkGroup(t *testing.T, label string, cmds []string, source, extra nameSet) {
	t.Helper()
	union := nameSet{}
	for _, cmd := range cmds {
		for f := range specFlags(t, cmd) {
			union[f] = true
			if !source[f] && !extra[f] {
				t.Errorf("%s: spec for %q offers --%s, which the parser does not take", label, cmd, f)
			}
		}
	}
	for _, f := range source.sorted() {
		if !union[f] {
			t.Errorf("%s: the parser takes --%s, but the completion spec for %v does not list it", label, f, cmds)
		}
	}
}

func TestCompletionSpecMatchesHandWrittenParsers(t *testing.T) {
	run := caseFlags(t, "../../pkg/booth/init/initialize_app_context.go")
	checkGroup(t, "run", []string{"", "run", "print-security-warning"}, run, nil)
	for _, cmd := range []string{"", "run", "print-security-warning"} {
		checkGroup(t, "run", []string{cmd}, run, nil)
	}
	checkGroup(t, "express.go", []string{"express"}, caseFlags(t, "express.go"), run)
	checkGroup(t, "init.go", []string{"config", "template list", "template search", "template show", "template cat"},
		caseFlags(t, "init.go"), nil)
	checkGroup(t, "build.go", []string{"build"}, caseFlags(t, "build.go"), nil)
	checkGroup(t, "emit.go", []string{"emit-dockerfile"}, caseFlags(t, "emit.go"), nil)
	checkGroup(t, "just_init.go", []string{"just-init"}, caseFlags(t, "just_init.go"), nil)
	checkGroup(t, "tools_cache.go", []string{"tools-cache clean"}, caseFlags(t, "tools_cache.go"), nil)
	checkGroup(t, "showcase.go", []string{"showcase list", "showcase show", "showcase import"}, caseFlags(t, "showcase.go"), nil)
	checkGroup(t, "example.go", []string{"example list", "example try"}, argsCompareFlags(t, "example.go"), nil)
}

// Express refuses some run flags as soon as it sees them; offering them on Tab
// would only lead to that error.
func TestCompletionSpecExpressOffersNoRefusedFlag(t *testing.T) {
	offered := specFlags(t, "express")
	for flag := range expressRefused {
		if offered[bare(flag)] {
			t.Errorf("spec for express offers %s, which express refuses", flag)
		}
	}
}

func TestCompletionSpecMatchesFlagSets(t *testing.T) {
	lifecycle := map[string]map[string]nameSet{}
	for _, file := range []string{"lifecycle", "connect", "copy", "logs", "expose", "message", "home_volume", "observe"} {
		lifecycle[file] = flagSetFlags(t, "../../pkg/lifecycle/"+file+".go")
	}
	byName := func(file, set string) nameSet {
		flags, ok := lifecycle[file][set]
		if !ok {
			t.Fatalf("%s.go has no flag set %q", file, set)
		}
		return flags
	}

	for _, cmd := range []string{"list", "start", "stop", "restart", "remove", "prune"} {
		checkGroup(t, "lifecycle.go", []string{cmd}, byName("lifecycle", cmd), nil)
	}
	for _, cmd := range []string{"shell", "exec"} {
		checkGroup(t, "connect.go", []string{cmd}, byName("connect", cmd), nil)
	}
	checkGroup(t, "copy.go", []string{"cp"}, byName("copy", "cp"), nil)
	checkGroup(t, "logs.go", []string{"logs"}, byName("logs", "logs"), nil)
	checkGroup(t, "expose.go", []string{"expose list"}, byName("expose", "expose list"), nil)
	for _, sub := range []string{"send", "adjust", "list", "response"} {
		checkGroup(t, "message.go", []string{"message " + sub}, byName("message", "message "+sub), nil)
	}
	for _, cmd := range []string{"home-volume-list", "home-volume-export", "home-volume-import"} {
		checkGroup(t, "home_volume.go", []string{cmd}, byName("home_volume", cmd), nil)
	}
	// observe.go builds one flag set for all five, adding flags by command.
	checkGroup(t, "observe.go", []string{"inspect", "stats", "top", "diff", "wait"}, byName("observe", "<expr>"), nil)
}

func TestCompletionSpecMatchesMainCommands(t *testing.T) {
	src := readSource(t, "main.go")
	labels := regexp.MustCompile(`(?m)^\t\tcase (.+):$`)
	inMain := nameSet{}
	for _, m := range labels.FindAllStringSubmatch(src, -1) {
		for _, lit := range regexp.MustCompile(`"([^"]+)"`).FindAllStringSubmatch(m[1], -1) {
			if !strings.HasPrefix(lit[1], "-") {
				inMain[lit[1]] = true
			}
		}
	}

	inSpec := nameSet{}
	for _, sub := range completion.Spec().Subs {
		if !sub.Wrapper {
			inSpec[sub.Name] = true
		}
	}
	for _, name := range inMain.sorted() {
		if !inSpec[name] {
			t.Errorf("main.go dispatches %q, but the completion spec has no such command", name)
		}
	}
	for _, name := range inSpec.sorted() {
		if !inMain[name] {
			t.Errorf("the completion spec offers %q, but main.go does not dispatch it", name)
		}
	}
}

func TestCompletionSpecWrapperCommandsExistInWrapper(t *testing.T) {
	wrapper := readSource(t, "../../../../booth")
	for _, sub := range completion.Spec().Subs {
		if !sub.Wrapper {
			continue
		}
		label := regexp.MustCompile(`(?m)^\s+(?:[a-z|-]+\|)?` + regexp.QuoteMeta(sub.Name) + `(?:\|[a-z|-]+)?\)`)
		if !label.MatchString(wrapper) {
			t.Errorf("the completion spec offers wrapper command %q, but the booth script has no case for it", sub.Name)
		}
	}
}
