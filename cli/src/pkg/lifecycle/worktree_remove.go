// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/gitworktree"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// WorktreeRemove is `booth worktree remove <name>`: it ends a worktree for good, with the booths
// that ran on it and its branch. Without --force it removes only what loses nothing, and says what
// it kept. --force discards uncommitted work, the branch's own commits and the booths' per-booth
// volumes, after listing them and asking (--yes skips the question). The remote branch is never
// touched.
func WorktreeRemove(args []string, stdin io.Reader, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("worktree remove", flag.ContinueOnError)
	engineChoice := engineFlag(flagSet)
	force := flagSet.Bool("force", false, "Discard uncommitted work, unpushed commits and volumes")
	flagSet.BoolVar(force, "f", false, "Discard uncommitted work, unpushed commits and volumes")
	yes := flagSet.Bool("yes", false, "Skip the confirmation prompt")
	flagSet.BoolVar(yes, "y", false, "Skip the confirmation prompt")
	flagSet.SetOutput(stderr)
	if err := parseLifecycleFlags(flagSet, args); err != nil {
		return commandExit(2, "")
	}
	if flagSet.NArg() != 1 {
		return commandExit(2, "Usage: booth worktree remove <name> [--force] [--yes]")
	}
	name := flagSet.Arg(0)

	dir, err := os.Getwd()
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}
	entries, err := gitworktree.List(dir)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}
	if main := entries[0]; len(entries) > 0 && !main.Bare && (main.Branch == name || filepath.Base(main.Path) == name) {
		return commandExit(1, fmt.Sprintf("Error: %q is the main checkout (%s); booth worktree remove removes only linked worktrees.", name, main.Path))
	}
	entry, err := gitworktree.Find(entries, name)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}
	if samePathKey(dir) == samePathKey(entry.Path) || strings.HasPrefix(samePathKey(dir), samePathKey(entry.Path)+string(os.PathSeparator)) {
		return commandExit(1, fmt.Sprintf("Error: you are inside worktree %s; run this from another checkout.", entry.Path))
	}

	engines := resolveLifecycleEngines("", *engineChoice)
	containers, err := managedContainersAcross(engines, false, stderr)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to list booths: %v", err))
	}
	booths := boothsOn(entry.Path, containers)
	loss, err := gitworktree.Assess(dir, entry)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}
	var volumes []engineVolume
	if *force {
		volumes = perBoothVolumes(engines, boothNames(booths, gitworktree.BoothName(entry)))
	}

	if refusal := removalRefusal(entry, booths, loss, *force); refusal != "" {
		return commandExit(1, refusal)
	}
	if *force {
		if lost := describeLoss(entry, booths, loss, volumes); lost != "" {
			_, _ = fmt.Fprint(stdout, lost)
			if !*yes {
				_, _ = fmt.Fprint(stdout, "Discard all of this? [y/N]: ")
				confirmed, err := readConfirmation(stdin)
				if err != nil {
					return commandExit(1, fmt.Sprintf("Error: failed to read confirmation: %v", err))
				}
				if !confirmed {
					_, _ = fmt.Fprintln(stdout, "Nothing removed.")
					return nil
				}
			}
		}
	}

	say := func(format string, args ...any) { _, _ = fmt.Fprintf(stdout, format+"\n", args...) }
	for _, b := range booths {
		flags := docker.DockerFlags{Silent: true, Engine: b.Engine}
		stopSidecars(b.Name, flags)
		rmArgs := ilist.NewList(ilist.NewList(b.Name))
		if *force {
			rmArgs = ilist.NewList(ilist.NewList("--force", "--volumes"), ilist.NewList(b.Name))
		}
		if err := docker.Docker(flags, "rm", rmArgs); err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to remove booth %q: %v", b.Name, err))
		}
		say("Removed booth %s.", b.Name)
	}
	for _, v := range volumes {
		if err := docker.Docker(docker.DockerFlags{Silent: true, Engine: v.engine}, "volume",
			ilist.NewList(ilist.NewList("rm", v.name))); err != nil {
			say("Kept volume %s: %v", v.name, err)
			continue
		}
		say("Removed volume %s.", v.name)
	}
	if err := gitworktree.Remove(dir, entry, *force); err != nil {
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}
	say("Removed worktree %s.", entry.Path)

	if entry.Branch == "" {
		return nil
	}
	upstream := gitworktree.Upstream(dir, entry.Branch)
	if loss.BranchOnly > 0 && !*force {
		say("Kept branch %s: it has %d commit(s) that no other branch, remote or tag has. --force deletes them.",
			entry.Branch, loss.BranchOnly)
	} else if err := gitworktree.DeleteBranch(dir, entry.Branch); err != nil {
		say("Kept branch %s: %v", entry.Branch, err)
	} else {
		say("Deleted branch %s.", entry.Branch)
	}
	if upstream != "" {
		remote, branch, _ := strings.Cut(upstream, "/")
		say("The remote branch %s is untouched: `git push %s --delete %s` removes it.", upstream, remote, branch)
	}
	return nil
}

// removalRefusal is why the removal must not go ahead, or "" when it may. Without --force
// nothing that is lost can go: uncommitted work, commits only at a detached HEAD, a running
// booth. (Commits only on the branch keep the branch, not the worktree.)
func removalRefusal(entry gitworktree.Entry, booths []managedContainer, loss gitworktree.Loss, force bool) string {
	if force {
		return ""
	}
	var why []string
	for _, b := range booths {
		if b.State == "running" {
			why = append(why, fmt.Sprintf("booth %s is running: stop it (`booth stop --name %s`)", b.Name, b.Name))
		}
	}
	if len(loss.Changes) > 0 {
		why = append(why, fmt.Sprintf("it has %d uncommitted or untracked file(s)", len(loss.Changes)))
	}
	if loss.HeadOnly > 0 {
		why = append(why, fmt.Sprintf("its detached HEAD has %d commit(s) that no branch, remote or tag has", loss.HeadOnly))
	}
	if len(why) == 0 {
		return ""
	}
	return fmt.Sprintf("Kept worktree %s:\n  - %s\nCommit or stop what you want to keep, or remove it anyway with --force.",
		entry.Path, strings.Join(why, "\n  - "))
}

// describeLoss lists what a --force removal throws away, or "" when it throws nothing away.
func describeLoss(entry gitworktree.Entry, booths []managedContainer, loss gitworktree.Loss, volumes []engineVolume) string {
	var b strings.Builder
	line := func(format string, args ...any) { fmt.Fprintf(&b, "  "+format+"\n", args...) }
	const shown = 10
	for i, change := range loss.Changes {
		if i == shown {
			line("  … and %d more", len(loss.Changes)-shown)
			break
		}
		if i == 0 {
			line("Uncommitted or untracked files:")
		}
		line("  %s", change)
	}
	if loss.HeadOnly > 0 {
		line("%d commit(s) at the detached HEAD, on no branch, remote or tag", loss.HeadOnly)
	}
	if loss.BranchOnly > 0 {
		line("%d commit(s) only on branch %s", loss.BranchOnly, entry.Branch)
	}
	for _, c := range booths {
		if c.State == "running" {
			line("Running booth %s (it is stopped)", c.Name)
		}
	}
	for _, v := range volumes {
		line("Volume %s", v.name)
	}
	if b.Len() == 0 {
		return ""
	}
	return fmt.Sprintf("Removing worktree %s discards:\n%s", entry.Path, b.String())
}

// boothsOn are the booths whose code path is the folder path.
func boothsOn(path string, containers []managedContainer) []managedContainer {
	var on []managedContainer
	for _, c := range containers {
		if c.CodePath != "" && samePathKey(c.CodePath) == samePathKey(path) {
			on = append(on, c)
		}
	}
	return on
}

// boothNames are the names a worktree's booths have had: those of the booths on it, and the
// name a booth there gets by default, which a booth that has gone (a one-shot) still left its
// volumes under.
func boothNames(booths []managedContainer, defaultName string) []string {
	seen := map[string]bool{}
	var names []string
	for _, n := range append([]string{defaultName}, containerNames(booths)...) {
		if n != "" && !seen[n] {
			seen[n] = true
			names = append(names, n)
		}
	}
	return names
}

func containerNames(containers []managedContainer) []string {
	var names []string
	for _, c := range containers {
		names = append(names, c.Name)
	}
	return names
}

type engineVolume struct{ engine, name string }

// perBoothVolumes are the volumes, on any of engines, that belong to one of the booth names by
// booth's naming: cb-home-<name> (--persist-home) and booth-<service>data-<name> (templates).
// Shared volumes, such as caches, have other names and are never matched.
func perBoothVolumes(engines []string, names []string) []engineVolume {
	var found []engineVolume
	for _, engine := range engines {
		out, err := docker.DockerOutput(docker.DockerFlags{Silent: true, Engine: engine}, "volume",
			ilist.NewList(ilist.NewList("ls", "--format", "{{.Name}}")))
		if err != nil {
			continue
		}
		for _, v := range matchBoothVolumes(nonEmptyLines(out), names) {
			found = append(found, engineVolume{engine, v})
		}
	}
	return found
}

var boothDataVolume = regexp.MustCompile(`^booth-[a-z0-9]+data-(.+)$`)

// matchBoothVolumes is perBoothVolumes' decision, sorted. Pure for unit tests.
func matchBoothVolumes(volumes []string, names []string) []string {
	wanted := map[string]bool{}
	for _, n := range names {
		wanted[n] = true
	}
	var matched []string
	for _, v := range volumes {
		if owner, ok := strings.CutPrefix(v, "cb-home-"); ok && wanted[owner] {
			matched = append(matched, v)
		} else if m := boothDataVolume.FindStringSubmatch(v); m != nil && wanted[m[1]] {
			matched = append(matched, v)
		}
	}
	sort.Strings(matched)
	return matched
}
