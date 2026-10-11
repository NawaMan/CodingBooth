// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// In a git worktree, .git is a file holding `gitdir: <path>`, and that path leads into the main
// clone's .git/worktrees/<name> -- outside the mounted workspace. Inside the booth git then finds
// no repository at all. So when the workspace is a worktree, booth also mounts the main clone's git
// folder (the "common dir") at the path git will look for it in the container: the same absolute
// path for an absolute gitdir, or the path a relative gitdir resolves to from /home/coder/code.
//
// It is the repository the booth already writes to, so it does not ask for consent. Submodules are
// not covered: their core.worktree is relative to the git folder and does not resolve in the booth.

// containerCodePath is where the workspace is mounted in the booth.
const containerCodePath = "/home/coder/code"

// gitWorktreeMount is the main clone's git folder to mount: hostPath at containerPath.
type gitWorktreeMount struct {
	hostPath      string
	containerPath string
}

// resolveGitWorktreeMount returns the mount that makes git work in a booth on the worktree at
// codePath. ok is false when there is nothing to mount: not a worktree, a submodule, or a layout
// that cannot be mirrored in the container. warning explains a worktree it had to skip.
func resolveGitWorktreeMount(codePath string) (mount gitWorktreeMount, ok bool, warning string) {
	if codePath == "" {
		return mount, false, ""
	}
	gitFile := filepath.Join(codePath, ".git")
	info, err := os.Lstat(gitFile)
	if err != nil || !info.Mode().IsRegular() {
		return mount, false, "" // a normal repo (.git/ is a folder) or no repo at all
	}
	data, err := os.ReadFile(gitFile)
	if err != nil {
		return mount, false, fmt.Sprintf("could not read %s (%v)", gitFile, err)
	}
	gitdir, found := strings.CutPrefix(strings.TrimSpace(firstLine(string(data))), "gitdir:")
	gitdir = strings.TrimSpace(gitdir)
	if !found || gitdir == "" {
		return mount, false, fmt.Sprintf("%s is not a gitfile (no \"gitdir:\" line)", gitFile)
	}

	hostGitdir := gitdir
	if !filepath.IsAbs(hostGitdir) {
		hostGitdir = filepath.Join(codePath, hostGitdir)
	}
	hostGitdir = filepath.Clean(hostGitdir)

	// A worktree's git folder has a commondir file pointing back at the main clone's .git.
	// A submodule's has none: it is a whole repository of its own.
	commonData, err := os.ReadFile(filepath.Join(hostGitdir, "commondir"))
	if err != nil {
		return mount, false, ""
	}
	commondir := strings.TrimSpace(firstLine(string(commonData)))
	if commondir == "" {
		return mount, false, ""
	}

	hostCommon := commondir
	if !filepath.IsAbs(hostCommon) {
		hostCommon = filepath.Join(hostGitdir, hostCommon)
	}
	hostCommon = filepath.Clean(hostCommon)
	if info, err := os.Stat(hostCommon); err != nil || !info.IsDir() {
		return mount, false, fmt.Sprintf("the main repository's git folder %s does not exist", hostCommon)
	}
	if rel, err := filepath.Rel(hostCommon, hostGitdir); err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return mount, false, fmt.Sprintf("the worktree's git folder %s is not inside %s", hostGitdir, hostCommon)
	}

	// Where git in the container will look. An absolute path is taken as-is, so it must be a
	// Unix path -- a Windows "C:/..." gitdir cannot be mirrored.
	containerGitdir := filepath.ToSlash(gitdir)
	if !path.IsAbs(containerGitdir) {
		if filepath.IsAbs(gitdir) {
			return mount, false, fmt.Sprintf("gitdir %s is not a path the booth can use", gitdir)
		}
		containerGitdir = path.Join(containerCodePath, containerGitdir)
	}
	containerCommon := filepath.ToSlash(commondir)
	if !path.IsAbs(containerCommon) {
		containerCommon = path.Join(containerGitdir, containerCommon)
	}
	containerCommon = path.Clean(containerCommon)
	if containerCommon == containerCodePath || strings.HasPrefix(containerCommon, containerCodePath+"/") {
		return mount, false, "" // already inside the workspace mount
	}
	if reason := unusableGitMountTarget(containerCommon); reason != "" {
		return mount, false, fmt.Sprintf("cannot mount %s at %s in the booth: %s", hostCommon, containerCommon, reason)
	}
	if strings.Contains(hostCommon, ":") || strings.Contains(containerCommon, ":") {
		return mount, false, fmt.Sprintf("cannot mount %s: the path contains ':'", hostCommon)
	}
	return gitWorktreeMount{hostPath: hostCommon, containerPath: containerCommon}, true, ""
}

// unusableGitMountTarget says why containerPath cannot take a mount, or "" when it can.
func unusableGitMountTarget(containerPath string) string {
	if containerPath == "/" {
		return "it is the root folder"
	}
	if strings.HasPrefix(containerCodePath, containerPath+"/") {
		return "it would cover the workspace mount"
	}
	for _, system := range []string{"/proc", "/sys", "/dev", "/etc", "/usr", "/bin", "/sbin", "/lib"} {
		if containerPath == system || strings.HasPrefix(containerPath, system+"/") {
			return "it is a system folder"
		}
	}
	return ""
}

func firstLine(s string) string {
	line, _, _ := strings.Cut(s, "\n")
	return line
}

// gitWorktreeEnv keeps git in the booth from pruning the host's worktrees. Their records in
// .git/worktrees/ hold host paths that do not exist in the container, so every one of them looks
// stale there, and the `git gc --auto` a commit can trigger would delete those older than three
// months. A user-run `git worktree prune` still prunes.
var gitWorktreeEnv = []string{
	"GIT_CONFIG_COUNT=1",
	"GIT_CONFIG_KEY_0=gc.worktreePruneExpire",
	"GIT_CONFIG_VALUE_0=never",
}

// addGitWorktreeMount mounts the main clone's git folder when the workspace is a git worktree.
func addGitWorktreeMount(builder *appctx.AppContextBuilder, codePath string) {
	mount, ok, warning := resolveGitWorktreeMount(codePath)
	if warning != "" {
		fmt.Fprintf(os.Stderr, "Warning: git will not work in this booth: %s.\n", warning)
	}
	if !ok {
		return
	}
	builder.CommonArgs.Append(ilist.NewList[string]("-v", mount.hostPath+":"+mount.containerPath))
	for _, env := range gitWorktreeEnv {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", env))
	}
}
