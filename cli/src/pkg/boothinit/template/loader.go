// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/BurntSushi/toml"
)

// DefaultSegmentOrder is the order assigned to segment files without an explicit order suffix.
const DefaultSegmentOrder = 50

// TOML deserialization structs

type metaToml struct {
	DisplayName string `toml:"display-name"`
	Order       int    `toml:"order"`
}

type specToml struct {
	DisplayName  string               `toml:"display-name"`
	DisplayDesc   string               `toml:"display-disc"`
	DisplayDetail string               `toml:"display-detail"`
	DisplayOrder  int                  `toml:"display-order"`
	Tags         []string             `toml:"tags"`
	Primary      bool                 `toml:"primary"`
	AutoSelect   *bool                `toml:"auto-select"`
	Variant      string               `toml:"variant"`
	Port         string               `toml:"port"`
	Timezone     string               `toml:"timezone"`
	Dind         *bool                `toml:"dind"`
	Sudo         *bool                `toml:"sudo"`
	Cmds         []string             `toml:"cmds"`
	BuildArgs    []string             `toml:"build-args"`
	RunArgs      []string             `toml:"run-args"`
	Requires     []string             `toml:"requires"`
	Params       map[string]paramToml `toml:"params"`
	Segments     map[string]string    `toml:"segments"`
	Files        filesToml            `toml:"files"`
	CacheFiles   []string             `toml:"cache-files"`
	CacheDirs    []string             `toml:"cache-dirs"`
}

type filesToml struct {
	HomeSeed map[string]string `toml:"home-seed"`
	Home     map[string]string `toml:"home"`
	Setups   map[string]string `toml:"setups"`
}

type paramToml struct {
	Default  string   `toml:"default"`
	Suggests []string `toml:"suggests"`
	Variadic bool     `toml:"variadic"`
}

// LoadRegistry loads all templates from the given root directory.
// The directory should contain category subdirectories, each with meta.toml
// and template subdirectories containing template.toml.
func LoadRegistry(rootDir string) (*TemplateRegistry, error) {
	entries, err := os.ReadDir(rootDir)
	if err != nil {
		return nil, fmt.Errorf("reading templates directory: %w", err)
	}

	registry := &TemplateRegistry{
		ByName: make(map[string]*Template),
	}

	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		catDir := filepath.Join(rootDir, entry.Name())
		cat, err := loadCategory(catDir, entry.Name())
		if err != nil {
			return nil, fmt.Errorf("loading category %q: %w", entry.Name(), err)
		}
		if cat == nil {
			continue // no meta.toml — skip
		}

		for _, tmpl := range cat.Templates {
			if existing, ok := registry.ByName[tmpl.Name]; ok {
				return nil, fmt.Errorf("duplicate template name %q: found in both %q and %q categories",
					tmpl.Name, existing.CategoryName, tmpl.CategoryName)
			}
			registry.ByName[tmpl.Name] = tmpl
		}

		registry.Categories = append(registry.Categories, cat)
	}

	slices.SortFunc(registry.Categories, func(a, b *Category) int {
		return a.Order - b.Order
	})

	return registry, nil
}

// loadCategory loads a single category from a directory.
// Returns nil if meta.toml doesn't exist (directory is skipped).
func loadCategory(dir, name string) (*Category, error) {
	metaPath := filepath.Join(dir, "meta.toml")
	if _, err := os.Stat(metaPath); os.IsNotExist(err) {
		return nil, nil
	}

	var meta metaToml
	if _, err := toml.DecodeFile(metaPath, &meta); err != nil {
		return nil, fmt.Errorf("parsing meta.toml: %w", err)
	}

	cat := &Category{
		Name:        name,
		DisplayName: meta.DisplayName,
		Order:       meta.Order,
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("reading category directory: %w", err)
	}

	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		tmplDir := filepath.Join(dir, entry.Name())
		tmpl, err := loadTemplateDir(tmplDir, entry.Name(), name, true)
		if err != nil {
			return nil, fmt.Errorf("loading template %q: %w", entry.Name(), err)
		}
		if tmpl == nil {
			continue // no template.toml — skip
		}
		cat.Templates = append(cat.Templates, tmpl)
	}

	slices.SortFunc(cat.Templates, func(a, b *Template) int {
		return a.DisplayOrder - b.DisplayOrder
	})

	return cat, nil
}

// loadTemplateDir loads a template or extension from a directory.
// If allowExtensions is true, subdirectories with template.toml are loaded as extensions.
// Returns nil if template.toml doesn't exist.
func loadTemplateDir(dir, name, categoryName string, allowExtensions bool) (*Template, error) {
	specPath := filepath.Join(dir, "template.toml")
	if _, err := os.Stat(specPath); os.IsNotExist(err) {
		return nil, nil
	}

	var spec specToml
	md, err := toml.DecodeFile(specPath, &spec)
	if err != nil {
		return nil, fmt.Errorf("parsing template.toml: %w", err)
	}

	tmpl := &Template{
		Name:          name,
		CategoryName:  categoryName,
		DisplayName:   spec.DisplayName,
		DisplayDesc:   spec.DisplayDesc,
		DisplayDetail: spec.DisplayDetail,
		DisplayOrder:  spec.DisplayOrder,
		Tags:          spec.Tags,
		Primary:       spec.Primary,
		AutoSelect:    spec.AutoSelect,
		Variant:       spec.Variant,
		Port:          spec.Port,
		Timezone:      spec.Timezone,
		Dind:          spec.Dind,
		Sudo:          spec.Sudo,
		Cmds:          spec.Cmds,
		BuildArgs:     spec.BuildArgs,
		RunArgs:       spec.RunArgs,
		Requires:      spec.Requires,
	}

	// Convert params, preserving declaration order from TOML
	if len(spec.Params) > 0 {
		tmpl.Params = make(map[string]Param, len(spec.Params))
		for k, v := range spec.Params {
			tmpl.Params[k] = Param{Default: v.Default, Suggests: v.Suggests, Variadic: v.Variadic}
		}
		// Extract declaration order from TOML metadata keys
		for _, key := range md.Keys() {
			if len(key) == 2 && key[0] == "params" {
				tmpl.ParamOrder = append(tmpl.ParamOrder, key[1])
			}
		}
	}

	// Load file-based segments
	fileBoothSegs, err := loadSegments(dir, "Boothfile", "")
	if err != nil {
		return nil, fmt.Errorf("loading Boothfile segments: %w", err)
	}
	fileStartupSegs, err := loadSegments(dir, "startup", ".sh")
	if err != nil {
		return nil, fmt.Errorf("loading startup segments: %w", err)
	}

	// Parse inline segments from [segments] table
	var inlineBoothSegs, inlineStartupSegs []Segment
	if len(spec.Segments) > 0 {
		inlineBoothSegs, inlineStartupSegs, err = parseInlineSegments(spec.Segments)
		if err != nil {
			return nil, fmt.Errorf("parsing inline segments: %w", err)
		}
	}

	// Merge file-based and inline segments, rejecting duplicate orders
	tmpl.BoothfileSegments, err = mergeSegments(fileBoothSegs, inlineBoothSegs)
	if err != nil {
		return nil, fmt.Errorf("merging Boothfile segments: %w", err)
	}
	tmpl.StartupSegments, err = mergeSegments(fileStartupSegs, inlineStartupSegs)
	if err != nil {
		return nil, fmt.Errorf("merging startup segments: %w", err)
	}

	// Load files from special subdirectories
	tmpl.Setups, err = collectFiles(filepath.Join(dir, "setups"))
	if err != nil {
		return nil, fmt.Errorf("loading setups/: %w", err)
	}
	tmpl.Home, err = collectFiles(filepath.Join(dir, "home"))
	if err != nil {
		return nil, fmt.Errorf("loading home/: %w", err)
	}
	tmpl.HomeSeed, err = collectFiles(filepath.Join(dir, "home-seed"))
	if err != nil {
		return nil, fmt.Errorf("loading home-seed/: %w", err)
	}

	// Parse inline files from [files] table and append to directory-based files
	if err := appendInlineFiles(spec.Files, &tmpl.Setups, &tmpl.Home, &tmpl.HomeSeed); err != nil {
		return nil, err
	}

	// Validate and assign cache-files
	for _, cf := range spec.CacheFiles {
		if err := validateFilePath(cf); err != nil {
			return nil, fmt.Errorf("invalid cache-files path %q: %w", cf, err)
		}
	}
	tmpl.CacheFiles = spec.CacheFiles

	// Validate and assign cache-dirs
	for _, cd := range spec.CacheDirs {
		if err := validateFilePath(cd); err != nil {
			return nil, fmt.Errorf("invalid cache-dirs path %q: %w", cd, err)
		}
	}
	tmpl.CacheDirs = spec.CacheDirs

	// Load extensions (subdirectories with template.toml that aren't special dirs)
	if allowExtensions {
		entries, err := os.ReadDir(dir)
		if err != nil {
			return nil, fmt.Errorf("reading template directory: %w", err)
		}
		extNames := make(map[string]bool) // track names to detect conflicts

		// Pass 1: directory-based extensions
		specialDirs := map[string]bool{"setups": true, "home": true, "home-seed": true}
		for _, entry := range entries {
			if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") || specialDirs[entry.Name()] {
				continue
			}
			extDir := filepath.Join(dir, entry.Name())
			ext, err := loadTemplateDir(extDir, entry.Name(), categoryName, false)
			if err != nil {
				return nil, fmt.Errorf("loading extension %q: %w", entry.Name(), err)
			}
			if ext == nil {
				continue
			}
			extNames[entry.Name()] = true
			tmpl.Extensions = append(tmpl.Extensions, ext)
		}

		// Pass 2: inline extension files (<name>--extension.toml)
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), "--extension.toml") {
				continue
			}
			extName := strings.TrimSuffix(entry.Name(), "--extension.toml")
			if extNames[extName] {
				return nil, fmt.Errorf("extension %q defined as both a directory and an inline file", extName)
			}
			extPath := filepath.Join(dir, entry.Name())
			ext, err := loadExtensionFile(extPath, extName, categoryName)
			if err != nil {
				return nil, fmt.Errorf("loading inline extension %q: %w", extName, err)
			}
			tmpl.Extensions = append(tmpl.Extensions, ext)
		}

		slices.SortFunc(tmpl.Extensions, func(a, b *Template) int {
			return a.DisplayOrder - b.DisplayOrder
		})
	}

	return tmpl, nil
}

// loadExtensionFile loads an extension from an inline <name>--extension.toml file.
// This is equivalent to a directory-based extension but without file-based segments,
// setup scripts, or home/home-seed files.
func loadExtensionFile(filePath, name, categoryName string) (*Template, error) {
	var spec specToml
	md, err := toml.DecodeFile(filePath, &spec)
	if err != nil {
		return nil, fmt.Errorf("parsing %s: %w", filepath.Base(filePath), err)
	}

	tmpl := &Template{
		Name:          name,
		CategoryName:  categoryName,
		DisplayName:   spec.DisplayName,
		DisplayDesc:   spec.DisplayDesc,
		DisplayDetail: spec.DisplayDetail,
		DisplayOrder:  spec.DisplayOrder,
		Tags:          spec.Tags,
		Primary:       spec.Primary,
		AutoSelect:    spec.AutoSelect,
		Variant:       spec.Variant,
		Port:          spec.Port,
		Timezone:      spec.Timezone,
		Dind:          spec.Dind,
		Sudo:          spec.Sudo,
		Cmds:          spec.Cmds,
		BuildArgs:     spec.BuildArgs,
		RunArgs:       spec.RunArgs,
		Requires:      spec.Requires,
	}

	// Convert params, preserving declaration order from TOML
	if len(spec.Params) > 0 {
		tmpl.Params = make(map[string]Param, len(spec.Params))
		for k, v := range spec.Params {
			tmpl.Params[k] = Param{Default: v.Default, Suggests: v.Suggests, Variadic: v.Variadic}
		}
		for _, key := range md.Keys() {
			if len(key) == 2 && key[0] == "params" {
				tmpl.ParamOrder = append(tmpl.ParamOrder, key[1])
			}
		}
	}

	// Parse inline segments (no file-based segments for inline extensions)
	if len(spec.Segments) > 0 {
		var err error
		tmpl.BoothfileSegments, tmpl.StartupSegments, err = parseInlineSegments(spec.Segments)
		if err != nil {
			return nil, fmt.Errorf("parsing inline segments: %w", err)
		}
	}

	// Parse inline files (no directory-based files for inline extensions)
	if err := appendInlineFiles(spec.Files, &tmpl.Setups, &tmpl.Home, &tmpl.HomeSeed); err != nil {
		return nil, err
	}

	// Validate and assign cache-files
	for _, cf := range spec.CacheFiles {
		if err := validateFilePath(cf); err != nil {
			return nil, fmt.Errorf("invalid cache-files path %q: %w", cf, err)
		}
	}
	tmpl.CacheFiles = spec.CacheFiles

	// Validate and assign cache-dirs
	for _, cd := range spec.CacheDirs {
		if err := validateFilePath(cd); err != nil {
			return nil, fmt.Errorf("invalid cache-dirs path %q: %w", cd, err)
		}
	}
	tmpl.CacheDirs = spec.CacheDirs

	return tmpl, nil
}

// mergeSegments combines file-based and inline segments into a single sorted slice.
// Returns an error if both sources contain a segment with the same order number.
func mergeSegments(fileSegs, inlineSegs []Segment) ([]Segment, error) {
	if len(fileSegs) == 0 {
		return inlineSegs, nil
	}
	if len(inlineSegs) == 0 {
		return fileSegs, nil
	}

	// Check for duplicate orders across sources
	fileOrders := make(map[int]bool, len(fileSegs))
	for _, s := range fileSegs {
		fileOrders[s.Order] = true
	}
	for _, s := range inlineSegs {
		if fileOrders[s.Order] {
			return nil, fmt.Errorf("duplicate segment order %d found in both file-based and inline sources", s.Order)
		}
	}

	merged := make([]Segment, 0, len(fileSegs)+len(inlineSegs))
	merged = append(merged, fileSegs...)
	merged = append(merged, inlineSegs...)
	slices.SortFunc(merged, func(a, b Segment) int {
		return a.Order - b.Order
	})
	return merged, nil
}

// loadSegments reads segment files matching the pattern prefix[--N]suffix from a directory.
// For example, prefix="Boothfile" suffix="" matches "Boothfile" and "Boothfile--30".
// prefix="startup" suffix=".sh" matches "startup.sh" and "startup--30.sh".
func loadSegments(dir, prefix, suffix string) ([]Segment, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, nil // directory might not exist for extensions
	}

	var segments []Segment
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		order, ok := parseSegmentOrder(entry.Name(), prefix, suffix)
		if !ok {
			continue
		}
		content, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			return nil, fmt.Errorf("reading segment %q: %w", entry.Name(), err)
		}
		segments = append(segments, Segment{Order: order, Content: string(content)})
	}

	slices.SortFunc(segments, func(a, b Segment) int {
		return a.Order - b.Order
	})

	return segments, nil
}

// parseInlineSegments extracts Boothfile and startup segments from the inline [segments] map.
// Each key must match either Boothfile[--N] or startup[--N].sh pattern.
func parseInlineSegments(segMap map[string]string) ([]Segment, []Segment, error) {
	var boothSegs, startupSegs []Segment

	for key, content := range segMap {
		if order, ok := parseSegmentOrder(key, "Boothfile", ""); ok {
			boothSegs = append(boothSegs, Segment{Order: order, Content: content})
			continue
		}
		if order, ok := parseSegmentOrder(key, "startup", ".sh"); ok {
			startupSegs = append(startupSegs, Segment{Order: order, Content: content})
			continue
		}
		return nil, nil, fmt.Errorf("unrecognized segment key %q: must match Boothfile[--N] or startup[--N].sh", key)
	}

	slices.SortFunc(boothSegs, func(a, b Segment) int {
		return a.Order - b.Order
	})
	slices.SortFunc(startupSegs, func(a, b Segment) int {
		return a.Order - b.Order
	})

	return boothSegs, startupSegs, nil
}

// parseSegmentOrder extracts the order number from a segment filename.
// Returns (order, true) if the filename matches, or (0, false) if not.
//
// Examples:
//
//	parseSegmentOrder("Boothfile", "Boothfile", "")       → (50, true)
//	parseSegmentOrder("Boothfile--30", "Boothfile", "")   → (30, true)
//	parseSegmentOrder("startup.sh", "startup", ".sh")     → (50, true)
//	parseSegmentOrder("startup--10.sh", "startup", ".sh") → (10, true)
//	parseSegmentOrder("readme.md", "Boothfile", "")       → (0, false)
func parseSegmentOrder(filename, prefix, suffix string) (int, bool) {
	if suffix != "" {
		if !strings.HasSuffix(filename, suffix) {
			return 0, false
		}
		filename = strings.TrimSuffix(filename, suffix)
	}
	if !strings.HasPrefix(filename, prefix) {
		return 0, false
	}
	rest := strings.TrimPrefix(filename, prefix)
	if rest == "" {
		return DefaultSegmentOrder, true
	}
	if !strings.HasPrefix(rest, "--") {
		return 0, false
	}
	orderStr := strings.TrimPrefix(rest, "--")
	order, err := strconv.Atoi(orderStr)
	if err != nil {
		return 0, false
	}
	return order, true
}

// validateFilePath checks that a relative path is safe for use as a target file path.
// It rejects empty paths, absolute paths, paths with ".." components, and paths
// that clean to "." (the current directory).
func validateFilePath(relPath string) error {
	if relPath == "" {
		return fmt.Errorf("empty file path")
	}
	if filepath.IsAbs(relPath) {
		return fmt.Errorf("absolute path not allowed: %s", relPath)
	}
	cleaned := filepath.Clean(relPath)
	if cleaned == "." {
		return fmt.Errorf("path resolves to current directory: %s", relPath)
	}
	for _, part := range strings.Split(cleaned, string(filepath.Separator)) {
		if part == ".." {
			return fmt.Errorf("path traversal not allowed: %s", relPath)
		}
	}
	return nil
}

// parseInlineFiles converts a map of relative-path → content into validated FileRef slices.
// Keys are sorted alphabetically for deterministic output.
func parseInlineFiles(fileMap map[string]string) ([]FileRef, error) {
	if len(fileMap) == 0 {
		return nil, nil
	}

	keys := make([]string, 0, len(fileMap))
	for k := range fileMap {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var files []FileRef
	for _, relPath := range keys {
		if err := validateFilePath(relPath); err != nil {
			return nil, fmt.Errorf("invalid file path %q: %w", relPath, err)
		}
		files = append(files, FileRef{
			RelPath: filepath.Clean(relPath),
			Content: fileMap[relPath],
		})
	}
	return files, nil
}

// appendInlineFiles parses inline file definitions from the [files] TOML table
// and appends them to the corresponding file slices.
func appendInlineFiles(files filesToml, setups, home, homeSeed *[]FileRef) error {
	inlineSetups, err := parseInlineFiles(files.Setups)
	if err != nil {
		return fmt.Errorf("parsing inline setups files: %w", err)
	}
	inlineHome, err := parseInlineFiles(files.Home)
	if err != nil {
		return fmt.Errorf("parsing inline home files: %w", err)
	}
	inlineHomeSeed, err := parseInlineFiles(files.HomeSeed)
	if err != nil {
		return fmt.Errorf("parsing inline home-seed files: %w", err)
	}
	*setups = append(*setups, inlineSetups...)
	*home = append(*home, inlineHome...)
	*homeSeed = append(*homeSeed, inlineHomeSeed...)
	return nil
}

// collectFiles recursively collects all files from a directory.
// Returns nil (not error) if the directory doesn't exist.
// RelPath is relative to baseDir.
func collectFiles(baseDir string) ([]FileRef, error) {
	if _, err := os.Stat(baseDir); os.IsNotExist(err) {
		return nil, nil
	}

	var files []FileRef
	err := filepath.Walk(baseDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		relPath, err := filepath.Rel(baseDir, path)
		if err != nil {
			return fmt.Errorf("computing relative path: %w", err)
		}
		files = append(files, FileRef{
			SourcePath: path,
			RelPath:    relPath,
		})
		return nil
	})
	if err != nil {
		return nil, err
	}
	return files, nil
}
