// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package showcase

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
)

// defaultBaseURL is the CodingBooths.online host serving the showcase JSON
// API. It currently points at the dev host; override with BOOTH_SHOWCASE_URL
// (e.g. once the SaaS ships a GA domain) without a code change.
const defaultBaseURL = "https://dev.codingbooths.online"

// BaseURL returns the showcase API host to use, honoring BOOTH_SHOWCASE_URL.
func BaseURL() string {
	if v := os.Getenv("BOOTH_SHOWCASE_URL"); v != "" {
		return v
	}
	return defaultBaseURL
}

// FetchGallery fetches the cross-tenant showcase gallery (GET /show.json).
// limit and cursor are passed through as query params when non-empty.
func FetchGallery(limit, cursor string) (*GalleryResponse, error) {
	u := BaseURL() + "/show.json" + encodeQuery(limit, cursor)
	var out GalleryResponse
	if err := getJSON(u, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// FetchTenant fetches one tenant's published showcases (GET /show/{handle}.json).
func FetchTenant(handle, limit, cursor string) (*TenantResponse, error) {
	u := BaseURL() + "/show/" + url.PathEscape(handle) + ".json" + encodeQuery(limit, cursor)
	var out TenantResponse
	if err := getJSON(u, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// FetchDetail fetches one showcase's full detail (GET /show/{handle}/{slug}.json),
// pinned to a specific history entry when version is non-empty (?v=version).
func FetchDetail(handle, slug, version string) (*Detail, error) {
	u := BaseURL() + "/show/" + url.PathEscape(handle) + "/" + url.PathEscape(slug) + ".json"
	if version != "" {
		u += "?v=" + url.QueryEscape(version)
	}
	var out Detail
	if err := getJSON(u, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func encodeQuery(limit, cursor string) string {
	q := url.Values{}
	if limit != "" {
		q.Set("limit", limit)
	}
	if cursor != "" {
		q.Set("cursor", cursor)
	}
	if len(q) == 0 {
		return ""
	}
	return "?" + q.Encode()
}

func getJSON(requestURL string, out interface{}) error {
	resp, err := http.Get(requestURL)
	if err != nil {
		return fmt.Errorf("failed to fetch %s: %w", requestURL, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response from %s: %w", requestURL, err)
	}

	if resp.StatusCode != http.StatusOK {
		var apiErr struct {
			Error string `json:"error"`
		}
		_ = json.Unmarshal(body, &apiErr)
		return &APIError{StatusCode: resp.StatusCode, Code: apiErr.Error}
	}

	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("failed to parse response from %s: %w", requestURL, err)
	}
	return nil
}
