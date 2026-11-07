// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// GnuPG keys into a booth: the one way a host's private key reaches a booth's gpg home, used by
// gnupg+keys (the keys a user names) and by envfolio+seed (the store's key).
//
// The key files are copied as gpg keeps them -- private-keys-v1.d/<keygrip>.key, still encrypted
// with the key's passphrase -- into .booth/.tmp/gnupg-keys/private-keys/. Nothing is unlocked on
// the host and no passphrase is asked there: the booth's own gpg-agent asks it, in the booth, when
// the key is used. gnupg+keys also brings the host's public keyring (pubkeys.asc), so the booth can
// verify and encrypt to the people the host knows. The gnupg startup hook imports both into the
// booth's gpg home; .booth/.tmp/ is emptied at the next start, so the files never outlive one.
const (
	gnupgKeysEnv        = "CB_GNUPG_KEYS"
	gnupgKeysDirName    = "gnupg-keys"
	gnupgPrivateKeysDir = "private-keys"
	gnupgPublicKeysFile = "pubkeys.asc"
)

// gnupgKeysDir is where this start's key files go, under the booth's .booth/.tmp/.
func gnupgKeysDir(boothDir string) string {
	return filepath.Join(boothDir, ".tmp", gnupgKeysDirName)
}

// PrepareGnupgKeys copies the private keys GNUPG_KEYS names (gnupg+keys), and the host's public
// keyring, into .booth/.tmp/gnupg-keys/. It runs after PrepareBoothTmp. A key that cannot be
// brought stops the start: the booth was set up to have it, and gpg's message says why.
func PrepareGnupgKeys(ctx appctx.AppContext) (appctx.AppContext, error) {
	spec, ok := runArgEnvValue(ctx.RunArgs(), gnupgKeysEnv)
	if !ok || strings.TrimSpace(spec) == "" {
		return ctx, nil
	}
	ids, err := parseKeyIDs(spec)
	if err != nil {
		return ctx, fmt.Errorf("gnupg keys: %w", err)
	}
	if ctx.Dryrun() {
		fmt.Fprintf(os.Stderr, "Info: would bring the host's GnuPG key(s) %s (passphrase-protected) "+
			"and its public keyring into the booth\n", strings.Join(ids, ", "))
		return ctx, nil
	}
	boothDir := hostBoothDir(ctx)
	if info, err := os.Stat(boothDir); boothDir == "" || err != nil || !info.IsDir() {
		return ctx, fmt.Errorf("gnupg keys: the booth has no .booth folder to put the keys in (%s)", boothDir)
	}
	dir := gnupgKeysDir(boothDir)
	files, err := copyHostPrivateKeys(ctx.Code(), ids, filepath.Join(dir, gnupgPrivateKeysDir))
	if err != nil {
		return ctx, fmt.Errorf("gnupg keys: %w", err)
	}
	if err := exportHostPublicKeys(ctx.Code(), filepath.Join(dir, gnupgPublicKeysFile), nil); err != nil {
		return ctx, fmt.Errorf("gnupg keys: could not export the host's public keyring: %w", err)
	}
	// Every start says what came in, so a key brought by someone else's config is seen.
	fmt.Fprintf(os.Stderr, "Info: GnuPG keys: %d private key file(s) for %s, still protected by "+
		"their passphrase, and the host's public keyring (gnupg+keys).\n", files, strings.Join(ids, ", "))
	return ctx, nil
}

// keyIDPattern is what a key may be named by: a fingerprint or key id (0x… too), or an email
// (<…> too). Nothing that starts with "-": the ids go to gpg on the host as arguments, and
// GNUPG_KEYS comes from the project's config, which may be someone else's.
var keyIDPattern = regexp.MustCompile(`^<?[A-Za-z0-9][A-Za-z0-9@._+=-]*>?$`)

// parseKeyIDs splits GNUPG_KEYS on blanks and commas.
func parseKeyIDs(spec string) ([]string, error) {
	fields := strings.FieldsFunc(spec, func(r rune) bool {
		return r == ' ' || r == '\t' || r == '\n' || r == ','
	})
	if len(fields) == 0 {
		return nil, fmt.Errorf("GNUPG_KEYS names no key")
	}
	for _, id := range fields {
		if !keyIDPattern.MatchString(id) {
			return nil, fmt.Errorf("%q is not a key id, fingerprint or email", id)
		}
	}
	return fields, nil
}

// copyHostPrivateKeys copies the private key files of the keys ids name -- each is
// <keygrip>.key in the host's gpg home, private-keys-v1.d/, already encrypted with the key's
// passphrase -- into dst, and returns how many it copied. It is an error when gpg knows no secret
// key for one of the ids, or when none of the keygrips has a file (a key on a smartcard, or one
// whose secret part is on another machine).
func copyHostPrivateKeys(dir string, ids []string, dst string) (int, error) {
	if len(ids) == 0 {
		return 0, fmt.Errorf("no key named")
	}
	homeOut, err := runHost(dir, gpgconfCommand, "--list-dirs", "homedir")
	if err != nil {
		return 0, fmt.Errorf("`gpgconf --list-dirs homedir` failed: %w", err)
	}
	keyDir := filepath.Join(strings.TrimSpace(homeOut), "private-keys-v1.d")
	args := append([]string{"--batch", "--with-colons", "--with-keygrip", "--list-secret-keys", "--"}, ids...)
	listing, err := runHost(dir, gpgCommand, args...)
	if err != nil {
		return 0, fmt.Errorf("gpg has no private key for %s: %w", strings.Join(ids, ", "), err)
	}
	if err := os.MkdirAll(dst, 0o700); err != nil {
		return 0, err
	}
	count := 0
	for _, grip := range parseKeygrips(listing) {
		if !isRegularFile(filepath.Join(keyDir, grip+".key")) {
			continue // a stub (smartcard) or a subkey kept elsewhere
		}
		if err := copyStoreFile(keyDir, dst, grip+".key"); err != nil {
			return 0, err
		}
		count++
	}
	if count == 0 {
		return 0, fmt.Errorf("no private key file for %s in %s (on a smartcard, or not on this machine?)",
			strings.Join(ids, ", "), keyDir)
	}
	return count, nil
}

// parseKeygrips returns the keygrips in `gpg --with-colons --with-keygrip` output (the "grp"
// records, field 10), each once. Only 40 hex digits count: the value names a file.
func parseKeygrips(listing string) []string {
	var grips []string
	seen := map[string]bool{}
	for _, line := range strings.Split(listing, "\n") {
		fields := strings.Split(line, ":")
		if len(fields) < 10 || fields[0] != "grp" {
			continue
		}
		grip := fields[9]
		if keygripPattern.MatchString(grip) && !seen[grip] {
			seen[grip] = true
			grips = append(grips, grip)
		}
	}
	return grips
}

var keygripPattern = regexp.MustCompile(`^[0-9A-F]{40}$`)

// exportHostPublicKeys writes the public keys of ids (armored) to dst, from the host's keyring;
// with no ids, the whole public keyring.
func exportHostPublicKeys(dir, dst string, ids []string) error {
	args := []string{"--batch", "--armor", "--export"}
	if len(ids) > 0 {
		args = append(append(args, "--"), ids...)
	}
	out, err := runHost(dir, gpgCommand, args...)
	if err != nil {
		return err
	}
	if strings.TrimSpace(out) == "" {
		if len(ids) == 0 {
			return fmt.Errorf("the host's keyring has no public key")
		}
		return fmt.Errorf("gpg has no public key for %s", strings.Join(ids, ", "))
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	return os.WriteFile(dst, []byte(out), 0o644)
}
