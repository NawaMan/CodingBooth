// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// Git finds a worktree's repository through absolute paths in one-line pointer files: the
// worktree's .git file names its record folder (.git/worktrees/<id>), and the record's gitdir
// file names the worktree's .git file. Mounting the main clone's .git at its host path made those
// resolve, but it showed the host's folders in the booth -- /home/<you>/dev/... -- which look like
// the user's home and, being folders the engine made, are writable with sudo.
//
// So booth shows git a neutral layout instead. The main clone's .git is mounted at
// /opt/codingbooth/git/<repo>/.git, and every pointer git reads is covered, in the container only,
// by a generated read-only file that points within the booth:
//
//	/home/coder/code/.git                       gitdir: <common>/worktrees/<this>
//	<common>/worktrees/<id>/gitdir              where worktree <id>'s .git file is in the booth
//	/opt/codingbooth/git/<repo>/worktrees/<id>/.git   gitdir: <common>/worktrees/<id>  (others)
//
// A worktree inside the workspace mount (nested under the main clone, say) keeps its own place
// there; only its .git file is covered. Nothing outside the real .git is writable: the pointers
// are read-only, and /opt/codingbooth/git itself is a read-only tmpfs. The host's files never
// change, and an in-booth `git worktree repair` cannot rewrite a record (they are read-only).
//
// A worktree git adds in a booth is the one thing the booth cannot cover: git writes its record
// and its .git file with the paths it sees there. healBoothAddedWorktrees writes the host paths
// back at the next start of a booth on the same folder.

// neutralGitRoot is where a booth on a repository with worktrees sees that repository's git
// folders.
const neutralGitRoot = "/opt/codingbooth/git"

// gitPointer is a generated pointer file: content, mounted read-only at containerPath.
type gitPointer struct {
	containerPath string
	content       string
}

// neutralGitPlan is what a booth on a repository needs for git to work through neutral paths.
type neutralGitPlan struct {
	common       *gitWorktreeMount // the main clone's .git, when it is outside the workspace
	pointers     []gitPointer
	hasWorktrees bool // the repository has worktree records (pin gc, see gitWorktreeEnv)
	tmpfs        bool // something is mounted under neutralGitRoot
}

func (plan *neutralGitPlan) add(containerPath, content string) {
	for _, p := range plan.pointers {
		if p.containerPath == containerPath {
			return
		}
	}
	plan.pointers = append(plan.pointers, gitPointer{containerPath: containerPath, content: content})
	if strings.HasPrefix(containerPath, neutralGitRoot+"/") {
		plan.tmpfs = true
	}
}

// hostWorktreeGit reads the gitfile of the worktree at codePath on the host: its record folder
// and the main clone's .git. isWorktree is false for a normal repo, no repo, or a submodule (its
// git folder has no commondir); warning explains a gitfile that is broken.
func hostWorktreeGit(codePath string) (hostGitdir, hostCommon string, isWorktree bool, warning string) {
	gitFile := filepath.Join(codePath, ".git")
	info, err := os.Lstat(gitFile)
	if err != nil || !info.Mode().IsRegular() {
		return "", "", false, "" // a normal repo (.git/ is a folder) or no repo at all
	}
	data, err := os.ReadFile(gitFile)
	if err != nil {
		return "", "", false, fmt.Sprintf("could not read %s (%v)", gitFile, err)
	}
	gitdir, found := strings.CutPrefix(strings.TrimSpace(firstLine(string(data))), "gitdir:")
	gitdir = strings.TrimSpace(gitdir)
	if !found || gitdir == "" {
		return "", "", false, fmt.Sprintf("%s is not a gitfile (no \"gitdir:\" line)", gitFile)
	}
	hostGitdir = gitdir
	if !filepath.IsAbs(hostGitdir) {
		hostGitdir = filepath.Join(codePath, hostGitdir)
	}
	hostGitdir = filepath.Clean(hostGitdir)

	// A worktree's git folder has a commondir file pointing back at the main clone's .git.
	// A submodule's has none: it is a whole repository of its own.
	commonData, err := os.ReadFile(filepath.Join(hostGitdir, "commondir"))
	if err != nil {
		return "", "", false, ""
	}
	commondir := strings.TrimSpace(firstLine(string(commonData)))
	if commondir == "" {
		return "", "", false, ""
	}
	hostCommon = commondir
	if !filepath.IsAbs(hostCommon) {
		hostCommon = filepath.Join(hostGitdir, hostCommon)
	}
	hostCommon = filepath.Clean(hostCommon)
	if info, err := os.Stat(hostCommon); err != nil || !info.IsDir() {
		return "", "", false, fmt.Sprintf("the main repository's git folder %s does not exist", hostCommon)
	}
	if rel, err := filepath.Rel(hostCommon, hostGitdir); err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", "", false, fmt.Sprintf("the worktree's git folder %s is not inside %s", hostGitdir, hostCommon)
	}
	return hostGitdir, hostCommon, true, ""
}

// inWorkspace returns where hostPath is in the booth when it is inside the workspace (codePath,
// mounted at /home/coder/code).
func inWorkspace(codePath, hostPath string) (string, bool) {
	rel, err := filepath.Rel(codePath, hostPath)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		return "", false
	}
	return path.Join(containerCodePath, filepath.ToSlash(rel)), true
}

// gitRepoName names the repository in the neutral layout: the main clone's folder name.
func gitRepoName(hostCommon string) string {
	name := filepath.Base(hostCommon)
	if name == ".git" {
		name = filepath.Base(filepath.Dir(hostCommon))
	}
	name = strings.TrimSuffix(name, ".git")
	clean := strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '.', r == '_', r == '-':
			return r
		}
		return '-'
	}, name)
	if strings.Trim(clean, ".-") == "" {
		return "repo"
	}
	return clean
}

// planNeutralGit works out the neutral layout for a booth on codePath. ok is false when there is
// nothing to do (no repo, a submodule, a broken gitfile -- warning says why).
func planNeutralGit(codePath string) (plan neutralGitPlan, ok bool, warning string) {
	if codePath == "" {
		return plan, false, ""
	}
	var hostCommon, containerCommon, current string
	dotGit := filepath.Join(codePath, ".git")
	if info, err := os.Lstat(dotGit); err == nil && info.Mode().IsRegular() {
		hostGitdir, common, isWorktree, warn := hostWorktreeGit(codePath)
		if !isWorktree {
			return plan, false, warn
		}
		hostCommon = common
		if inBooth, in := inWorkspace(codePath, hostCommon); in {
			containerCommon = inBooth
		} else {
			if strings.Contains(hostCommon, ":") {
				return plan, false, fmt.Sprintf("cannot mount %s: the path contains ':'", hostCommon)
			}
			containerCommon = path.Join(neutralGitRoot, gitRepoName(hostCommon), ".git")
			plan.common = &gitWorktreeMount{hostPath: hostCommon, containerPath: containerCommon}
			plan.tmpfs = true
		}
		rel, err := filepath.Rel(filepath.Join(hostCommon, "worktrees"), hostGitdir)
		if err != nil || rel == "." || rel == ".." || strings.ContainsAny(rel, `/\:`) {
			return neutralGitPlan{}, false, fmt.Sprintf("the worktree's git folder %s is not a record in %s",
				hostGitdir, filepath.Join(hostCommon, "worktrees"))
		}
		current = rel
		plan.add(containerCodePath+"/.git", "gitdir: "+containerCommon+"/worktrees/"+current+"\n")
	} else if isDir(dotGit) {
		hostCommon, containerCommon = dotGit, containerCodePath+"/.git"
	} else {
		return plan, false, ""
	}

	entries, _ := os.ReadDir(filepath.Join(hostCommon, "worktrees"))
	for _, entry := range entries {
		if !entry.IsDir() || strings.Contains(entry.Name(), ":") {
			continue
		}
		id := entry.Name()
		hostAdmin := filepath.Join(hostCommon, "worktrees", id)
		data, err := os.ReadFile(filepath.Join(hostAdmin, "gitdir"))
		if err != nil {
			continue
		}
		recorded := strings.TrimSpace(firstLine(string(data)))
		if recorded == "" {
			continue
		}
		plan.hasWorktrees = true

		var inBooth string
		if id == current {
			inBooth = containerCodePath + "/.git"
		} else {
			hostFile := recorded
			if !filepath.IsAbs(hostFile) {
				hostFile = filepath.Join(hostAdmin, hostFile)
			}
			hostFile = filepath.Clean(hostFile)
			if info, err := os.Lstat(hostFile); err != nil || !info.Mode().IsRegular() {
				continue // gone on the host: really stale, so prune may drop it
			}
			if at, in := inWorkspace(codePath, hostFile); in {
				inBooth = at
			} else {
				inBooth = path.Join(neutralGitRoot, gitRepoName(hostCommon), "worktrees", id, ".git")
			}
			plan.add(inBooth, "gitdir: "+containerCommon+"/worktrees/"+id+"\n")
		}
		plan.add(containerCommon+"/worktrees/"+id+"/gitdir", inBooth+"\n")
	}
	return plan, true, ""
}

// addNeutralGitMounts shows git in the booth the neutral layout. It first heals what booths left
// in the records. It returns false, having added nothing, when the pointer files cannot be
// written, so that the caller can mount the host's paths instead.
func addNeutralGitMounts(builder *appctx.AppContextBuilder, codePath string, dryrun bool) bool {
	if !dryrun {
		if hostCommon := hostGitCommon(codePath); hostCommon != "" {
			// Records a booth on the host's paths broke with `git worktree repair` (older booths).
			containerCommon := filepath.ToSlash(hostCommon)
			if mount, ok, _ := resolveGitWorktreeMount(codePath); ok {
				containerCommon = mount.containerPath
			} else if isDir(filepath.Join(codePath, ".git")) {
				containerCommon = containerCodePath + "/.git"
			}
			reportHealed(healWorktreeRecords(hostCommon, containerCommon))
			reportHealedAdds(healBoothAddedWorktrees(codePath, hostCommon))
		}
	}

	plan, ok, warning := planNeutralGit(codePath)
	if warning != "" {
		fmt.Fprintf(os.Stderr, "Warning: git will not work in this booth: %s.\n", warning)
	}
	if !ok {
		return true
	}
	dir, err := gitPointerDir(codePath)
	var files []string
	if err == nil {
		files, err = writeGitPointers(dir, plan.pointers)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not write git's pointer files for the booth (%v); "+
			"mounting the repository at its host path instead.\n", err)
		return false
	}

	if plan.tmpfs {
		builder.CommonArgs.Append(ilist.NewList[string]("--tmpfs", neutralGitRoot+":ro,mode=755"))
	}
	if plan.common != nil {
		builder.CommonArgs.Append(ilist.NewList[string]("-v", plan.common.hostPath+":"+plan.common.containerPath))
	}
	for i, p := range plan.pointers {
		builder.CommonArgs.Append(ilist.NewList[string]("-v", files[i]+":"+p.containerPath+":ro"))
	}
	if plan.hasWorktrees {
		for _, env := range gitWorktreeEnv {
			builder.CommonArgs.Append(ilist.NewList[string]("-e", env))
		}
	}
	return true
}

// hostGitCommon returns the host path of the git folder of the repository at codePath -- the main
// clone's .git for a worktree -- or "" when there is none.
func hostGitCommon(codePath string) string {
	if codePath == "" {
		return ""
	}
	if _, hostCommon, isWorktree, _ := hostWorktreeGit(codePath); isWorktree {
		return hostCommon
	}
	if dotGit := filepath.Join(codePath, ".git"); isDir(dotGit) {
		return dotGit
	}
	return ""
}

func reportHealedAdds(files []string, err error) {
	for _, file := range files {
		fmt.Fprintf(os.Stderr, "Note: repaired %s, which `git worktree add` in a booth had written with the booth's paths.\n", file)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not repair a worktree added in a booth: %v.\n", err)
	}
}

// gitPointerDir is where the generated pointer files for a booth on codePath are kept:
// <cache>/codingbooth/git-pointers/<hash of codePath>/, <cache> being $XDG_CACHE_HOME, else
// ~/.cache. They stay there, because a booth restarted later mounts them again.
func gitPointerDir(codePath string) (string, error) {
	cacheHome := os.Getenv("XDG_CACHE_HOME")
	if cacheHome == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		cacheHome = filepath.Join(home, ".cache")
	}
	sum := sha256.Sum256([]byte(codePath))
	return filepath.Join(cacheHome, "codingbooth", "git-pointers", hex.EncodeToString(sum[:8])), nil
}

// writeGitPointers writes each pointer's content into dir and returns the host file for each, in
// order. A file whose content is unchanged is left alone, so a booth already running on it -- a
// second booth on the same folder -- keeps the same file.
func writeGitPointers(dir string, pointers []gitPointer) ([]string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	files := make([]string, len(pointers))
	for i, p := range pointers {
		sum := sha256.Sum256([]byte(p.containerPath))
		files[i] = filepath.Join(dir, hex.EncodeToString(sum[:8]))
		if err := writeIfChanged(files[i], p.content); err != nil {
			return nil, err
		}
	}
	return files, nil
}

// healBoothAddedWorktrees writes host paths back into what an in-booth `git worktree add` left:
// a record holding the worktree's path in the booth, and the worktree's .git file holding the
// record's. Only a worktree made inside the workspace exists on the host at all; it is healed by
// the next booth on the same folder (codePath), and only when its .git file, read the way the
// booth saw it, leads back to the record. hostCommon is the repository's git folder on the host;
// the booth saw it at containerCommon. It returns the files it fixed.
func healBoothAddedWorktrees(codePath, hostCommon string) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(hostCommon, "worktrees"))
	if err != nil {
		return nil, nil
	}
	// Where a booth on this folder may have seen the git folder: the neutral path (a booth on a
	// worktree) or inside the workspace (a booth on the main clone).
	seenAt := []string{path.Join(neutralGitRoot, gitRepoName(hostCommon), ".git")}
	if inBooth, in := inWorkspace(codePath, hostCommon); in {
		seenAt = append(seenAt, inBooth)
	}
	toHost := func(p string) string {
		for _, at := range seenAt {
			if p == at || strings.HasPrefix(p, at+"/") {
				return filepath.Join(hostCommon, filepath.FromSlash(strings.TrimPrefix(p, at)))
			}
		}
		if p == containerCodePath || strings.HasPrefix(p, containerCodePath+"/") {
			return filepath.Join(codePath, filepath.FromSlash(strings.TrimPrefix(p, containerCodePath)))
		}
		return ""
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
		recorded := path.Clean(strings.TrimSpace(firstLine(string(data))))
		// The worktree's own .git (/home/coder/code/.git) is what `git worktree repair` writes;
		// healWorktreeBackLink and healWorktreeRecords handle that.
		if !strings.HasPrefix(recorded, containerCodePath+"/") || recorded == boothRecordPath {
			continue
		}
		hostFile := toHost(recorded)
		if hostFile == "" || filepath.Base(hostFile) != ".git" {
			continue
		}
		info, err := os.Lstat(hostFile)
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		gitData, err := os.ReadFile(hostFile)
		if err != nil {
			continue
		}
		gitdir, found := strings.CutPrefix(strings.TrimSpace(firstLine(string(gitData))), "gitdir:")
		gitdir = filepath.ToSlash(strings.TrimSpace(gitdir))
		if !found || gitdir == "" {
			continue
		}
		if !path.IsAbs(gitdir) {
			gitdir = path.Join(path.Dir(recorded), gitdir) // relative to where the booth saw the file
		}
		if leads := toHost(path.Clean(gitdir)); leads == "" || !samePath(leads, hostAdmin) {
			continue // not this record's worktree, as the booth saw it
		}
		if err := os.WriteFile(hostFile, []byte("gitdir: "+hostAdmin+"\n"), 0o644); err != nil {
			return healed, err
		}
		if err := os.WriteFile(record, []byte(hostFile+"\n"), 0o644); err != nil {
			return append(healed, hostFile), err
		}
		healed = append(healed, hostFile, record)
	}
	return healed, nil
}
