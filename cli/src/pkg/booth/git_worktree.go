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

// A `git worktree repair` run in a booth on a worktree finds the record's path different from
// where it stands, /home/coder/code, and rewrites the record to /home/coder/code/.git -- a path
// that never exists on the host, so there the worktree then looks deleted and `git worktree prune`
// would drop it. In a booth on the main clone that path is the main clone's own .git, so git calls
// the record a "duplicate entry" and prunes it there too. Booth knows the host path of the
// worktree it runs on, so it writes that back; and it leaves the path beside the record, in
// worktreeHostPathFile, so that a booth on the main clone or on another worktree can heal it too.
// Git keeps that file with the record and deletes it with the record.

// worktreeHostPathFile is where booth leaves a worktree's host .git path, in its record's folder.
const worktreeHostPathFile = "cb-host-path"

// boothRecordPath is what an in-booth `git worktree repair` writes into a record.
const boothRecordPath = containerCodePath + "/.git"

// worktreeAdmin returns the record folder of the worktree at codePath -- on the host, and where
// git in the booth sees it -- or ok false when codePath is not a worktree.
func worktreeAdmin(codePath string) (hostAdmin, containerAdmin string, ok bool) {
	if codePath == "" {
		return "", "", false
	}
	gitFile := filepath.Join(codePath, ".git")
	info, err := os.Lstat(gitFile)
	if err != nil || !info.Mode().IsRegular() {
		return "", "", false
	}
	data, err := os.ReadFile(gitFile)
	if err != nil {
		return "", "", false
	}
	gitdir, found := strings.CutPrefix(strings.TrimSpace(firstLine(string(data))), "gitdir:")
	gitdir = strings.TrimSpace(gitdir)
	if !found || gitdir == "" {
		return "", "", false
	}
	hostAdmin, containerAdmin = gitdir, filepath.ToSlash(gitdir)
	if !filepath.IsAbs(hostAdmin) {
		hostAdmin = filepath.Join(codePath, hostAdmin)
		containerAdmin = path.Join(containerCodePath, containerAdmin)
	}
	hostAdmin = filepath.Clean(hostAdmin)
	if _, err := os.Stat(filepath.Join(hostAdmin, "gitdir")); err != nil {
		return "", "", false // a submodule has no record
	}
	return hostAdmin, path.Clean(containerAdmin), true
}

// recordInBooth says where the path a record holds leads in the booth, given where the record's
// folder is there; "" when the booth cannot hold it.
func recordInBooth(recorded, containerAdmin string) string {
	inBooth := filepath.ToSlash(recorded)
	if !path.IsAbs(inBooth) {
		if filepath.IsAbs(recorded) {
			return ""
		}
		inBooth = path.Join(containerAdmin, inBooth)
	}
	return path.Clean(inBooth)
}

// gitfileLeadsTo says whether the gitfile at gitFile names hostAdmin as its git folder.
func gitfileLeadsTo(gitFile, hostAdmin string) bool {
	info, err := os.Lstat(gitFile)
	if err != nil || !info.Mode().IsRegular() {
		return false
	}
	data, err := os.ReadFile(gitFile)
	if err != nil {
		return false
	}
	gitdir, found := strings.CutPrefix(strings.TrimSpace(firstLine(string(data))), "gitdir:")
	gitdir = strings.TrimSpace(gitdir)
	if !found || gitdir == "" {
		return false
	}
	if !filepath.IsAbs(gitdir) {
		gitdir = filepath.Join(filepath.Dir(gitFile), gitdir)
	}
	return samePath(gitdir, hostAdmin)
}

func samePath(a, b string) bool {
	if ra, err := filepath.EvalSymlinks(a); err == nil {
		a = ra
	}
	if rb, err := filepath.EvalSymlinks(b); err == nil {
		b = rb
	}
	return filepath.Clean(a) == filepath.Clean(b)
}

// healWorktreeBackLink writes the host path back into the record of the worktree at codePath when
// a booth broke it, and leaves that path beside the record for other booths. It returns the
// record it fixed, or "".
func healWorktreeBackLink(codePath string) (string, error) {
	hostAdmin, containerAdmin, ok := worktreeAdmin(codePath)
	if !ok {
		return "", nil
	}
	gitFile := filepath.Join(codePath, ".git")
	// Best effort: without it only a booth on this worktree can heal its record.
	_ = writeIfChanged(filepath.Join(hostAdmin, worktreeHostPathFile), gitFile+"\n")

	record := filepath.Join(hostAdmin, "gitdir")
	data, err := os.ReadFile(record)
	if err != nil {
		return "", nil
	}
	if recordInBooth(strings.TrimSpace(firstLine(string(data))), containerAdmin) != boothRecordPath {
		return "", nil
	}
	// A worktree whose host path is /home/coder/code/.git (booth run in a booth): already right.
	if samePath(gitFile, filepath.FromSlash(boothRecordPath)) {
		return "", nil
	}
	if err := os.WriteFile(record, []byte(gitFile+"\n"), 0o644); err != nil {
		return "", err
	}
	return record, nil
}

// healWorktreeRecords heals every record in the repository's git folder (hostCommon, seen at
// containerCommon in the booth) that a booth broke, from the host path a booth on that worktree
// left beside it. It only writes a path that still leads back to the record: never one that
// moved, and never over a record whose path is right on the host. It returns the records fixed.
func healWorktreeRecords(hostCommon, containerCommon string) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(hostCommon, "worktrees"))
	if err != nil {
		return nil, nil
	}
	var healed []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		hostAdmin := filepath.Join(hostCommon, "worktrees", entry.Name())
		record := filepath.Join(hostAdmin, "gitdir")
		data, err := os.ReadFile(record)
		if err != nil {
			continue
		}
		recorded := strings.TrimSpace(firstLine(string(data)))
		containerAdmin := path.Join(containerCommon, "worktrees", entry.Name())
		if recordInBooth(recorded, containerAdmin) != boothRecordPath {
			continue
		}
		onHost := recorded
		if !filepath.IsAbs(onHost) {
			onHost = filepath.Join(hostAdmin, onHost)
		}
		if gitfileLeadsTo(onHost, hostAdmin) {
			continue // right on the host after all
		}
		saved, err := os.ReadFile(filepath.Join(hostAdmin, worktreeHostPathFile))
		if err != nil {
			continue
		}
		gitFile := strings.TrimSpace(firstLine(string(saved)))
		if !filepath.IsAbs(gitFile) || !gitfileLeadsTo(gitFile, hostAdmin) {
			continue // moved or gone since a booth saw it
		}
		if err := os.WriteFile(record, []byte(gitFile+"\n"), 0o644); err != nil {
			return healed, err
		}
		healed = append(healed, record)
	}
	return healed, nil
}

func writeIfChanged(file, content string) error {
	if data, err := os.ReadFile(file); err == nil && string(data) == content {
		return nil
	}
	return os.WriteFile(file, []byte(content), 0o644)
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
// .git file and keeps gc from pruning their records. It first heals the records a booth broke.
func addGitWorktreeMount(builder *appctx.AppContextBuilder, codePath string, dryrun bool) {
	if !dryrun {
		record, err := healWorktreeBackLink(codePath)
		reportHealed([]string{record}, err)
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

	if !dryrun {
		reportHealed(healWorktreeRecords(hostCommon, containerCommon))
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

func reportHealed(records []string, err error) {
	for _, record := range records {
		if record != "" {
			fmt.Fprintf(os.Stderr, "Note: repaired %s, which `git worktree repair` in a booth had pointed at the booth's path.\n", record)
		}
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not repair git's record of a worktree: %v.\n", err)
	}
}
