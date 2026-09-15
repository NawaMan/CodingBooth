// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package showcase talks to the CodingBooths.online showcase JSON API
// (GET /show.json, /show/{handle}.json, /show/{handle}/{slug}.json) so the
// CLI can browse and import published showcases without a browser.
package showcase

// CatalogEntry is one lightweight row from a list response. Handle is empty
// and Featured is false when the entry came from a tenant-scoped listing
// (/show/{handle}.json), where both are implied by context rather than
// repeated per-entry.
type CatalogEntry struct {
	Handle      string `json:"handle,omitempty"`
	Slug        string `json:"slug"`
	Title       string `json:"title"`
	BoothID     string `json:"boothId"`
	Variant     string `json:"variant"`
	Version     string `json:"version"`
	PublishedAt string `json:"publishedAt"`
	Featured    bool   `json:"featured,omitempty"`
}

// GalleryResponse is the body of GET /show.json.
type GalleryResponse struct {
	Showcases  []CatalogEntry `json:"showcases"`
	NextCursor *string        `json:"nextCursor"`
}

// TenantResponse is the body of GET /show/{handle}.json.
type TenantResponse struct {
	Handle    string         `json:"handle"`
	Showcases []CatalogEntry `json:"showcases"`
}

// Detail is the full body of GET /show/{handle}/{slug}.json — everything
// needed to preview or recreate the source booth.
type Detail struct {
	Slug              string `json:"slug"`
	Title             string `json:"title"`
	BoothID           string `json:"boothId"`
	MdFile            string `json:"mdFile"`
	MdContent         string `json:"mdContent"`
	BoothfileContent  string `json:"boothfileContent"`
	ConfigTomlContent string `json:"configTomlContent"`
	Variant           string `json:"variant"`
	Version           string `json:"version"`
	SourceType        string `json:"sourceType"`
	RepoURL           string `json:"repoUrl"`
	Branch            string `json:"branch"`
	Commit            string `json:"commit"`
	PublishedAt       string `json:"publishedAt"`
	Note              string `json:"note"`
}

// APIError is the {"error": "..."} body the API returns on 4xx responses,
// e.g. "showcase_not_found" or "version_not_found".
type APIError struct {
	StatusCode int
	Code       string
}

func (e *APIError) Error() string {
	if e.Code != "" {
		return e.Code
	}
	return "showcase API error"
}
