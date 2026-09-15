// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package showcase

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetchGallery(t *testing.T) {
	var gotPath, gotQuery string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotQuery = r.URL.RawQuery
		fmt.Fprint(w, `{"showcases":[{"handle":"h1","slug":"s1","title":"T1","boothId":"s1","variant":"base","version":"","publishedAt":"2026-01-01T00:00:00Z","featured":true}],"nextCursor":"abc"}`)
	}))
	defer server.Close()
	t.Setenv("BOOTH_SHOWCASE_URL", server.URL)

	resp, err := FetchGallery("10", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if gotPath != "/show.json" {
		t.Errorf("path = %q, want /show.json", gotPath)
	}
	if gotQuery != "limit=10" {
		t.Errorf("query = %q, want limit=10", gotQuery)
	}
	if len(resp.Showcases) != 1 || resp.Showcases[0].Handle != "h1" {
		t.Errorf("unexpected showcases: %+v", resp.Showcases)
	}
	if resp.NextCursor == nil || *resp.NextCursor != "abc" {
		t.Errorf("unexpected nextCursor: %v", resp.NextCursor)
	}
}

func TestFetchTenant(t *testing.T) {
	var gotPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		fmt.Fprint(w, `{"handle":"NawaMan-GMail","showcases":[{"slug":"defaultj","title":"defaultj","boothId":"defaultj","variant":"desktop-xfce","version":"","publishedAt":"2026-09-12T17:27:44Z"}]}`)
	}))
	defer server.Close()
	t.Setenv("BOOTH_SHOWCASE_URL", server.URL)

	resp, err := FetchTenant("NawaMan-GMail", "", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if gotPath != "/show/NawaMan-GMail.json" {
		t.Errorf("path = %q, want /show/NawaMan-GMail.json", gotPath)
	}
	if resp.Handle != "NawaMan-GMail" || len(resp.Showcases) != 1 {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestFetchDetail(t *testing.T) {
	var gotPath, gotQuery string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotQuery = r.URL.RawQuery
		fmt.Fprint(w, `{"slug":"defaultj","title":"defaultj","boothId":"defaultj","mdFile":"README.md","mdContent":"# hi","boothfileContent":"setup jdk","configTomlContent":"variant=\"base\"","variant":"desktop-xfce","version":"","sourceType":"git","repoUrl":"https://github.com/NawaMan/DefaultJ.git","branch":"master","commit":"abc123","publishedAt":"2026-09-12T17:27:44Z","note":""}`)
	}))
	defer server.Close()
	t.Setenv("BOOTH_SHOWCASE_URL", server.URL)

	detail, err := FetchDetail("NawaMan-GMail", "defaultj", "3")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if gotPath != "/show/NawaMan-GMail/defaultj.json" {
		t.Errorf("path = %q, want /show/NawaMan-GMail/defaultj.json", gotPath)
	}
	if gotQuery != "v=3" {
		t.Errorf("query = %q, want v=3", gotQuery)
	}
	if detail.Commit != "abc123" || detail.SourceType != "git" {
		t.Errorf("unexpected detail: %+v", detail)
	}
}

func TestFetchDetailNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, `{"error":"showcase_not_found"}`)
	}))
	defer server.Close()
	t.Setenv("BOOTH_SHOWCASE_URL", server.URL)

	_, err := FetchDetail("nope", "nope", "")
	apiErr, ok := err.(*APIError)
	if !ok {
		t.Fatalf("expected *APIError, got %T (%v)", err, err)
	}
	if apiErr.StatusCode != http.StatusNotFound || apiErr.Code != "showcase_not_found" {
		t.Errorf("unexpected APIError: %+v", apiErr)
	}
}

func TestFetchDetailVersionNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, `{"error":"version_not_found"}`)
	}))
	defer server.Close()
	t.Setenv("BOOTH_SHOWCASE_URL", server.URL)

	_, err := FetchDetail("h", "s", "99")
	apiErr, ok := err.(*APIError)
	if !ok || apiErr.Code != "version_not_found" {
		t.Fatalf("expected version_not_found APIError, got %v", err)
	}
}

func TestDefaultBaseURL(t *testing.T) {
	if BaseURL() != defaultBaseURL {
		t.Errorf("BaseURL() = %q, want default %q", BaseURL(), defaultBaseURL)
	}
}
