// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// ProjectTemplatesDir returns the path to a project's local templates tree:
// <projectRoot>/.booth/templates.
func ProjectTemplatesDir(projectRoot string) string {
	if projectRoot == "" {
		projectRoot = "."
	}
	return filepath.Join(projectRoot, ".booth", "templates")
}

// LoadMergedRegistry loads the stock templates from stockDir, then merges any
// project-local templates: those under <projectRoot>/.booth/templates, and the
// setup scripts in <projectRoot>/.booth/setups that carry a `# cb-template:`
// header (see setupheader.go). Project templates with the same name override
// stock ones; a warning is written to warn (if non-nil) for each override.
//
// If projectRoot is empty, the current directory is the project. A missing or
// empty project templates or setups directory is not an error.
func LoadMergedRegistry(stockDir, projectRoot string, warn io.Writer) (*TemplateRegistry, error) {
	stock, err := LoadRegistry(stockDir)
	if err != nil {
		return nil, err
	}

	project, err := loadProjectRegistry(projectRoot, warn)
	if err != nil {
		return nil, err
	}
	if len(project.ByName) == 0 {
		return stock, nil
	}

	return MergeRegistries(stock, project, warn), nil
}

// loadProjectRegistry loads a project's own templates: flat files in
// .booth/templates, plus a template for each .booth/setups script with a
// `# cb-template:` header. When both define a name, the flat file wins — it is
// the explicit one — and the header is reported to warn.
func loadProjectRegistry(projectRoot string, warn io.Writer) (*TemplateRegistry, error) {
	project := &TemplateRegistry{ByName: make(map[string]*Template)}

	projectDir := ProjectTemplatesDir(projectRoot)
	if info, err := os.Stat(projectDir); err == nil && info.IsDir() {
		loaded, err := loadFlatProjectTemplates(projectDir)
		if err != nil {
			return nil, fmt.Errorf("loading project templates from %q: %w", projectDir, err)
		}
		project = loaded
	}

	setupsDir := ProjectSetupsDir(projectRoot)
	headers, err := LoadSetupHeaderTemplates(setupsDir)
	if err != nil {
		return nil, fmt.Errorf("loading setup templates from %q: %w", setupsDir, err)
	}
	addSetupHeaderTemplates(project, headers, warn)
	return project, nil
}

// loadFlatProjectTemplates reads .booth/templates as flat files.
//
//	<name>.toml                         template <name>
//	<template>--<ext>--extension.toml   extension <ext> of <template>
//
// A directory, a meta.toml, or any other file is an error. Every template lands
// in the project category. A template.toml needs only its segments: display-name
// falls back to the template name, and primary defaults to true unless the file
// sets it.
func loadFlatProjectTemplates(dir string) (*TemplateRegistry, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	type pendingExt struct {
		parent string
		name   string
		path   string
	}

	byName := make(map[string]*Template)
	var names []string
	var exts []pendingExt

	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		path := filepath.Join(dir, name)
		if entry.IsDir() {
			return nil, fmt.Errorf("%s is a directory; a project template is a file %s/<name>.toml", path, dir)
		}
		if name == "meta.toml" {
			return nil, fmt.Errorf("%s is not used; project templates are <name>.toml files and the category is always %q", path, ProjectCategoryDisplayName)
		}
		if strings.HasSuffix(name, "--extension.toml") {
			parent, ext, ok := splitFlatExtension(name)
			if !ok {
				return nil, fmt.Errorf("extension file %q needs a parent prefix, <template>--<ext>--extension.toml", name)
			}
			if err := validateProjectIdent(parent); err != nil {
				return nil, fmt.Errorf("extension file %q: %w", name, err)
			}
			if err := validateProjectIdent(ext); err != nil {
				return nil, fmt.Errorf("extension file %q: %w", name, err)
			}
			exts = append(exts, pendingExt{parent: parent, name: ext, path: path})
			continue
		}
		if !strings.HasSuffix(name, ".toml") {
			return nil, fmt.Errorf("%s is not a project template; expected <name>.toml or <template>--<ext>--extension.toml", name)
		}
		tname := strings.TrimSuffix(name, ".toml")
		if err := validateProjectIdent(tname); err != nil {
			return nil, fmt.Errorf("template file %q: %w", name, err)
		}
		loaded, err := loadExtensionFile(path, tname, ProjectCategoryName)
		if err != nil {
			return nil, fmt.Errorf("loading project template %q: %w", tname, err)
		}
		if _, exists := byName[tname]; exists {
			return nil, fmt.Errorf("duplicate project template %q", tname)
		}
		byName[tname] = loaded
		names = append(names, tname)
	}

	for _, ext := range exts {
		parent, ok := byName[ext.parent]
		if !ok {
			return nil, fmt.Errorf("extension %q belongs to unknown project template %q (%s.toml)", ext.name, ext.parent, ext.parent)
		}
		for _, existing := range parent.Extensions {
			if existing.Name == ext.name {
				return nil, fmt.Errorf("duplicate extension %q on project template %q", ext.name, ext.parent)
			}
		}
		loaded, err := loadExtensionFile(ext.path, ext.name, ProjectCategoryName)
		if err != nil {
			return nil, fmt.Errorf("loading extension %q of %q: %w", ext.name, ext.parent, err)
		}
		parent.Extensions = append(parent.Extensions, loaded)
	}

	project := &TemplateRegistry{ByName: make(map[string]*Template)}
	if len(byName) == 0 {
		return project, nil
	}
	cat := &Category{
		Name:        ProjectCategoryName,
		DisplayName: ProjectCategoryDisplayName,
		Order:       ProjectCategoryOrder,
	}
	for _, name := range names {
		t := byName[name]
		applyProjectDefaults(t)
		if !t.primarySet {
			t.Primary = true
		}
		slices.SortFunc(t.Extensions, func(a, b *Template) int {
			return a.DisplayOrder - b.DisplayOrder
		})
		cat.Templates = append(cat.Templates, t)
		project.ByName[t.Name] = t
	}
	slices.SortStableFunc(cat.Templates, func(a, b *Template) int {
		return a.DisplayOrder - b.DisplayOrder
	})
	project.Categories = []*Category{cat}
	return project, nil
}

// splitFlatExtension splits "<parent>--<ext>--extension.toml" on the first "--".
// A file with no parent prefix ("fancy--extension.toml") returns ok=false.
func splitFlatExtension(filename string) (parent, ext string, ok bool) {
	rest := strings.TrimSuffix(filename, "--extension.toml")
	parent, ext, ok = strings.Cut(rest, "--")
	if !ok || parent == "" || ext == "" {
		return "", "", false
	}
	return parent, ext, true
}

// validateProjectIdent accepts a template or extension name: a letter, then
// letters, digits, and single hyphens. "--" is the flat-file separator.
func validateProjectIdent(name string) error {
	if name == "" || strings.Contains(name, "--") {
		return fmt.Errorf("name %q must be a letter followed by letters, digits, and single hyphens", name)
	}
	for i, r := range name {
		letter := (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z')
		digit := r >= '0' && r <= '9'
		if i == 0 && !letter {
			return fmt.Errorf("name %q must be a letter followed by letters, digits, and single hyphens", name)
		}
		if i > 0 && !letter && !digit && r != '-' {
			return fmt.Errorf("name %q must be a letter followed by letters, digits, and single hyphens", name)
		}
	}
	return nil
}

// applyProjectDefaults moves t and its extensions into the project category and
// fills an empty display-name with the template name.
func applyProjectDefaults(t *Template) {
	t.CategoryName = ProjectCategoryName
	if t.DisplayName == "" {
		t.DisplayName = t.Name
	}
	for _, ext := range t.Extensions {
		applyProjectDefaults(ext)
	}
}

// addSetupHeaderTemplates adds header-derived templates to the project registry,
// in the project category, after any template.toml already there. A name the
// registry already has is skipped with a warning.
func addSetupHeaderTemplates(project *TemplateRegistry, headers []*Template, warn io.Writer) {
	if len(headers) == 0 {
		return
	}

	var cat *Category
	for _, c := range project.Categories {
		if c.Name == ProjectCategoryName {
			cat = c
			break
		}
	}

	added := false
	for _, h := range headers {
		if existing, ok := project.ByName[h.Name]; ok {
			if warn != nil {
				fmt.Fprintf(warn, "Warning: project template %q (category %q) overrides the cb-template header in .booth/setups/%s--setup.sh\n",
					h.Name, existing.CategoryName, h.Name)
			}
			continue
		}
		if cat == nil {
			cat = &Category{
				Name:        ProjectCategoryName,
				DisplayName: ProjectCategoryDisplayName,
				Order:       ProjectCategoryOrder,
			}
			project.Categories = append(project.Categories, cat)
		}
		if !added {
			// Keep header templates after the category's template.toml ones.
			base := 0
			for _, t := range cat.Templates {
				base = max(base, t.DisplayOrder)
			}
			for _, t := range headers {
				t.DisplayOrder += base
			}
			added = true
		}
		cat.Templates = append(cat.Templates, h)
		project.ByName[h.Name] = h
	}

	slices.SortFunc(project.Categories, func(a, b *Category) int {
		return a.Order - b.Order
	})
}

// MergeRegistries returns a new registry with project templates overlaid on stock.
// Names are global: a project template replaces any stock template of the same name.
// When warn is non-nil, each override is reported.
//
// The returned registry does not share category slices with stock or project, so
// callers may mutate Categories lists without affecting the inputs. Template
// pointers themselves are shared (read-only after load).
func MergeRegistries(stock, project *TemplateRegistry, warn io.Writer) *TemplateRegistry {
	if stock == nil {
		stock = &TemplateRegistry{ByName: make(map[string]*Template)}
	}
	if project == nil || len(project.ByName) == 0 {
		return stock
	}

	out := &TemplateRegistry{
		ByName:     make(map[string]*Template, len(stock.ByName)+len(project.ByName)),
		Categories: make([]*Category, 0, len(stock.Categories)+len(project.Categories)),
	}
	catByName := make(map[string]*Category, len(stock.Categories)+len(project.Categories))

	for _, cat := range stock.Categories {
		c := &Category{
			Name:        cat.Name,
			DisplayName: cat.DisplayName,
			Order:       cat.Order,
			Templates:   append([]*Template(nil), cat.Templates...),
		}
		out.Categories = append(out.Categories, c)
		catByName[c.Name] = c
		for _, t := range c.Templates {
			out.ByName[t.Name] = t
		}
	}

	for _, pcat := range project.Categories {
		for _, t := range pcat.Templates {
			if existing, ok := out.ByName[t.Name]; ok {
				if warn != nil {
					fmt.Fprintf(warn, "Warning: project template %q overrides built-in (category %q → %q)\n",
						t.Name, existing.CategoryName, t.CategoryName)
				}
				if oldCat := catByName[existing.CategoryName]; oldCat != nil {
					oldCat.Templates = removeTemplateNamed(oldCat.Templates, t.Name)
				}
			}

			c, ok := catByName[pcat.Name]
			if !ok {
				c = &Category{
					Name:        pcat.Name,
					DisplayName: pcat.DisplayName,
					Order:       pcat.Order,
				}
				out.Categories = append(out.Categories, c)
				catByName[pcat.Name] = c
			}
			// Avoid duplicate entries if project registry itself listed the name twice
			// (LoadRegistry already forbids that within one tree).
			c.Templates = removeTemplateNamed(c.Templates, t.Name)
			t.Local = true
			c.Templates = append(c.Templates, t)
			out.ByName[t.Name] = t
		}
	}

	// Drop categories emptied by overrides.
	var kept []*Category
	for _, c := range out.Categories {
		if len(c.Templates) == 0 {
			continue
		}
		slices.SortFunc(c.Templates, func(a, b *Template) int {
			return a.DisplayOrder - b.DisplayOrder
		})
		kept = append(kept, c)
	}
	out.Categories = kept

	slices.SortFunc(out.Categories, func(a, b *Category) int {
		if a.Order != b.Order {
			return a.Order - b.Order
		}
		if a.Name < b.Name {
			return -1
		}
		if a.Name > b.Name {
			return 1
		}
		return 0
	})

	return out
}

func removeTemplateNamed(list []*Template, name string) []*Template {
	out := list[:0]
	for _, t := range list {
		if t.Name != name {
			out = append(out, t)
		}
	}
	// zero trailing slots for GC when shrinking in place
	for i := len(out); i < len(list); i++ {
		list[i] = nil
	}
	return out
}
