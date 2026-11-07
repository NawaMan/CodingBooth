// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"reflect"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func runArgs(groups ...[]string) ilist.List[ilist.List[string]] {
	var lists []ilist.List[string]
	for _, g := range groups {
		lists = append(lists, ilist.NewListFromSlice(g))
	}
	return ilist.NewListFromSlice(lists)
}

// storeHostArgs is what the extension writes into run-args.
func storeHostArgs(store, gnupg string) []string {
	return []string{"-v", store + ":/home/coder/.folio", "-v", gnupg + ":/home/coder/.gnupg",
		"-e", "FOLIO_STORE_DIR=/home/coder/.folio", "-e", "CB_FOLIO_HOST=1"}
}

func TestCheckFolioHostAlone(t *testing.T) {
	alone := runArgs(storeHostArgs("~/.folio", "~/.gnupg"))
	if err := checkFolioHostAlone(alone); err != nil {
		t.Errorf("store-host alone must pass, got %v", err)
	}
	cases := map[string]struct {
		extra []string
		want  string
	}{
		"seed":        {[]string{"-e", "CB_FOLIO_SEED=--secrets gh", "-e", "CB_FOLIO_SEED_MODE=seed"}, "envfolio+seed"},
		"gnupg keys":  {[]string{"-e", "CB_GNUPG_KEYS=me@example.com"}, "gnupg+keys"},
		"store-cache": {[]string{"-e", "FOLIO_STORE_DIR=/home/coder/.local/share/folio/store"}, "envfolio+store-cache"},
	}
	for name, c := range cases {
		err := checkFolioHostAlone(runArgs(storeHostArgs("~/.folio", "~/.gnupg"), c.extra))
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: want an error naming %s, got %v", name, c.want, err)
		}
	}
	// An empty seed selection is no seed (the extension's default), so it does not conflict.
	if err := checkFolioHostAlone(runArgs(storeHostArgs("~/.folio", "~/.gnupg"),
		[]string{"-e", "CB_FOLIO_SEED=", "-e", "CB_GNUPG_KEYS="})); err != nil {
		t.Errorf("empty seed / keys values must not conflict, got %v", err)
	}
}

func TestRunArgBindSources(t *testing.T) {
	got := runArgBindSources(runArgs(
		storeHostArgs("~/.folio", "${HOME}/.gnupg/"),
		[]string{"--volume=/data:/srv/data:ro", "-p", "8080:80"},
	))
	want := map[string]string{
		"/home/coder/.folio": "~/.folio",
		"/home/coder/.gnupg": "${HOME}/.gnupg/",
		"/srv/data":          "/data",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("bind sources = %v, want %v", got, want)
	}
}

func TestRunArgEnvValues(t *testing.T) {
	args := runArgs([]string{"-e", "A=1", "--env", "B=2"}, []string{"--env=A=3", "-e", "AB=4"})
	if got := runArgEnvValues(args, "A"); !reflect.DeepEqual(got, []string{"1", "3"}) {
		t.Errorf("values of A = %q, want every one, in order", got)
	}
	if v, ok := runArgEnvValue(args, "A"); !ok || v != "3" {
		t.Errorf("runArgEnvValue(A) = %q, %v; want the last", v, ok)
	}
	if _, ok := runArgEnvValue(args, "C"); ok {
		t.Error("an unset name must not be found")
	}
}

func TestFolioHostSocketTmpfs(t *testing.T) {
	if got := folioHostSocketTmpfs("1000", "1001"); got != "/run/user/1000:uid=1000,gid=1001,mode=0700" {
		t.Errorf("tmpfs = %q", got)
	}
}
