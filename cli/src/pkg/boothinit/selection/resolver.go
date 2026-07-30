// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"sort"
	"strings"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// Resolve validates a ParsedSelection against a TemplateRegistry and produces
// a ResolvedSelection with mapped param values and auto-selected extensions.
func Resolve(parsed *ParsedSelection, registry *tmpl.TemplateRegistry) (*ResolvedSelection, error) {
	return ResolveWithOverrides(parsed, registry, nil)
}

// ResolveWithOverrides is Resolve with a set of preserved param values, keyed by
// param name. When a param is not set explicitly by the selection, an override
// (typically read back from an existing Boothfile's `arg` lines) is used instead
// of the template default — so reconfiguring a booth to add or remove one thing
// does not silently reset unrelated version pins (e.g. PLAYWRIGHT_VERSION) to
// their defaults. Explicit selection values always win over overrides.
func ResolveWithOverrides(parsed *ParsedSelection, registry *tmpl.TemplateRegistry, overrides map[string]string) (*ResolvedSelection, error) {
	selectedNames := make(map[string]bool)

	// Check for duplicate selections
	for i, pi := range parsed.Items {
		if selectedNames[pi.Name] {
			return nil, fmt.Errorf("template %q selected more than once%s", pi.Name, quoteHint(parsed.Items, i))
		}
		selectedNames[pi.Name] = true
	}

	var items []SelectedTemplate
	for i, pi := range parsed.Items {
		t, ok := registry.ByName[pi.Name]
		if !ok {
			return nil, fmt.Errorf("unknown template: %q (not in built-in catalog or .booth/templates/)%s",
				pi.Name, quoteHint(parsed.Items, i))
		}

		paramValues, err := resolveParams(t, pi.Params, overrides)
		if err != nil {
			return nil, fmt.Errorf("template %q: %w", pi.Name, err)
		}

		extensions, err := resolveExtensions(t, pi.Extensions, pi.Excludes, overrides)
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

	// Auto-select required templates (recursively)
	for changed := true; changed; {
		changed = false
		for _, item := range items {
			for _, req := range item.Template.Requires {
				if !selectedNames[req] {
					t, ok := registry.ByName[req]
					if !ok {
						return nil, fmt.Errorf("template %q requires unknown template %q", item.Template.Name, req)
					}
					paramValues, err := resolveParams(t, nil, overrides)
					if err != nil {
						return nil, fmt.Errorf("auto-selected template %q: %w", req, err)
					}
					extensions, err := resolveExtensions(t, nil, nil, overrides)
					if err != nil {
						return nil, fmt.Errorf("auto-selected template %q: %w", req, err)
					}
					items = append(items, SelectedTemplate{
						Template:    t,
						ParamValues: paramValues,
						Extensions:  extensions,
						SelectMode:  DependencySelect,
					})
					selectedNames[req] = true
					changed = true
				}
			}
			for _, ext := range item.Extensions {
				for _, req := range ext.Extension.Requires {
					if !selectedNames[req] {
						t, ok := registry.ByName[req]
						if !ok {
							return nil, fmt.Errorf("extension %q of template %q requires unknown template %q",
								ext.Extension.Name, item.Template.Name, req)
						}
						paramValues, err := resolveParams(t, nil, overrides)
						if err != nil {
							return nil, fmt.Errorf("auto-selected template %q: %w", req, err)
						}
						extensions, err := resolveExtensions(t, nil, nil, overrides)
						if err != nil {
							return nil, fmt.Errorf("auto-selected template %q: %w", req, err)
						}
						items = append(items, SelectedTemplate{
							Template:    t,
							ParamValues: paramValues,
							Extensions:  extensions,
							SelectMode:  DependencySelect,
						})
						selectedNames[req] = true
						changed = true
					}
				}
			}
		}
	}

	return &ResolvedSelection{Templates: items}, nil
}

// quoteHint returns advice to quote a param value when the item at idx looks like
// a fragment of one rather than a template someone meant to select.
//
// An unquoted "/" inside a param value splits the selection, so
// "go+go-pkg:github.com/user/tool@latest" arrives here as the template go plus the
// templates "user" and "tool@latest" — reported as unknown or, when a path repeats
// a segment, as selected twice. Neither message says anything about the "/" that
// caused it, which is the one thing worth saying. The signal is that some earlier
// item carried params at all: without a param list open, a "/" is simply a
// separator and the name really is wrong.
func quoteHint(items []ParsedItem, idx int) string {
	for i := 0; i < idx; i++ {
		if hasParams(items[i]) {
			return "\n  A \"/\" inside a param value has to be quoted, or it separates templates:" +
				"\n    --select 'go+go-pkg:\"github.com/user/tool@latest\"'"
		}
	}
	return ""
}

// hasParams reports whether an item or any of its extensions was given params.
func hasParams(item ParsedItem) bool {
	if len(item.Params) > 0 {
		return true
	}
	for _, ext := range item.Extensions {
		if len(ext.Params) > 0 {
			return true
		}
	}
	return false
}

// resolveParams maps positional CLI params to named template params.
// Param names follow declaration order from template.toml, falling back to
// alphabetical order if declaration order is not available.
// Unspecified params fall back to an override (a preserved value from an
// existing Boothfile) when one exists for that param name, otherwise to the
// template default.
func resolveParams(t *tmpl.Template, positional []string, overrides map[string]string) (map[string]string, error) {
	paramNames := orderedParamNames(t)

	// Check if the last param is variadic
	lastIsVariadic := false
	if len(paramNames) > 0 {
		lastName := paramNames[len(paramNames)-1]
		if t.Params[lastName].Variadic {
			lastIsVariadic = true
		}
	}

	if !lastIsVariadic && len(positional) > len(paramNames) {
		return nil, fmt.Errorf("too many parameters: got %d, template has %d", len(positional), len(paramNames))
	}

	values := make(map[string]string, len(paramNames))
	for i, name := range paramNames {
		isLast := i == len(paramNames)-1
		if isLast && lastIsVariadic {
			// Variadic: absorb all remaining positional values, canonicalized
			// (deduped + sorted) so the output is stable regardless of input
			// order. Variadic params are package lists where order is not
			// significant to the installer, so a canonical form keeps Boothfiles
			// deterministic across the TUI, CLI, and recipe entry points.
			if i < len(positional) {
				values[name] = CanonicalizeVariadic(positional[i:])
			} else if ov, ok := overrides[name]; ok && isPin(ov, t.Params[name].Default, overrides) {
				values[name] = ov
			} else {
				values[name] = t.Params[name].Default
			}
		} else {
			if i < len(positional) && positional[i] != "" {
				values[name] = positional[i]
			} else if ov, ok := overrides[name]; ok && isPin(ov, t.Params[name].Default, overrides) {
				values[name] = ov
			} else {
				values[name] = t.Params[name].Default
			}
		}
	}

	return values, nil
}

// isPin reports whether an override carried over from an existing Boothfile is a value
// the user chose, rather than one the previous generation derived.
//
// Overrides come from the Boothfile's `arg` lines, which hold resolved values. A default
// that follows another param ("${SSH_PORT}") therefore arrives as a number, and a plain
// string comparison against the default cannot tell "the user pinned 2200" from "2200 is
// what ${SSH_PORT} resolved to last time". Re-resolving the default against those same
// old args reconstructs the derived value: if the override matches it, it is derived and
// must be dropped so it re-derives from the new selection — otherwise moving a service
// port would leave the published host port behind on the port the service used to listen on.
func isPin(override, dflt string, oldArgs map[string]string) bool {
	return override != tmpl.ExpandRefs(dflt, oldArgs)
}

// CanonicalizeVariadic dedups (exact match, whitespace-trimmed) and sorts the
// values of a variadic param, returning them comma-joined. Blank entries are
// dropped. Order is not significant for the package managers these params feed,
// so a canonical form keeps the generated Boothfile stable regardless of how
// (or in what order) the packages were entered.
func CanonicalizeVariadic(values []string) string {
	seen := make(map[string]bool, len(values))
	out := make([]string, 0, len(values))
	for _, v := range values {
		v = strings.TrimSpace(v)
		if v == "" || seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
	}
	sort.Strings(out)
	return strings.Join(out, ",")
}

// resolveExtensions resolves extension selections, including auto-selected ones.
// Extensions listed in excludes are skipped even if auto-selected.
func resolveExtensions(t *tmpl.Template, explicit []ParsedExtension, excludes []string, overrides map[string]string) ([]SelectedExtension, error) {
	extByName := make(map[string]*tmpl.Template, len(t.Extensions))
	for _, ext := range t.Extensions {
		extByName[ext.Name] = ext
	}

	// Build exclude set and validate excluded names exist as extensions
	excludeSet := make(map[string]bool, len(excludes))
	for _, excName := range excludes {
		if _, ok := extByName[excName]; !ok {
			return nil, fmt.Errorf("unknown extension %q to exclude", excName)
		}
		excludeSet[excName] = true
	}

	// Validate: cannot both include (+) and exclude (~) the same extension
	for _, pe := range explicit {
		if excludeSet[pe.Name] {
			return nil, fmt.Errorf("extension %q is both included (+) and excluded (~)", pe.Name)
		}
	}

	selected := make(map[string]bool)
	var result []SelectedExtension

	// Auto-select extensions (skip excluded ones)
	for _, ext := range t.Extensions {
		if ext.AutoSelect != nil && *ext.AutoSelect {
			if excludeSet[ext.Name] {
				continue
			}
			paramValues, err := resolveParams(ext, nil, overrides)
			if err != nil {
				return nil, fmt.Errorf("auto-selected extension %q: %w", ext.Name, err)
			}
			result = append(result, SelectedExtension{
				Extension:   ext,
				ParamValues: paramValues,
				SelectMode:  AutoSelected,
			})
			selected[ext.Name] = true
		}
	}

	// Add explicit extensions
	for _, pe := range explicit {
		if selected[pe.Name] {
			continue // already auto-selected
		}
		ext, ok := extByName[pe.Name]
		if !ok {
			return nil, fmt.Errorf("unknown extension %q", pe.Name) // parent may be stock or project-local
		}
		paramValues, err := resolveParams(ext, pe.Params, overrides)
		if err != nil {
			return nil, fmt.Errorf("extension %q: %w", pe.Name, err)
		}
		result = append(result, SelectedExtension{
			Extension:   ext,
			ParamValues: paramValues,
			SelectMode:  ExplicitSelect,
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
