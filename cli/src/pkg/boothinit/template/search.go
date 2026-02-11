// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import "strings"

// Search returns a filtered copy of the registry containing only templates
// (and extensions) that match the given term via case-insensitive prefix match
// on name, display-name, or any tag. Categories with no matches are omitted.
// If a parent template matches, all its extensions are included.
// If only extension(s) match, the parent is included with only matching extensions.
func (r *TemplateRegistry) Search(term string) *TemplateRegistry {
	lowerTerm := strings.ToLower(term)
	result := &TemplateRegistry{
		ByName: make(map[string]*Template),
	}

	for _, cat := range r.Categories {
		var matched []*Template
		for _, t := range cat.Templates {
			if matchesPrefix(t, lowerTerm) {
				// Parent matches: include with all extensions
				matched = append(matched, t)
				result.ByName[t.Name] = t
				continue
			}
			// Check extensions
			var matchedExts []*Template
			for _, ext := range t.Extensions {
				if matchesPrefix(ext, lowerTerm) {
					matchedExts = append(matchedExts, ext)
				}
			}
			if len(matchedExts) > 0 {
				// Shallow copy of the template with only matching extensions
				filtered := *t
				filtered.Extensions = matchedExts
				matched = append(matched, &filtered)
				result.ByName[t.Name] = &filtered
			}
		}
		if len(matched) > 0 {
			result.Categories = append(result.Categories, &Category{
				Name:        cat.Name,
				DisplayName: cat.DisplayName,
				Order:       cat.Order,
				Templates:   matched,
			})
		}
	}

	return result
}

// FilterPrimary returns a filtered copy of the registry containing only
// templates with Primary=true. Categories with no primary templates are omitted.
func (r *TemplateRegistry) FilterPrimary() *TemplateRegistry {
	result := &TemplateRegistry{
		ByName: make(map[string]*Template),
	}

	for _, cat := range r.Categories {
		var matched []*Template
		for _, t := range cat.Templates {
			if t.Primary {
				matched = append(matched, t)
				result.ByName[t.Name] = t
			}
		}
		if len(matched) > 0 {
			result.Categories = append(result.Categories, &Category{
				Name:        cat.Name,
				DisplayName: cat.DisplayName,
				Order:       cat.Order,
				Templates:   matched,
			})
		}
	}

	return result
}

// matchesPrefix returns true if the template's name, display-name,
// or any tag starts with the given lowercase term (case-insensitive).
func matchesPrefix(t *Template, lowerTerm string) bool {
	if strings.HasPrefix(strings.ToLower(t.Name), lowerTerm) {
		return true
	}
	if strings.HasPrefix(strings.ToLower(t.DisplayName), lowerTerm) {
		return true
	}
	for _, tag := range t.Tags {
		if strings.HasPrefix(strings.ToLower(tag), lowerTerm) {
			return true
		}
	}
	return false
}
