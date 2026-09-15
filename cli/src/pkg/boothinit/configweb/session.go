// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"fmt"
	"maps"
	"slices"
	"sort"
	"strings"
	"sync"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/tui"
)

// Session is the UI-agnostic config state the TUI already keeps: selection,
// params, and Config-tab fields. The Web UI mutates this; save reads it back
// as a tui.ConfigResult so the write path stays one copy.
type Session struct {
	mu sync.Mutex

	registry     *tmpl.TemplateRegistry
	hostArch     string
	selected     map[string]bool
	stringFields map[string]string
	boolFields   map[string]bool
	listFields   map[string][]string
	paramValues  map[string]string
	notification string
	warning      string
	drifted      []string
	hasLocal     bool
	baseline     sessionSnapshot
}

type sessionSnapshot struct {
	selected map[string]bool
	params   map[string]string
	strings  map[string]string
	bools    map[string]bool
	lists    map[string][]string
}

// State is the JSON the Web UI redraws from after every mutation.
type State struct {
	Selected      map[string]bool     `json:"selected"`
	StringFields  map[string]string   `json:"stringFields"`
	BoolFields    map[string]bool     `json:"boolFields"`
	ListFields    map[string][]string `json:"listFields"`
	ParamValues   map[string]string   `json:"paramValues"`
	Notification  string              `json:"notification"`
	SelectedCount int                 `json:"selectedCount"`
	Warning       string              `json:"warning"`
	Drifted       []string            `json:"drifted"`
	HasLocal      bool                `json:"hasLocal"`
	Dirty         bool                `json:"dirty"`
}

// NewSession builds session state the same way the TUI's newModel does:
// registry first, then pre-selection from flags / an existing booth.
func NewSession(registry *tmpl.TemplateRegistry, pre *tui.PreSelection, warning string, drifted []string) *Session {
	thisSession := &Session{
		registry:     registry,
		hostArch:     tmpl.HostArch(),
		selected:     make(map[string]bool),
		stringFields: make(map[string]string),
		boolFields:   make(map[string]bool),
		listFields:   make(map[string][]string),
		paramValues:  make(map[string]string),
		warning:      warning,
		drifted:      append([]string{}, drifted...),
	}
	if registry != nil {
		for _, loaded := range registry.ByName {
			if loaded != nil && loaded.Local {
				thisSession.hasLocal = true
				break
			}
		}
	}
	if pre != nil {
		for key, value := range pre.StringFields {
			if value != "" {
				thisSession.stringFields[key] = value
			}
		}
		for key, value := range pre.BoolFields {
			thisSession.boolFields[key] = value
		}
		for key, values := range pre.ListFields {
			if len(values) > 0 {
				thisSession.listFields[key] = append([]string{}, values...)
			}
		}
		for templateName := range pre.SelectedTemplates {
			thisSession.selected[templateName] = true
			if template, found := registry.ByName[templateName]; found {
				thisSession.initParamDefaults(templateName, template)
			}
		}
		for templateName, extensions := range pre.SelectedExts {
			for extensionName := range extensions {
				extKey := templateName + "/" + extensionName
				thisSession.selected[extKey] = true
				if template, found := registry.ByName[templateName]; found {
					for _, extension := range template.Extensions {
						if extension.Name == extensionName {
							thisSession.initParamDefaults(extKey, extension)
							break
						}
					}
				}
			}
		}
		for key, value := range pre.ParamValues {
			thisSession.paramValues[key] = value
		}
	}
	thisSession.baseline = thisSession.snapshot()
	return thisSession
}

// Catalog returns the registry as JSON tabs.
func (thisSession *Session) Catalog() Catalog {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()
	catalog := BuildCatalog(thisSession.registry, thisSession.hostArch)
	catalog.HasLocal = thisSession.hasLocal
	return catalog
}

// CurrentState copies the editable maps for the Web UI.
func (thisSession *Session) CurrentState() State {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()
	return thisSession.stateLocked()
}

func (thisSession *Session) stateLocked() State {
	lists := make(map[string][]string, len(thisSession.listFields))
	for key, values := range thisSession.listFields {
		lists[key] = slices.Clone(values)
	}
	selectedCount := 0
	for _, isSelected := range thisSession.selected {
		if isSelected {
			selectedCount++
		}
	}
	return State{
		Selected:      maps.Clone(thisSession.selected),
		StringFields:  maps.Clone(thisSession.stringFields),
		BoolFields:    maps.Clone(thisSession.boolFields),
		ListFields:    lists,
		ParamValues:   maps.Clone(thisSession.paramValues),
		Notification:  thisSession.notification,
		SelectedCount: selectedCount,
		Warning:       thisSession.warning,
		Drifted:       append([]string{}, thisSession.drifted...),
		HasLocal:      thisSession.hasLocal,
		Dirty:         !thisSession.snapshot().equal(thisSession.baseline),
	}
}

// Toggle selects or deselects a template/extension key ("go" or "go/linter"),
// with the same auto-select, parent, and Requires cascade as the TUI.
func (thisSession *Session) Toggle(key string) error {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()

	parent, extension, err := thisSession.lookup(key)
	if err != nil {
		return err
	}

	var notifications []string
	if thisSession.selected[key] {
		delete(thisSession.selected, key)
		if extension == nil {
			thisSession.clearParamValues(parent.Name, parent)
			for _, child := range parent.Extensions {
				extKey := parent.Name + "/" + child.Name
				delete(thisSession.selected, extKey)
				thisSession.clearParamValues(extKey, child)
			}
		} else {
			thisSession.clearParamValues(key, extension)
		}
	} else {
		thisSession.selected[key] = true
		if extension != nil {
			thisSession.initParamDefaults(key, extension)
			if !thisSession.selected[parent.Name] {
				thisSession.selected[parent.Name] = true
				thisSession.initParamDefaults(parent.Name, parent)
				notifications = append(notifications, fmt.Sprintf("Auto-selected: %s", parent.Name))
				thisSession.selectDependencies(parent, &notifications)
				thisSession.autoSelectExtensions(parent, &notifications)
			}
			for _, required := range extension.Requires {
				if !thisSession.selected[required] {
					thisSession.selectTemplateByName(required, &notifications)
				}
			}
		} else {
			thisSession.initParamDefaults(key, parent)
			if parent.UnsupportedOn(thisSession.hostArch) {
				notifications = append(notifications,
					fmt.Sprintf("⚠ %s has no %s build — it will NOT be installed (see the panel on the right)",
						parent.Name, thisSession.hostArch))
			}
			thisSession.selectDependencies(parent, &notifications)
			thisSession.autoSelectExtensions(parent, &notifications)
		}
	}
	thisSession.notification = strings.Join(notifications, " | ")
	return nil
}

// SetStringField writes a string/cycle/int Config-tab value.
func (thisSession *Session) SetStringField(key, value string) {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()
	if value == "" {
		delete(thisSession.stringFields, key)
		return
	}
	thisSession.stringFields[key] = value
	thisSession.notification = ""
}

// SetBoolField writes a checkbox Config-tab value.
func (thisSession *Session) SetBoolField(key string, value bool) {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()
	thisSession.boolFields[key] = value
	thisSession.notification = ""
}

// SetListField replaces a list Config-tab value (expose, env, mount, …).
func (thisSession *Session) SetListField(key string, values []string) {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()
	cleaned := make([]string, 0, len(values))
	for _, value := range values {
		if value = strings.TrimSpace(value); value != "" {
			cleaned = append(cleaned, value)
		}
	}
	if len(cleaned) == 0 {
		delete(thisSession.listFields, key)
	} else {
		thisSession.listFields[key] = cleaned
	}
	thisSession.notification = ""
}

// SetParam writes a template/extension parameter. An empty value removes the
// override so the default is used on save.
func (thisSession *Session) SetParam(key, value string) {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()
	if strings.TrimSpace(value) == "" {
		delete(thisSession.paramValues, key)
	} else {
		thisSession.paramValues[key] = value
	}
	thisSession.notification = ""
}

// Result is what the existing TUI save path consumes.
func (thisSession *Session) Result(saveBeside bool) *tui.ConfigResult {
	thisSession.mu.Lock()
	defer thisSession.mu.Unlock()
	return &tui.ConfigResult{
		Confirmed:    true,
		SelectDSL:    thisSession.buildSelectDSL(),
		StringFields: maps.Clone(thisSession.stringFields),
		BoolFields:   maps.Clone(thisSession.boolFields),
		ListFields:   cloneListMap(thisSession.listFields),
		SaveBeside:   saveBeside,
	}
}

func cloneListMap(source map[string][]string) map[string][]string {
	copied := make(map[string][]string, len(source))
	for key, values := range source {
		copied[key] = slices.Clone(values)
	}
	return copied
}

func (thisSession *Session) lookup(key string) (*tmpl.Template, *tmpl.Template, error) {
	if thisSession.registry == nil {
		return nil, nil, fmt.Errorf("unknown template %q", key)
	}
	if parentName, extensionName, found := strings.Cut(key, "/"); found {
		parent, ok := thisSession.registry.ByName[parentName]
		if !ok {
			return nil, nil, fmt.Errorf("unknown template %q", parentName)
		}
		for _, extension := range parent.Extensions {
			if extension.Name == extensionName {
				return parent, extension, nil
			}
		}
		return nil, nil, fmt.Errorf("unknown extension %q", key)
	}
	template, ok := thisSession.registry.ByName[key]
	if !ok {
		return nil, nil, fmt.Errorf("unknown template %q", key)
	}
	return template, nil, nil
}

func (thisSession *Session) selectTemplateByName(name string, notifications *[]string) {
	template, ok := thisSession.registry.ByName[name]
	if !ok || thisSession.selected[name] {
		return
	}
	thisSession.selected[name] = true
	thisSession.initParamDefaults(name, template)
	*notifications = append(*notifications, fmt.Sprintf("Dependency: %s", name))
	thisSession.selectDependencies(template, notifications)
	thisSession.autoSelectExtensions(template, notifications)
}

func (thisSession *Session) selectDependencies(template *tmpl.Template, notifications *[]string) {
	for _, required := range template.Requires {
		if !thisSession.selected[required] {
			thisSession.selectTemplateByName(required, notifications)
		}
	}
}

func (thisSession *Session) autoSelectExtensions(template *tmpl.Template, notifications *[]string) {
	var autoSelected []string
	for _, extension := range template.Extensions {
		if extension.AutoSelect != nil && *extension.AutoSelect {
			extKey := template.Name + "/" + extension.Name
			if !thisSession.selected[extKey] {
				thisSession.selected[extKey] = true
				thisSession.initParamDefaults(extKey, extension)
				autoSelected = append(autoSelected, extension.Name)
			}
		}
	}
	if len(autoSelected) > 0 {
		*notifications = append(*notifications, fmt.Sprintf("Auto: %s/%s", template.Name, strings.Join(autoSelected, ",")))
	}
}

func (thisSession *Session) initParamDefaults(itemKey string, template *tmpl.Template) {
	for name, param := range template.Params {
		paramKey := itemKey + ":" + name
		if _, exists := thisSession.paramValues[paramKey]; !exists {
			thisSession.paramValues[paramKey] = param.Default
		}
	}
}

func (thisSession *Session) clearParamValues(itemKey string, template *tmpl.Template) {
	for name := range template.Params {
		delete(thisSession.paramValues, itemKey+":"+name)
	}
}

func (thisSession *Session) snapshot() sessionSnapshot {
	return sessionSnapshot{
		selected: maps.Clone(thisSession.selected),
		params:   maps.Clone(thisSession.paramValues),
		strings:  maps.Clone(thisSession.stringFields),
		bools:    maps.Clone(thisSession.boolFields),
		lists:    cloneListMap(thisSession.listFields),
	}
}

func (thisSnapshot sessionSnapshot) equal(other sessionSnapshot) bool {
	return maps.Equal(thisSnapshot.selected, other.selected) &&
		maps.Equal(thisSnapshot.params, other.params) &&
		maps.Equal(thisSnapshot.strings, other.strings) &&
		maps.Equal(thisSnapshot.bools, other.bools) &&
		maps.EqualFunc(thisSnapshot.lists, other.lists, slices.Equal)
}

func orderedParamNames(template *tmpl.Template) []string {
	if len(template.ParamOrder) > 0 {
		return template.ParamOrder
	}
	names := make([]string, 0, len(template.Params))
	for name := range template.Params {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func (thisSession *Session) buildSelectDSL() string {
	if thisSession.registry == nil {
		return ""
	}
	var parts []string
	for _, category := range thisSession.registry.Categories {
		for _, template := range category.Templates {
			if !thisSession.selected[template.Name] {
				continue
			}
			item := template.Name + thisSession.buildParamDSL(template.Name, template)

			var extensions []string
			for _, extension := range template.Extensions {
				extKey := template.Name + "/" + extension.Name
				if thisSession.selected[extKey] {
					extensions = append(extensions, extension.Name+thisSession.buildParamDSL(extKey, extension))
				}
			}
			var excludes []string
			for _, extension := range template.Extensions {
				extKey := template.Name + "/" + extension.Name
				isAutoSelect := extension.AutoSelect != nil && *extension.AutoSelect
				if isAutoSelect && !thisSession.selected[extKey] {
					excludes = append(excludes, extension.Name)
				}
			}
			if len(extensions) > 0 {
				item += "+" + strings.Join(extensions, "+")
			}
			if len(excludes) > 0 {
				item += "~" + strings.Join(excludes, "~")
			}
			parts = append(parts, item)
		}
	}
	return strings.Join(parts, "/")
}

func (thisSession *Session) buildParamDSL(itemKey string, template *tmpl.Template) string {
	if len(template.Params) == 0 {
		return ""
	}
	paramNames := orderedParamNames(template)
	var values []string
	allDefault := true
	for _, name := range paramNames {
		value := thisSession.paramValues[itemKey+":"+name]
		if value == "" {
			value = template.Params[name].Default
		}
		if value != template.Params[name].Default {
			allDefault = false
		}
		values = append(values, value)
	}
	if allDefault {
		return ""
	}
	for len(values) > 0 && values[len(values)-1] == template.Params[paramNames[len(values)-1]].Default {
		values = values[:len(values)-1]
	}
	if len(values) == 0 {
		return ""
	}
	quoted := make([]string, len(values))
	for index, value := range values {
		if template.Params[paramNames[index]].Variadic {
			quoted[index] = selection.QuoteVariadic(value)
		} else {
			quoted[index] = selection.QuoteParam(value)
		}
	}
	return ":" + strings.Join(quoted, ",")
}
