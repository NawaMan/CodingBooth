// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
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
	DisplayDesc  string               `toml:"display-disc"`
	DisplayOrder int                  `toml:"display-order"`
	Tags         []string             `toml:"tags"`
	AutoSelect   *bool                `toml:"auto-select"`
	Variant      string               `toml:"variant"`
	Port         string               `toml:"port"`
	Timezone     string               `toml:"timezone"`
	Dind         *bool                `toml:"dind"`
	Cmds         []string             `toml:"cmds"`
	BuildArgs    []string             `toml:"build-args"`
	RunArgs      []string             `toml:"run-args"`
	Requires     []string             `toml:"requires"`
	Params       map[string]paramToml `toml:"params"`
}

type paramToml struct {
	Default  string   `toml:"default"`
	Suggests []string `toml:"suggests"`
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
		Name:         name,
		CategoryName: categoryName,
		DisplayName:  spec.DisplayName,
		DisplayDesc:  spec.DisplayDesc,
		DisplayOrder: spec.DisplayOrder,
		Tags:         spec.Tags,
		AutoSelect:   spec.AutoSelect,
		Variant:      spec.Variant,
		Port:         spec.Port,
		Timezone:     spec.Timezone,
		Dind:         spec.Dind,
		Cmds:         spec.Cmds,
		BuildArgs:    spec.BuildArgs,
		RunArgs:      spec.RunArgs,
		Requires:     spec.Requires,
	}

	// Convert params, preserving declaration order from TOML
	if len(spec.Params) > 0 {
		tmpl.Params = make(map[string]Param, len(spec.Params))
		for k, v := range spec.Params {
			tmpl.Params[k] = Param{Default: v.Default, Suggests: v.Suggests}
		}
		// Extract declaration order from TOML metadata keys
		for _, key := range md.Keys() {
			if len(key) == 2 && key[0] == "params" {
				tmpl.ParamOrder = append(tmpl.ParamOrder, key[1])
			}
		}
	}

	// Load Boothfile segments
	segments, err := loadSegments(dir, "Boothfile", "")
	if err != nil {
		return nil, fmt.Errorf("loading Boothfile segments: %w", err)
	}
	tmpl.BoothfileSegments = segments

	// Load startup segments
	segments, err = loadSegments(dir, "startup", ".sh")
	if err != nil {
		return nil, fmt.Errorf("loading startup segments: %w", err)
	}
	tmpl.StartupSegments = segments

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

	// Load extensions (subdirectories with template.toml that aren't special dirs)
	if allowExtensions {
		entries, err := os.ReadDir(dir)
		if err != nil {
			return nil, fmt.Errorf("reading template directory: %w", err)
		}
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
			tmpl.Extensions = append(tmpl.Extensions, ext)
		}

		slices.SortFunc(tmpl.Extensions, func(a, b *Template) int {
			return a.DisplayOrder - b.DisplayOrder
		})
	}

	return tmpl, nil
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
