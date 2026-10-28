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

// worktreeRun is a run's `--worktree` session: the worktree this run created, which it removes
// again when the booth exits. A worktree that already existed needs no session; init finds it.
type worktreeRun struct {
	dir     string // where booth started; git runs from here
	plan    gitworktree.Plan
	keep    bool // --keep-worktree
	checked bool // the first init has been checked against the session
}

// worktreeFlags is what a run's arguments say about --worktree, before the `--` command.
type worktreeFlags struct {
	name, root, from         string
	keep, dryrun, background bool // background: --daemon or --keep-alive
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
		case "--keep-worktree":
			f.keep = true
		case "--dryrun":
			f.dryrun = true
		case "--daemon", "--keep-alive":
			f.background = true
		}
	}
	return f
}

// prepareWorktree creates the --worktree worktree when it does not exist yet, before init looks
// it up. It returns the session to finish at exit, or nil when there is nothing to remove later.
func prepareWorktree(args []string) *worktreeRun {
	f := readWorktreeFlags(args)
	if f.name == "" {
		if f.root != "" || f.from != "" || f.keep {
			worktreeFail("--worktree-root, --worktree-from and --keep-worktree need --worktree")
		}
		return nil
	}

	dir := boothinit.DefaultInitializeAppContextBoundary{}.GetCurrentPath()
	entries, err := gitworktree.List(dir)
	if err != nil {
		worktreeFail("%v", err)
	}
	if _, err := gitworktree.Find(entries, f.name); err == nil {
		if f.root != "" || f.from != "" {
			fmt.Fprintf(os.Stderr, "Note: worktree %q already exists; --worktree-root and --worktree-from are not used.\n", f.name)
		}
		return nil // it existed before this run, so this run leaves it be
	} else if !gitworktree.IsNotFound(err) {
		worktreeFail("%v", err)
	}

	if f.background && !f.keep {
		worktreeFail("a --daemon or --keep-alive booth outlives this command, so nothing would remove " +
			"the worktree it creates; add --keep-worktree")
	}
	plan, err := gitworktree.PlanCreate(dir, entries, gitworktree.CreateOptions{Name: f.name, Root: f.root, From: f.from})
	if err != nil {
		worktreeFail("%v", err)
	}
	if f.dryrun {
		fmt.Printf("Dryrun: would create worktree %s on %s, starting at %s.\n", plan.Path, branchDesc(plan), short(plan.Base))
		os.Exit(0)
	}
	if err := gitworktree.Create(dir, plan); err != nil {
		worktreeFail("%v", err)
	}
	fmt.Fprintf(os.Stderr, "Created worktree %s on %s, starting at %s.\n", plan.Path, branchDesc(plan), short(plan.Base))
	return &worktreeRun{dir: dir, plan: plan, keep: f.keep}
}

// check runs once, on the first init: a keep-alive or daemon booth set in config.toml outlives
// this command just as the flags do, so the worktree just created is removed again.
func (w *worktreeRun) check(ctx appctx.AppContext) {
	if w == nil || w.checked {
		return
	}
	w.checked = true
	if !w.keep && (ctx.KeepAlive() || ctx.Daemon()) {
		w.finish(0)
		worktreeFail("this booth is keep-alive or daemon (config.toml), so nothing would remove " +
			"the worktree it creates; add --keep-worktree")
	}
}

// finish removes the worktree this run created, unless kept, and reports what happened.
func (w *worktreeRun) finish(exitCode int) {
	if w == nil {
		return
	}
	if w.keep {
		fmt.Fprintf(os.Stderr, "Kept worktree %s (--keep-worktree).\n", w.plan.Path)
		return
	}
	for _, line := range gitworktree.Finish(w.dir, w.plan, exitCode).Messages {
		fmt.Fprintln(os.Stderr, line)
	}
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

func worktreeFail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "Error: "+format+"\n", args...)
	os.Exit(1)
}
