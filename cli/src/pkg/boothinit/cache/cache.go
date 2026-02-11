// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package cache handles downloading, caching, and extracting template zip
// files from GitHub releases.
package cache

import (
	"archive/zip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

const (
	githubRepo   = "NawaMan/CodingBooth"
	templateFile = "templates.zip"
)

// ResolveTemplatesDir returns a path to an extracted templates directory.
// It checks the local cache for a previously downloaded templates.zip,
// downloading from GitHub releases if not found. The zip is extracted
// to a temporary directory. The caller must invoke the returned cleanup
// function when done.
func ResolveTemplatesDir(version string) (string, func(), error) {
	cacheDir, err := getCacheDir()
	if err != nil {
		return "", nil, fmt.Errorf("determining cache directory: %w", err)
	}

	zipPath := filepath.Join(cacheDir, version, templateFile)

	// Download if not cached
	if _, err := os.Stat(zipPath); os.IsNotExist(err) {
		fmt.Printf("Downloading templates for version %s...\n", version)
		if err := downloadTemplatesZip(version, zipPath); err != nil {
			return "", nil, fmt.Errorf("downloading templates: %w", err)
		}
	}

	// Extract to temp dir
	tmpDir, err := os.MkdirTemp("", "cb-init-")
	if err != nil {
		return "", nil, fmt.Errorf("creating temp directory: %w", err)
	}

	cleanup := func() { os.RemoveAll(tmpDir) }

	if err := ExtractTemplatesZip(zipPath, tmpDir); err != nil {
		cleanup()
		return "", nil, fmt.Errorf("extracting templates: %w", err)
	}

	// The zip contains a top-level "templates/" directory
	templatesDir := filepath.Join(tmpDir, "templates")
	if info, err := os.Stat(templatesDir); err != nil || !info.IsDir() {
		cleanup()
		return "", nil, fmt.Errorf("extracted zip does not contain a templates/ directory")
	}

	return templatesDir, cleanup, nil
}

// downloadTemplatesZip downloads templates.zip from GitHub releases for the
// given version and saves it to destPath.
func downloadTemplatesZip(version, destPath string) error {
	url := fmt.Sprintf("https://github.com/%s/releases/download/%s/%s", githubRepo, version, templateFile)

	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("fetching %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("fetching %s: HTTP %d %s", url, resp.StatusCode, resp.Status)
	}

	// Ensure parent directory exists
	if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
		return fmt.Errorf("creating cache directory: %w", err)
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(destPath), "templates-*.zip.tmp")
	if err != nil {
		return fmt.Errorf("creating temp file: %w", err)
	}
	tmpPath := tmpFile.Name()

	if _, err := io.Copy(tmpFile, resp.Body); err != nil {
		tmpFile.Close()
		os.Remove(tmpPath)
		return fmt.Errorf("writing download: %w", err)
	}
	tmpFile.Close()

	// Atomic rename to final path
	if err := os.Rename(tmpPath, destPath); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("saving to cache: %w", err)
	}

	return nil
}

// ExtractTemplatesZip extracts a zip file to destDir with security checks.
// It rejects entries with path traversal ("../") and symbolic links.
func ExtractTemplatesZip(zipPath, destDir string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("opening zip %s: %w", zipPath, err)
	}
	defer r.Close()

	destDir, err = filepath.Abs(destDir)
	if err != nil {
		return fmt.Errorf("resolving destination path: %w", err)
	}

	for _, f := range r.File {
		// Security: reject path traversal
		if strings.Contains(f.Name, "..") {
			return fmt.Errorf("zip contains path traversal entry: %s", f.Name)
		}

		// Security: reject symbolic links
		if f.FileInfo().Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("zip contains symbolic link: %s", f.Name)
		}

		fpath := filepath.Join(destDir, f.Name)

		// Security: verify resolved path is within destination
		if !strings.HasPrefix(fpath, destDir+string(os.PathSeparator)) && fpath != destDir {
			return fmt.Errorf("zip entry escapes destination: %s", f.Name)
		}

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(fpath, 0755); err != nil {
				return fmt.Errorf("creating directory %s: %w", f.Name, err)
			}
			continue
		}

		// Create parent directories
		if err := os.MkdirAll(filepath.Dir(fpath), 0755); err != nil {
			return fmt.Errorf("creating parent directory for %s: %w", f.Name, err)
		}

		outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return fmt.Errorf("creating file %s: %w", f.Name, err)
		}

		rc, err := f.Open()
		if err != nil {
			outFile.Close()
			return fmt.Errorf("reading zip entry %s: %w", f.Name, err)
		}

		_, err = io.Copy(outFile, rc)
		outFile.Close()
		rc.Close()

		if err != nil {
			return fmt.Errorf("extracting %s: %w", f.Name, err)
		}
	}

	return nil
}

// getCacheDir returns the cache directory for codingbooth versions.
// Uses XDG_CACHE_HOME if set, otherwise ~/.cache.
func getCacheDir() (string, error) {
	cacheHome := os.Getenv("XDG_CACHE_HOME")
	if cacheHome == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		cacheHome = filepath.Join(home, ".cache")
	}
	return filepath.Join(cacheHome, "codingbooth", "versions"), nil
}
