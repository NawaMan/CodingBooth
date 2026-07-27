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
// project-local templates from <projectRoot>/.booth/templates when that directory
// exists. Project templates with the same name override stock ones; a warning is
// written to warn (if non-nil) for each override.
//
// If projectRoot is empty, only the stock registry is returned. A missing or empty
// project templates directory is not an error.
func LoadMergedRegistry(stockDir, projectRoot string, warn io.Writer) (*TemplateRegistry, error) {
	stock, err := LoadRegistry(stockDir)
	if err != nil {
		return nil, err
	}

	projectDir := ProjectTemplatesDir(projectRoot)
	info, err := os.Stat(projectDir)
	if err != nil || !info.IsDir() {
		return stock, nil
	}

	project, err := LoadRegistry(projectDir)
	if err != nil {
		return nil, fmt.Errorf("loading project templates from %q: %w", projectDir, err)
	}
	if len(project.ByName) == 0 {
		return stock, nil
	}

	return MergeRegistries(stock, project, warn), nil
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
