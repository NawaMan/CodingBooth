// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// Catalog is the JSON view of a TemplateRegistry. The Web UI builds its
// category tabs from this — the same data the TUI walks in newModel.
type Catalog struct {
	HostArch   string         `json:"hostArch"`
	HasLocal   bool           `json:"hasLocal"`
	Categories []CategoryView `json:"categories"`
}

// CategoryView is one catalog tab (Languages, Tools, …).
type CategoryView struct {
	Name        string         `json:"name"`
	DisplayName string         `json:"displayName"`
	Templates   []TemplateView `json:"templates"`
}

// TemplateView is a template or extension as the Web UI renders it.
type TemplateView struct {
	Name                string         `json:"name"`
	DisplayName         string         `json:"displayName"`
	DisplayDesc         string         `json:"displayDesc"`
	DisplayDetail       string         `json:"displayDetail"`
	Primary             bool           `json:"primary"`
	Local               bool           `json:"local"`
	Requires            []string       `json:"requires"`
	UnsupportedArch     []string       `json:"unsupportedArch"`
	UnsupportedArchNote string         `json:"unsupportedArchNote"`
	UnsupportedOnHost   bool           `json:"unsupportedOnHost"`
	AutoSelect          bool           `json:"autoSelect"`
	Params              []ParamView    `json:"params"`
	Extensions          []TemplateView `json:"extensions"`
}

// ParamView is one template/extension parameter.
type ParamView struct {
	Name     string   `json:"name"`
	Default  string   `json:"default"`
	Suggests []string `json:"suggests"`
	Variadic bool     `json:"variadic"`
}

// BuildCatalog flattens a registry into the JSON the Web UI consumes.
func BuildCatalog(registry *tmpl.TemplateRegistry, hostArch string) Catalog {
	catalog := Catalog{
		HostArch:   hostArch,
		Categories: []CategoryView{},
	}
	if registry == nil {
		return catalog
	}
	for _, category := range registry.Categories {
		view := CategoryView{
			Name:        category.Name,
			DisplayName: category.DisplayName,
			Templates:   []TemplateView{},
		}
		if view.DisplayName == "" {
			view.DisplayName = category.Name
		}
		for _, template := range category.Templates {
			if template.Local {
				catalog.HasLocal = true
			}
			view.Templates = append(view.Templates, templateView(template, hostArch, false))
		}
		catalog.Categories = append(catalog.Categories, view)
	}
	if !catalog.HasLocal && registry.ByName != nil {
		for _, loaded := range registry.ByName {
			if loaded != nil && loaded.Local {
				catalog.HasLocal = true
				break
			}
		}
	}
	return catalog
}

func templateView(template *tmpl.Template, hostArch string, isExtension bool) TemplateView {
	view := TemplateView{
		Name:                template.Name,
		DisplayName:         template.DisplayName,
		DisplayDesc:         template.DisplayDesc,
		DisplayDetail:       template.DisplayDetail,
		Primary:             template.Primary,
		Local:               template.Local,
		Requires:            nonNilStrings(template.Requires),
		UnsupportedArch:     nonNilStrings(template.UnsupportedArch),
		UnsupportedArchNote: template.UnsupportedArchNote,
		UnsupportedOnHost:   template.UnsupportedOn(hostArch),
		Params:              paramViews(template),
	}
	if view.DisplayName == "" {
		view.DisplayName = template.Name
	}
	if isExtension && template.AutoSelect != nil {
		view.AutoSelect = *template.AutoSelect
	}
	if !isExtension {
		view.Extensions = []TemplateView{}
		for _, extension := range template.Extensions {
			if extension.Local {
				view.Local = view.Local || extension.Local
			}
			view.Extensions = append(view.Extensions, templateView(extension, hostArch, true))
		}
	}
	return view
}

func paramViews(template *tmpl.Template) []ParamView {
	names := orderedParamNames(template)
	views := make([]ParamView, 0, len(names))
	for _, name := range names {
		param := template.Params[name]
		views = append(views, ParamView{
			Name:     name,
			Default:  param.Default,
			Suggests: nonNilStrings(param.Suggests),
			Variadic: param.Variadic,
		})
	}
	return views
}

func nonNilStrings(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}
