// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParseKeyIDs(t *testing.T) {
	got, err := parseKeyIDs(" 28A920C00F1DC63C, me@example.com\t0xABCDEF12 <you@example.com> ")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"28A920C00F1DC63C", "me@example.com", "0xABCDEF12", "<you@example.com>"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("ids = %q, want %q", got, want)
	}
	for _, bad := range []string{"", " , ", "--export-secret-keys", "-K", "a;b", "$(id)", "../x"} {
		if _, err := parseKeyIDs(bad); err == nil {
			t.Errorf("parseKeyIDs(%q) must be refused: it goes to gpg on the host", bad)
		}
	}
}

func TestCopyHostPrivateKeysNamedKeysOnly(t *testing.T) {
	gnupg := t.TempDir()
	keyDir := filepath.Join(gnupg, "private-keys-v1.d")
	os.MkdirAll(keyDir, 0o700)
	os.WriteFile(filepath.Join(keyDir, "E46C9395D7426A1C84DB57D6CD874C312A280EBF.key"), []byte("protected-primary"), 0o600)
	os.WriteFile(filepath.Join(keyDir, "C57CA7B533407125984D2402DCA0A0D36B819A9D.key"), []byte("protected-sub"), 0o600)
	os.WriteFile(filepath.Join(keyDir, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF.key"), []byte("another key"), 0o600)
	t.Setenv("CB_TEST_GNUPGHOME", gnupg)
	args := filepath.Join(t.TempDir(), "args")
	stubHostTools(t, `exit 0`, `echo "$@" > "`+args+`"; printf '%s' '`+keygripListing+`'`)

	dst := filepath.Join(t.TempDir(), "private-keys")
	n, err := copyHostPrivateKeys(t.TempDir(), []string{"me@example.com", "28A920C00F1DC63C"}, dst)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Errorf("copied %d key files, want 2 (the named keys' own, not another key's)", n)
	}
	if got := listFiles(t, dst); !reflect.DeepEqual(got, []string{
		"C57CA7B533407125984D2402DCA0A0D36B819A9D.key", "E46C9395D7426A1C84DB57D6CD874C312A280EBF.key"}) {
		t.Errorf("copied %q", got)
	}
	if b, _ := os.ReadFile(args); !strings.Contains(string(b), "--list-secret-keys -- me@example.com 28A920C00F1DC63C") {
		t.Errorf("gpg must be asked for exactly the named keys, after --, was run with %q", b)
	}
}

func TestCopyHostPrivateKeysUnknownKey(t *testing.T) {
	t.Setenv("CB_TEST_GNUPGHOME", t.TempDir())
	stubHostTools(t, `exit 0`, `echo "gpg: error reading key: No secret key" >&2; exit 2`)
	_, err := copyHostPrivateKeys(t.TempDir(), []string{"nobody@example.com"}, t.TempDir())
	if err == nil || !strings.Contains(err.Error(), "No secret key") {
		t.Errorf("a key gpg does not have must be an error with gpg's message, got %v", err)
	}
}

func TestExportHostPublicKeys(t *testing.T) {
	args := filepath.Join(t.TempDir(), "args")
	stubHostTools(t, `exit 0`, `echo "$@" > "`+args+`"; echo "-----BEGIN PGP PUBLIC KEY BLOCK-----"`)

	all := filepath.Join(t.TempDir(), "keys", "pubkeys.asc")
	if err := exportHostPublicKeys(t.TempDir(), all, nil); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(args); strings.TrimSpace(string(b)) != "--batch --armor --export" {
		t.Errorf("no ids must export the whole public keyring, was run with %q", b)
	}
	if b, _ := os.ReadFile(all); !strings.Contains(string(b), "PUBLIC KEY BLOCK") {
		t.Errorf("pubkeys.asc holds %q", b)
	}

	one := filepath.Join(t.TempDir(), "pubkey.asc")
	if err := exportHostPublicKeys(t.TempDir(), one, []string{"28A920C00F1DC63C"}); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(args); strings.TrimSpace(string(b)) != "--batch --armor --export -- 28A920C00F1DC63C" {
		t.Errorf("ids must export only those, after --, was run with %q", b)
	}
}

func TestExportHostPublicKeysEmptyKeyring(t *testing.T) {
	stubHostTools(t, `exit 0`, `exit 0`)
	err := exportHostPublicKeys(t.TempDir(), filepath.Join(t.TempDir(), "pubkeys.asc"), nil)
	if err == nil || !strings.Contains(err.Error(), "no public key") {
		t.Errorf("an empty keyring must be an error, got %v", err)
	}
}
