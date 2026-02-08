// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"sort"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// Resolve validates a ParsedSelection against a TemplateRegistry and produces
// a ResolvedSelection with mapped param values and auto-selected extensions.
func Resolve(parsed *ParsedSelection, registry *tmpl.TemplateRegistry) (*ResolvedSelection, error) {
	selectedNames := make(map[string]bool)

	// Check for duplicate selections
	for _, pi := range parsed.Items {
		if selectedNames[pi.Name] {
			return nil, fmt.Errorf("template %q selected more than once", pi.Name)
		}
		selectedNames[pi.Name] = true
	}

	var items []SelectedTemplate
	for _, pi := range parsed.Items {
		t, ok := registry.ByName[pi.Name]
		if !ok {
			return nil, fmt.Errorf("unknown template: %q", pi.Name)
		}

		paramValues, err := resolveParams(t, pi.Params)
		if err != nil {
			return nil, fmt.Errorf("template %q: %w", pi.Name, err)
		}

		extensions, err := resolveExtensions(t, pi.Extensions)
		if err != nil {
			return nil, fmt.Errorf("template %q: %w", pi.Name, err)
		}

		items = append(items, SelectedTemplate{
			Template:    t,
			ParamValues: paramValues,
			Extensions:  extensions,
			SelectMode:  ExplicitSelect,
		})
	}

	// Validate requires
	for _, item := range items {
		for _, req := range item.Template.Requires {
			if !selectedNames[req] {
				return nil, fmt.Errorf("template %q requires %q which is not selected", item.Template.Name, req)
			}
		}
	}

	return &ResolvedSelection{Templates: items}, nil
}

// resolveParams maps positional CLI params to named template params.
// Param names follow declaration order from template.toml, falling back to
// alphabetical order if declaration order is not available.
// Unspecified params use their default values.
func resolveParams(t *tmpl.Template, positional []string) (map[string]string, error) {
	paramNames := orderedParamNames(t)

	if len(positional) > len(paramNames) {
		return nil, fmt.Errorf("too many parameters: got %d, template has %d", len(positional), len(paramNames))
	}

	values := make(map[string]string, len(paramNames))
	for i, name := range paramNames {
		if i < len(positional) && positional[i] != "" {
			values[name] = positional[i]
		} else {
			values[name] = t.Params[name].Default
		}
	}

	return values, nil
}

// resolveExtensions resolves extension selections, including auto-selected ones.
func resolveExtensions(t *tmpl.Template, explicit []string) ([]SelectedExtension, error) {
	extByName := make(map[string]*tmpl.Template, len(t.Extensions))
	for _, ext := range t.Extensions {
		extByName[ext.Name] = ext
	}

	selected := make(map[string]bool)
	var result []SelectedExtension

	// Auto-select extensions
	for _, ext := range t.Extensions {
		if ext.AutoSelect != nil && *ext.AutoSelect {
			result = append(result, SelectedExtension{
				Extension:  ext,
				SelectMode: AutoSelected,
			})
			selected[ext.Name] = true
		}
	}

	// Add explicit extensions
	for _, extName := range explicit {
		if selected[extName] {
			continue // already auto-selected
		}
		ext, ok := extByName[extName]
		if !ok {
			return nil, fmt.Errorf("unknown extension %q", extName)
		}
		result = append(result, SelectedExtension{
			Extension:  ext,
			SelectMode: ExplicitSelect,
		})
	}

	return result, nil
}

// orderedParamNames returns param names in declaration order from template.toml.
// Falls back to alphabetical order if ParamOrder is not set.
func orderedParamNames(t *tmpl.Template) []string {
	if len(t.ParamOrder) > 0 {
		return t.ParamOrder
	}
	names := make([]string, 0, len(t.Params))
	for name := range t.Params {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
