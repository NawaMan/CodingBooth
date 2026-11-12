// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	boothinit "github.com/nawaman/codingbooth/src/pkg/booth/init"
	"github.com/nawaman/codingbooth/src/pkg/gitworktree"
)

// worktreeRun is a run's `--worktree` session: what happens when the booth exits. A worktree is
// kept by default; with --worktree-remove, one this run created is removed again. With
// --worktree-push, the branch is pushed first. A worktree that already existed, without
// --worktree-push, needs no session; init finds it.
type worktreeRun struct {
	dir      string // where booth started; git runs from here
	plan     gitworktree.Plan
	remove   bool // --worktree-remove
	push     bool // --worktree-push
	existing bool // the worktree existed before this run
	checked  bool // the first init has been checked against the session
}

// worktreeFlags is what a run's arguments say about --worktree, before the `--` command.
type worktreeFlags struct {
	name, root, from                 string
	remove, push, dryrun, background bool // background: --daemon or --keep-alive
}

func readWorktreeFlags(args []string) worktreeFlags {
	var f worktreeFlags
	value := func(i int) string {
		if i+1 < len(args) {
			return args[i+1]
		}
		return ""
	}
	for i := 1; i < len(args); i++ {
		switch args[i] {
		case "--":
			return f
		case "--worktree":
			f.name = value(i)
			i++
		case "--worktree-root":
			f.root = value(i)
			i++
		case "--worktree-from":
			f.from = value(i)
			i++
		case "--worktree-remove":
			f.remove = true
		case "--worktree-keep", "--keep-worktree": // removed: keeping is the default now
			worktreeFail("%s is gone: a worktree is kept by default now; drop it "+
				"(--worktree-remove removes the worktree this run creates)", args[i])
		case "--worktree-push":
			f.push = true
		// The name 0.81.0 shipped, still taken for now. init skips it too
		// (initialize_app_context.go), and express refuses it.
		case "--push":
			warnRenamedFlag("--push", "--worktree-push")
			f.push = true
		case "--dryrun":
			f.dryrun = true
		case "--daemon", "--keep-alive":
			f.background = true
		}
	}
	return f
}

// prepareWorktree creates the --worktree worktree when it does not exist yet, before init looks
// it up. It returns the session to finish at exit, or nil when there is nothing to do then.
func prepareWorktree(args []string) *worktreeRun {
	f := readWorktreeFlags(args)
	if f.name == "" {
		if f.root != "" || f.from != "" || f.remove || f.push {
			worktreeFail("--worktree-root, --worktree-from, --worktree-remove and --worktree-push need --worktree")
		}
		return nil
	}
	if f.push && f.background {
		worktreeFail("--worktree-push pushes when the booth exits, and a --daemon or --keep-alive booth " +
			"outlives this command; push from the host when you are done")
	}

	dir := boothinit.DefaultInitializeAppContextBoundary{}.GetCurrentPath()
	entries, err := gitworktree.List(dir)
	if err != nil {
		worktreeFail("%v", err)
	}
	if entry, err := gitworktree.Find(entries, f.name); err == nil {
		if f.root != "" || f.from != "" {
			fmt.Fprintf(os.Stderr, "Note: worktree %q already exists; --worktree-root and --worktree-from are not used.\n", f.name)
		}
		if !f.push {
			return nil // it existed before this run, so this run leaves it be
		}
		if entry.Branch == "" {
			worktreeFail("worktree %s has no branch checked out, so --worktree-push has nothing to push", entry.Path)
		}
		if f.dryrun {
			fmt.Printf("Dryrun: would push branch %s when the booth exits cleanly.\n", entry.Branch)
		}
		// It existed before this run, so it stays; the session only pushes.
		return &worktreeRun{dir: dir, plan: gitworktree.Plan{Path: entry.Path, Branch: entry.Branch},
			push: true, existing: true}
	} else if !gitworktree.IsNotFound(err) {
		worktreeFail("%v", err)
	}

	if f.background && f.remove {
		worktreeFail("a --daemon or --keep-alive booth outlives this command, so nothing would remove " +
			"the worktree it creates; drop --worktree-remove, and remove it with `booth worktree remove`")
	}
	plan, err := gitworktree.PlanCreate(dir, entries, gitworktree.CreateOptions{Name: f.name, Root: f.root, From: f.from})
	if err != nil {
		worktreeFail("%v", err)
	}
	if f.dryrun {
		fmt.Printf("Dryrun: would create worktree %s on %s, starting at %s.\n", plan.Path, branchDesc(plan), short(plan.Base))
		if f.push {
			fmt.Printf("Dryrun: would push branch %s when the booth exits cleanly.\n", plan.Branch)
		}
		if f.remove {
			fmt.Printf("Dryrun: would remove the worktree when the booth exits cleanly.\n")
		}
		os.Exit(0)
	}
	if err := gitworktree.Create(dir, plan); err != nil {
		worktreeFail("%v", err)
	}
	fmt.Fprintf(os.Stderr, "Created worktree %s on %s, starting at %s.\n", plan.Path, branchDesc(plan), short(plan.Base))
	return &worktreeRun{dir: dir, plan: plan, remove: f.remove, push: f.push}
}

// check runs once, on the first init: a keep-alive or daemon booth set in config.toml outlives
// this command just as the flags do, so --worktree-push and --worktree-remove cannot work. A
// worktree --worktree-remove just created is removed again.
func (w *worktreeRun) check(ctx appctx.AppContext) {
	if w == nil || w.checked {
		return
	}
	w.checked = true
	if !(ctx.KeepAlive() || ctx.Daemon()) {
		return
	}
	if w.push {
		w.push = false // nothing was done yet: do not push
		w.finish(0)    // removes the worktree only with --worktree-remove
		worktreeFail("this booth is keep-alive or daemon (config.toml), and --worktree-push pushes when the " +
			"booth exits; push from the host when you are done")
	}
	if w.remove && !w.existing {
		w.finish(0)
		worktreeFail("this booth is keep-alive or daemon (config.toml), so nothing would remove " +
			"the worktree it creates; drop --worktree-remove")
	}
}

// finish ends the session: it pushes (--worktree-push) and removes the worktree this run created
// (--worktree-remove), when the run succeeded, and reports what happened. It returns the code booth exits with: a push that
// was asked for and did not happen turns a 0 into 1, so a script can tell.
func (w *worktreeRun) finish(exitCode int) int {
	if w == nil {
		return exitCode
	}
	out := gitworktree.Finish(w.dir, w.plan, gitworktree.FinishOptions{
		ExitCode: exitCode, Push: w.push, Remove: w.remove, Existing: w.existing})
	for _, line := range out.Messages {
		fmt.Fprintln(os.Stderr, line)
	}
	if exitCode == 0 && out.NotPushed {
		return 1
	}
	return exitCode
}

func branchDesc(plan gitworktree.Plan) string {
	if plan.NewBranch {
		return "new branch " + plan.Branch
	}
	return "branch " + plan.Branch
}

func short(sha string) string {
	if len(sha) > 8 {
		return sha[:8]
	}
	return sha
}

func warnRenamedFlag(old, renamed string) {
	fmt.Fprintf(os.Stderr, "Warning: %s is now %s; the old name will go away.\n", old, renamed)
}

func worktreeFail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "Error: "+format+"\n", args...)
	os.Exit(1)
}
