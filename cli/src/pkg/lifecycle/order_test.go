// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestOrderSaveAndLoadRoundTrip(t *testing.T) {
	dir := t.TempDir()
	web, api := filepath.Join(dir, "web"), filepath.Join(dir, "api")
	for _, d := range []string{web, api} {
		if err := os.Mkdir(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	o := Order{Path: filepath.Join(dir, "cache", "order.json")}
	if got := o.Load(); len(got) != 0 {
		t.Fatalf("no file: order = %v, want none", got)
	}
	want := []OrderEntry{{"repo:" + web, web}, {"api@docker", api}, {"nopath@docker", ""}}
	if err := o.Save(want); err != nil {
		t.Fatal(err)
	}
	if got := o.Load(); !reflect.DeepEqual(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
}

func TestOrderDropsEntriesWhoseFolderIsGone(t *testing.T) {
	dir := t.TempDir()
	web, gone := filepath.Join(dir, "web"), filepath.Join(dir, "gone")
	if err := os.Mkdir(web, 0o755); err != nil {
		t.Fatal(err)
	}
	o := Order{Path: filepath.Join(dir, "order.json")}
	if err := o.Save([]OrderEntry{{"gone@docker", gone}, {"web@docker", web}, {"web@docker", web}}); err != nil {
		t.Fatal(err)
	}
	want := []OrderEntry{{"web@docker", web}}
	if got := o.Load(); !reflect.DeepEqual(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
	// Dropped from the file too.
	if got := (Order{Path: o.Path}).Load(); !reflect.DeepEqual(got, want) {
		t.Errorf("reloaded order = %v, want %v", got, want)
	}
}

func TestOrderBrokenFileIsNoOrder(t *testing.T) {
	path := filepath.Join(t.TempDir(), "order.json")
	if err := os.WriteFile(path, []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := (Order{Path: path}).Load(); len(got) != 0 {
		t.Errorf("order = %v, want none", got)
	}
}
