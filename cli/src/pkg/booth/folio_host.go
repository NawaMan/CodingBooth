// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path"
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
const (
	folioHostEnv       = "CB_FOLIO_HOST"
	folioHostStorePath = "/home/coder/.folio"
	folioHostGnupgPath = "/home/coder/.gnupg"
)

// PrepareFolioHost checks an envfolio+store-host run and adds its socket folder. It runs before
// PrepareFolioSeed and PrepareGnupgKeys, so a refused combination copies nothing.
func PrepareFolioHost(ctx appctx.AppContext) (appctx.AppContext, error) {
	if v, _ := runArgEnvValue(ctx.RunArgs(), folioHostEnv); v != "1" {
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
	builder.CommonArgs.Append(ilist.NewList[string]("--tmpfs", folioHostSocketTmpfs(ctx.HostUID(), ctx.HostGID())))
	fmt.Fprintf(os.Stderr, "Warning: envfolio+store-host: the host's EnvFolio store (%s) and gpg home (%s), "+
		"private keys included, are live in this booth: anything run in it can read, change or copy them.\n",
		storeHost, gnupgHost)
	return builder.Build(), nil
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
