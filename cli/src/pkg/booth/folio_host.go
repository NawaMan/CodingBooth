// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path"
	"runtime"
	"slices"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// Folio host store (envfolio+store-host): the host's EnvFolio store and its gpg home are mounted
// into the booth as they are, live -- the store, every private key in the keyring, all of it. The
// extension's run-args carry the two mounts and -e CB_FOLIO_HOST=1; this step checks what the
// mounts cannot say for themselves:
//   - nothing else brings a store or keys into the same booth (+store-cache, +seed, gnupg+keys
//     would each give a second store or key that the live ones hide, or the other way round);
//   - both host folders exist: a missing source is dropped from the run with a warning, and the
//     booth would then make its store in the container, not on the host it meant to share;
//   - the booth's gpg-agent keeps its sockets in /run/user/<uid>/gnupg (a tmpfs added here), not
//     in the shared gpg home: on Linux they would pile up there, and on macOS the host agent's
//     own socket lives there, which the booth's gpg would find, fail to reach, and replace.
// Every start says that the host's store and keys are live in the booth.
//
// envfolio+host-agent (-e CB_FOLIO_HOST_AGENT=1) goes one step further: the booth's gpg uses the
// host's gpg-agent, so the passphrase is asked and cached on the host, once, instead of in every
// booth. The host agent's socket is mounted where the booth's gpg looks for its own; see
// folioHostAgentArgs.
const (
	folioHostEnv       = "CB_FOLIO_HOST"
	folioHostAgentEnv  = "CB_FOLIO_HOST_AGENT"
	folioHostStorePath = "/home/coder/.folio"
	folioHostGnupgPath = "/home/coder/.gnupg"
)

// PrepareFolioHost checks an envfolio+store-host run and adds its socket folder. It runs before
// PrepareFolioSeed and PrepareGnupgKeys, so a refused combination copies nothing.
func PrepareFolioHost(ctx appctx.AppContext) (appctx.AppContext, error) {
	agent, _ := runArgEnvValue(ctx.RunArgs(), folioHostAgentEnv)
	if v, _ := runArgEnvValue(ctx.RunArgs(), folioHostEnv); v != "1" {
		if agent == "1" {
			return ctx, fmt.Errorf("envfolio+host-agent: needs envfolio+store-host: the host's gpg-agent holds " +
				"only the host's keys, so it cannot open a store whose key is the booth's own")
		}
		return ctx, nil
	}
	if err := checkFolioHostAlone(ctx.RunArgs()); err != nil {
		return ctx, fmt.Errorf("envfolio+store-host: %w", err)
	}
	mounts := runArgBindSources(ctx.RunArgs())
	store, gnupg := mounts[folioHostStorePath], mounts[folioHostGnupgPath]
	if store == "" || gnupg == "" {
		return ctx, fmt.Errorf("envfolio+store-host: run-args must mount the host store at %s and the host "+
			"gpg home at %s; reselect the extension rather than editing them", folioHostStorePath, folioHostGnupgPath)
	}
	homeDir, _ := os.UserHomeDir()
	storeHost := expandHostPath(os.ExpandEnv(store), homeDir)
	gnupgHost := expandHostPath(os.ExpandEnv(gnupg), homeDir)
	if !ctx.Dryrun() {
		if !isDir(storeHost) {
			return ctx, fmt.Errorf("envfolio+store-host: the host has no EnvFolio store at %s; make it on the "+
				"host first (`folio init`), or set FOLIO_HOST_STORE to where it is", storeHost)
		}
		if !isDir(gnupgHost) {
			return ctx, fmt.Errorf("envfolio+store-host: the host has no gpg home at %s; set FOLIO_HOST_GNUPG "+
				"to where it is (`gpgconf --list-dirs homedir` on the host says)", gnupgHost)
		}
	}

	builder := ctx.ToBuilder()
	if ctx.Dryrun() {
		// The check above is skipped, so the missing-mount filter would drop a folder this host
		// lacks, and print a run the real one never is: that one refuses instead. Marked
		// `create`, a dry run takes both as there and shows the mounts (nothing is created).
		builder.RunArgs = markVolumesCreate(ctx.RunArgs(), folioHostStorePath, folioHostGnupgPath)
	}
	builder.CommonArgs.Append(ilist.NewList[string]("--tmpfs", folioHostSocketTmpfs(ctx.HostUID(), ctx.HostGID())))
	fmt.Fprintf(os.Stderr, "Warning: envfolio+store-host: the host's EnvFolio store (%s) and gpg home (%s), "+
		"private keys included, are live in this booth: anything run in it can read, change or copy them.\n",
		storeHost, gnupgHost)
	if agent == "1" {
		socket, why := folioHostAgentSocket(ctx, gnupgHost)
		if socket == "" {
			fmt.Fprintf(os.Stderr, "Info: envfolio+host-agent: %s; the booth's gpg runs its own agent and asks "+
				"for the passphrase in the booth.\n", why)
		} else {
			agentArgs := ilist.NewAppendableList[ilist.List[string]]()
			for _, group := range folioHostAgentArgs(ctx.HostUID(), ctx.HostGID(), socket) {
				agentArgs.Append(ilist.NewList[string](group...))
			}
			if ctx.Dryrun() {
				// A dry run names the default socket without starting the agent, so on a host
				// whose agent is not running yet the missing-mount filter would drop it and print
				// a run the real one never is. Marked `create`, the dry run takes it as there.
				agentArgs = markVolumesCreate(agentArgs.ToList(),
					fmt.Sprintf("/run/user/%s/gnupg/S.gpg-agent", ctx.HostUID()))
			}
			builder.CommonArgs.ExtendByList(agentArgs.ToList())
			fmt.Fprintf(os.Stderr, "Warning: envfolio+host-agent: gpg in this booth uses the host's gpg-agent (%s): "+
				"anything run in it can decrypt and sign with every key the host has unlocked, with no "+
				"passphrase asked. The booth cannot ask for one: unlock the key on the host first.\n", socket)
		}
	}
	return builder.Build(), nil
}

// folioHostAgentSocket is the host gpg-agent's socket for gnupgHost, or "" and why there is none
// to mount. gpgconf names it (the default gpg home's is $XDG_RUNTIME_DIR/gnupg/S.gpg-agent,
// another home's is in a folder of its own), and starts the agent when it is not running, as any
// gpg command on the host would. A dry run names the default without asking.
func folioHostAgentSocket(ctx appctx.AppContext, gnupgHost string) (socket, why string) {
	if ctx.Dryrun() {
		return dryrunAgentSocket(runtime.GOOS, ctx.HostUID())
	}
	return hostAgentSocket(runtime.GOOS, ctx.Code(), gnupgHost, isHostSocket)
}

// agentUnsharable is why no host gpg-agent socket can be shared on goos, or "" on Linux. On macOS
// and Windows the engine runs in a VM, which a host socket does not reach.
func agentUnsharable(goos string) string {
	if goos == "linux" {
		return ""
	}
	return "the host's gpg-agent socket cannot be shared with a booth on " + goos
}

// dryrunAgentSocket is what a dry run shows: the default socket on Linux, without asking gpgconf,
// and elsewhere the same refusal as the real run — so the dry run never prints a mount that run
// does not make.
func dryrunAgentSocket(goos, uid string) (socket, why string) {
	if why := agentUnsharable(goos); why != "" {
		return "", why
	}
	return fmt.Sprintf("/run/user/%s/gnupg/S.gpg-agent", uid), ""
}

func hostAgentSocket(goos, dir, gnupgHost string, isSocket func(string) bool) (socket, why string) {
	if why := agentUnsharable(goos); why != "" {
		return "", why
	}
	out, err := runHost(dir, gpgconfCommand, "--homedir", gnupgHost, "--list-dirs", "agent-socket")
	socket = strings.TrimSpace(out)
	if err != nil || socket == "" {
		return "", "gpgconf on the host could not name the gpg-agent socket"
	}
	if !isSocket(socket) {
		_, _ = runHost(dir, gpgconfCommand, "--homedir", gnupgHost, "--launch", "gpg-agent")
		if !isSocket(socket) {
			return "", "the host has no gpg-agent socket at " + socket
		}
	}
	return socket, ""
}

// folioHostAgentArgs is what the run gets when the host agent's socket is shared:
//   - a tmpfs for /run/user/<uid>/gnupg, the booth user's own, mode 700. The engine would
//     otherwise create that folder for the socket mount as root, and gpg ignores a socket folder
//     that is not its user's (it falls back to ~/.gnupg and starts an agent of its own);
//   - the host socket at S.gpg-agent in it, where the booth's gpg looks for its agent;
//   - GPG_TTY=/dev/null: gpg tells the agent which terminal to ask on, and the booth's
//     /dev/pts/N names some other terminal on the host. With no terminal named, an uncached
//     passphrase fails (or the host's graphical pinentry asks) instead of a prompt landing there.
//     The image's profile sets the same for login shells, which start with a clean environment.
func folioHostAgentArgs(uid, gid, hostSocket string) [][]string {
	dir := fmt.Sprintf("/run/user/%s/gnupg", uid)
	return [][]string{
		{"--tmpfs", fmt.Sprintf("%s:uid=%s,gid=%s,mode=0700", dir, uid, gid)},
		{"-v", hostSocket + ":" + dir + "/S.gpg-agent"},
		{"-e", "GPG_TTY=/dev/null"},
	}
}

// folioHostSocketTmpfs is the --tmpfs value for the booth user's /run/user/<uid>: gpg puts its
// sockets in <that>/gnupg when the folder exists and is the user's own, mode 700.
func folioHostSocketTmpfs(uid, gid string) string {
	return fmt.Sprintf("/run/user/%s:uid=%s,gid=%s,mode=0700", uid, uid, gid)
}

// checkFolioHostAlone refuses what would bring a second store or key next to the live ones.
func checkFolioHostAlone(runArgs ilist.List[ilist.List[string]]) error {
	if v, _ := runArgEnvValue(runArgs, folioSeedEnv); strings.TrimSpace(v) != "" {
		return fmt.Errorf("cannot be used with envfolio+seed: the host store is already in the booth, live")
	}
	if v, _ := runArgEnvValue(runArgs, gnupgKeysEnv); strings.TrimSpace(v) != "" {
		return fmt.Errorf("cannot be used with gnupg+keys: the host's gpg home is already in the booth, live")
	}
	for _, v := range runArgEnvValues(runArgs, "FOLIO_STORE_DIR") {
		if path.Clean(v) != folioHostStorePath {
			return fmt.Errorf("cannot be used with envfolio+store-cache (or another FOLIO_STORE_DIR, here %s): "+
				"the booth would use that store with the host's keys", v)
		}
	}
	return nil
}

// runArgEnvValues returns every value of `-e NAME=value` (or --env, --env=…) in runArgs, in order.
func runArgEnvValues(runArgs ilist.List[ilist.List[string]], name string) []string {
	var values []string
	prefix := name + "="
	runArgs.Range(func(_ int, group ilist.List[string]) bool {
		items := group.Slice()
		for i := 0; i < len(items); i++ {
			var spec string
			switch {
			case (items[i] == "-e" || items[i] == "--env") && i+1 < len(items):
				spec = items[i+1]
				i++
			case strings.HasPrefix(items[i], "--env="):
				spec = strings.TrimPrefix(items[i], "--env=")
			default:
				continue
			}
			if strings.HasPrefix(spec, prefix) {
				values = append(values, strings.TrimPrefix(spec, prefix))
			}
		}
		return true
	})
	return values
}

// markVolumesCreate adds the booth-only `create` option to each `-v` / `--volume` spec in runArgs
// whose target is one of targets ("src:dst" -> "src:dst:create", "src:dst:ro" -> "src:dst:ro,create").
func markVolumesCreate(runArgs ilist.List[ilist.List[string]], targets ...string) *ilist.AppendableList[ilist.List[string]] {
	marked := ilist.NewAppendableList[ilist.List[string]]()
	runArgs.Range(func(_ int, group ilist.List[string]) bool {
		items := append([]string(nil), group.Slice()...)
		for i := 0; i+1 < len(items); i++ {
			if !isVolumeFlag(items[i]) {
				continue
			}
			i++
			spec := items[i]
			target := volumeTarget(spec)
			if target == "" || !slices.Contains(targets, path.Clean(target)) {
				continue
			}
			if _, already := stripCreateVolumeOption(spec); already {
				continue
			}
			if len(spec) > len(volumeSource(spec))+1+len(target) {
				items[i] = spec + "," + createVolumeOption
			} else {
				items[i] = spec + ":" + createVolumeOption
			}
		}
		marked.Append(ilist.NewListFromSlice(items))
		return true
	})
	return marked
}

// runArgBindSources maps each -v / --volume target in runArgs to its host source, as written.
func runArgBindSources(runArgs ilist.List[ilist.List[string]]) map[string]string {
	sources := map[string]string{}
	runArgs.Range(func(_ int, group ilist.List[string]) bool {
		items := group.Slice()
		for i := 0; i < len(items); i++ {
			name, spec, inline := strings.Cut(items[i], "=")
			if !isVolumeFlag(name) {
				continue
			}
			if !inline {
				if i+1 >= len(items) {
					break
				}
				spec = items[i+1]
				i++
			}
			if target := volumeTarget(spec); target != "" {
				sources[path.Clean(target)] = volumeSource(spec)
			}
		}
		return true
	})
	return sources
}
