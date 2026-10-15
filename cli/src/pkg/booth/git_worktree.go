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
//
// The records in .git/worktrees/ point the other way: each one's gitdir file holds the path of its
// worktree's .git file, and git takes a record whose path does not exist for a worktree deleted
// without `git worktree remove`. In the container those are host paths, so `git worktree prune`
// in a booth would delete the records of worktrees that are alive on the host. So for a booth on a
// repository with worktrees -- the main clone or a worktree -- booth also mounts each worktree's
// .git file, read-only, at the path its record names. Only that one-line file: not the worktree.

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

// resolveWorktreeMirrors returns a read-only mount for the .git file of each worktree recorded in
// the repository's git folder (hostCommon, mounted at containerCommon), so that every record's
// path exists in the booth. hasWorktrees says whether there are records at all. A record whose
// .git file is gone on the host is not mirrored: it really is stale. Nor is one already visible in
// the workspace mount, or one whose path the container cannot hold.
func resolveWorktreeMirrors(hostCommon, containerCommon string) (mirrors []gitWorktreeMount, hasWorktrees bool) {
	entries, err := os.ReadDir(filepath.Join(hostCommon, "worktrees"))
	if err != nil {
		return nil, false
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		hostAdmin := filepath.Join(hostCommon, "worktrees", entry.Name())
		data, err := os.ReadFile(filepath.Join(hostAdmin, "gitdir"))
		if err != nil {
			continue
		}
		recorded := strings.TrimSpace(firstLine(string(data)))
		if recorded == "" {
			continue
		}
		hasWorktrees = true

		hostFile := recorded
		if !filepath.IsAbs(hostFile) {
			hostFile = filepath.Join(hostAdmin, hostFile)
		}
		hostFile = filepath.Clean(hostFile)
		if info, err := os.Lstat(hostFile); err != nil || !info.Mode().IsRegular() {
			continue
		}

		containerFile := filepath.ToSlash(recorded)
		if !path.IsAbs(containerFile) {
			if filepath.IsAbs(recorded) {
				continue // a Windows path
			}
			containerFile = path.Join(containerCommon, "worktrees", entry.Name(), containerFile)
		}
		containerFile = path.Clean(containerFile)
		if containerFile == containerCodePath || strings.HasPrefix(containerFile, containerCodePath+"/") ||
			strings.HasPrefix(containerFile, containerCommon+"/") {
			continue
		}
		if unusableGitMountTarget(containerFile) != "" ||
			strings.Contains(hostFile, ":") || strings.Contains(containerFile, ":") {
			continue
		}
		mirrors = append(mirrors, gitWorktreeMount{hostPath: hostFile, containerPath: containerFile})
	}
	return mirrors, hasWorktrees
}

// healWorktreeBackLink undoes a `git worktree repair` run in a booth on the worktree at codePath.
// From /home/coder/code, repair finds the record's path different from where it stands and
// rewrites it to /home/coder/code/.git -- a path that never exists on the host, so there the
// worktree then looks deleted and `git worktree prune` would drop it. Booth knows the host path,
// so it writes that back. It returns the record it fixed, or "".
func healWorktreeBackLink(codePath string) (string, error) {
	if codePath == "" {
		return "", nil
	}
	gitFile := filepath.Join(codePath, ".git")
	info, err := os.Lstat(gitFile)
	if err != nil || !info.Mode().IsRegular() {
		return "", nil
	}
	data, err := os.ReadFile(gitFile)
	if err != nil {
		return "", nil
	}
	gitdir, found := strings.CutPrefix(strings.TrimSpace(firstLine(string(data))), "gitdir:")
	gitdir = strings.TrimSpace(gitdir)
	if !found || gitdir == "" {
		return "", nil
	}
	hostAdmin := gitdir
	containerAdmin := filepath.ToSlash(gitdir)
	if !filepath.IsAbs(hostAdmin) {
		hostAdmin = filepath.Join(codePath, hostAdmin)
		containerAdmin = path.Join(containerCodePath, containerAdmin)
	}
	record := filepath.Join(filepath.Clean(hostAdmin), "gitdir")
	recData, err := os.ReadFile(record)
	if err != nil {
		return "", nil // not a worktree (a submodule has no gitdir record)
	}
	recorded := strings.TrimSpace(firstLine(string(recData)))
	inBooth := filepath.ToSlash(recorded)
	if !path.IsAbs(inBooth) {
		if filepath.IsAbs(recorded) {
			return "", nil
		}
		inBooth = path.Join(containerAdmin, inBooth)
	}
	if path.Clean(inBooth) != containerCodePath+"/.git" {
		return "", nil
	}
	// The record would name a host path that happens to equal the booth's: then it is right.
	if filepath.Clean(gitFile) == filepath.FromSlash(containerCodePath+"/.git") {
		return "", nil
	}
	if err := os.WriteFile(record, []byte(gitFile+"\n"), 0o644); err != nil {
		return "", err
	}
	return record, nil
}

// gitWorktreeEnv keeps git in the booth from pruning the host's worktrees. Their records in
// .git/worktrees/ hold host paths, and a record whose worktree booth could not mirror looks stale
// there; the `git gc --auto` a commit can trigger would delete those older than three months.
// The mirrors keep a `git worktree prune` you run from deleting the others.
var gitWorktreeEnv = []string{
	"GIT_CONFIG_COUNT=1",
	"GIT_CONFIG_KEY_0=gc.worktreePruneExpire",
	"GIT_CONFIG_VALUE_0=never",
}

// addGitWorktreeMount makes git in the booth safe for the repository's worktrees. On a worktree it
// mounts the main clone's git folder; on the main clone or a worktree it mirrors every worktree's
// .git file and keeps gc from pruning their records. It first heals a record a booth broke.
func addGitWorktreeMount(builder *appctx.AppContextBuilder, codePath string, dryrun bool) {
	if !dryrun {
		if record, err := healWorktreeBackLink(codePath); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not repair git's record of this worktree: %v.\n", err)
		} else if record != "" {
			fmt.Fprintf(os.Stderr, "Note: repaired %s, which `git worktree repair` in a booth had pointed at the booth's path.\n", record)
		}
	}

	mount, ok, warning := resolveGitWorktreeMount(codePath)
	if warning != "" {
		fmt.Fprintf(os.Stderr, "Warning: git will not work in this booth: %s.\n", warning)
	}
	var hostCommon, containerCommon string
	switch {
	case ok:
		builder.CommonArgs.Append(ilist.NewList[string]("-v", mount.hostPath+":"+mount.containerPath))
		hostCommon, containerCommon = mount.hostPath, mount.containerPath
	case codePath != "" && isDir(filepath.Join(codePath, ".git")):
		hostCommon, containerCommon = filepath.Join(codePath, ".git"), containerCodePath+"/.git"
	default:
		return
	}

	mirrors, hasWorktrees := resolveWorktreeMirrors(hostCommon, containerCommon)
	if !hasWorktrees {
		return
	}
	for _, mirror := range mirrors {
		builder.CommonArgs.Append(ilist.NewList[string]("-v", mirror.hostPath+":"+mirror.containerPath+":ro"))
	}
	for _, env := range gitWorktreeEnv {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", env))
	}
}
