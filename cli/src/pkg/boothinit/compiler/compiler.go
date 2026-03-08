// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package compiler converts a resolved selection + templates into the output model.
package compiler

import (
	"fmt"
	"slices"
	"sort"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// sourcedSegment is a segment tagged with its source name for tiebreaking.
type sourcedSegment struct {
	Order      int
	Content    string
	SourceName string
}

// Compile converts a ResolvedSelection into a BoothOutput.
//
// Merge rules:
//   - Boothfile/startup segments: concatenated by order, tiebreak by source name
//   - Config scalars (variant, port, timezone, dind, cmds): match-or-error
//   - Config arrays (run-args, build-args): combine and dedup
//   - Params: error on conflicting values for the same key
func Compile(resolved *selection.ResolvedSelection) (*output.BoothOutput, error) {
	c := &collector{
		params: make(map[string]string),
	}

	for _, st := range resolved.Templates {
		if err := c.collectTemplate(st); err != nil {
			return nil, err
		}
	}

	return c.build()
}

type collector struct {
	params        map[string]string
	paramSources  map[string]string // param name → source template
	boothfileSegs []sourcedSegment
	startupSegs   []sourcedSegment

	// match-or-error scalars
	variant        string
	variantSource  string
	port           string
	portSource     string
	timezone       string
	timezoneSource string
	dind           *bool
	dindSource     string
	cmds           []string
	cmdsSource     string

	// combine-and-dedup arrays
	runArgs   []string
	buildArgs []string

	// files
	setups   []output.FileContent
	home     []output.FileContent
	homeSeed []output.FileContent
}

func (c *collector) collectTemplate(st selection.SelectedTemplate) error {
	t := st.Template
	source := t.Name

	// Params
	if err := c.collectParams(st.ParamValues, source); err != nil {
		return err
	}

	// Segments
	c.collectSegments(t, source)

	// Config
	if err := c.collectConfig(t, source); err != nil {
		return err
	}

	// Files
	c.collectFiles(t)

	// Extensions
	for _, ext := range st.Extensions {
		extSource := source + "+" + ext.Extension.Name

		if err := c.collectParams(ext.ParamValues, extSource); err != nil {
			return err
		}

		c.collectSegments(ext.Extension, extSource)

		if err := c.collectConfig(ext.Extension, extSource); err != nil {
			return err
		}

		c.collectFiles(ext.Extension)
	}

	return nil
}

func (c *collector) collectParams(values map[string]string, source string) error {
	if c.paramSources == nil {
		c.paramSources = make(map[string]string)
	}
	for k, v := range values {
		if existing, ok := c.params[k]; ok && existing != v {
			return fmt.Errorf("param %q conflict: %q (from %s) vs %q (from %s)",
				k, existing, c.paramSources[k], v, source)
		}
		c.params[k] = v
		c.paramSources[k] = source
	}
	return nil
}

func (c *collector) collectSegments(t *tmpl.Template, source string) {
	for _, seg := range t.BoothfileSegments {
		c.boothfileSegs = append(c.boothfileSegs, sourcedSegment{
			Order: seg.Order, Content: seg.Content, SourceName: source,
		})
	}
	for _, seg := range t.StartupSegments {
		c.startupSegs = append(c.startupSegs, sourcedSegment{
			Order: seg.Order, Content: seg.Content, SourceName: source,
		})
	}
}

func (c *collector) collectConfig(t *tmpl.Template, source string) error {
	if err := c.setScalar(&c.variant, &c.variantSource, t.Variant, source, "variant"); err != nil {
		return err
	}
	if err := c.setScalar(&c.port, &c.portSource, t.Port, source, "port"); err != nil {
		return err
	}
	if err := c.setScalar(&c.timezone, &c.timezoneSource, t.Timezone, source, "timezone"); err != nil {
		return err
	}
	if t.Dind != nil {
		if err := c.setBool(&c.dind, &c.dindSource, *t.Dind, source, "dind"); err != nil {
			return err
		}
	}
	if t.Cmds != nil {
		if err := c.setSlice(&c.cmds, &c.cmdsSource, t.Cmds, source, "cmds"); err != nil {
			return err
		}
	}

	c.runArgs = append(c.runArgs, t.RunArgs...)
	c.buildArgs = append(c.buildArgs, t.BuildArgs...)

	return nil
}

func (c *collector) collectFiles(t *tmpl.Template) {
	for _, f := range t.Setups {
		c.setups = append(c.setups, output.FileContent{SourcePath: f.SourcePath, RelPath: f.RelPath, Content: f.Content})
	}
	for _, f := range t.Home {
		c.home = append(c.home, output.FileContent{SourcePath: f.SourcePath, RelPath: f.RelPath, Content: f.Content})
	}
	for _, f := range t.HomeSeed {
		c.homeSeed = append(c.homeSeed, output.FileContent{SourcePath: f.SourcePath, RelPath: f.RelPath, Content: f.Content})
	}
}

func (c *collector) setScalar(current *string, currentSource *string, value, source, field string) error {
	if value == "" {
		return nil
	}
	if *current != "" && *current != value {
		return fmt.Errorf("conflicting %s: %q (from %s) vs %q (from %s)",
			field, *current, *currentSource, value, source)
	}
	*current = value
	*currentSource = source
	return nil
}

func (c *collector) setBool(current **bool, currentSource *string, value bool, source, field string) error {
	if *current != nil && **current != value {
		return fmt.Errorf("conflicting %s: %v (from %s) vs %v (from %s)",
			field, **current, *currentSource, value, source)
	}
	*current = &value
	*currentSource = source
	return nil
}

func (c *collector) setSlice(current *[]string, currentSource *string, value []string, source, field string) error {
	if *current != nil && !sliceEqual(*current, value) {
		return fmt.Errorf("conflicting %s: %v (from %s) vs %v (from %s)",
			field, *current, *currentSource, value, source)
	}
	*current = value
	*currentSource = source
	return nil
}

func (c *collector) build() (*output.BoothOutput, error) {
	out := &output.BoothOutput{}

	// Config — always produce one
	cfg := &output.ConfigToml{
		Variant:   c.variant,
		Port:      c.port,
		Timezone:  c.timezone,
		Cmds:      c.cmds,
		RunArgs:   expandParams(dedup(c.runArgs), c.params),
		BuildArgs: dedup(c.buildArgs),
	}
	if c.dind != nil {
		cfg.Dind = *c.dind
	}
	out.Config = cfg

	// Boothfile
	boothfileBody := mergeSegments(c.boothfileSegs)
	argLines := buildArgLines(c.params)
	if argLines != "" || boothfileBody != "" {
		content := argLines + boothfileBody
		out.Boothfile = &output.BoothfileContent{Content: content}
	}

	// Startups — emit each segment as a separate file
	sortSegments(c.startupSegs)
	for _, seg := range c.startupSegs {
		name := fmt.Sprintf("%02d-%s--startup.sh", seg.Order, sanitizeName(seg.SourceName))
		content := strings.TrimRight(seg.Content, "\n") + "\n"
		out.Startups = append(out.Startups, output.FileContent{
			RelPath: name,
			Content: content,
		})
	}

	// Files
	out.Setups = c.setups
	out.Home = c.home
	out.HomeSeed = c.homeSeed

	return out, nil
}

// sortSegments sorts segments by order (tiebreak by source name).
func sortSegments(segs []sourcedSegment) {
	slices.SortFunc(segs, func(a, b sourcedSegment) int {
		if a.Order != b.Order {
			return a.Order - b.Order
		}
		if a.SourceName < b.SourceName {
			return -1
		}
		if a.SourceName > b.SourceName {
			return 1
		}
		return 0
	})
}

// mergeSegments sorts by order (tiebreak by source name) and concatenates content.
func mergeSegments(segs []sourcedSegment) string {
	if len(segs) == 0 {
		return ""
	}

	sortSegments(segs)

	var parts []string
	for _, seg := range segs {
		parts = append(parts, strings.TrimRight(seg.Content, "\n"))
	}
	return strings.Join(parts, "\n") + "\n"
}

// sanitizeName converts a source name to a safe filename component.
// e.g., "excalidraw+autostart" → "excalidraw-autostart"
func sanitizeName(name string) string {
	return strings.ReplaceAll(name, "+", "-")
}

// buildArgLines generates Boothfile ARG directives from params, sorted alphabetically.
func buildArgLines(params map[string]string) string {
	if len(params) == 0 {
		return ""
	}

	names := make([]string, 0, len(params))
	for name := range params {
		names = append(names, name)
	}
	sort.Strings(names)

	var lines []string
	for _, name := range names {
		lines = append(lines, fmt.Sprintf("arg %s=%s", name, params[name]))
	}
	return strings.Join(lines, "\n") + "\n\n"
}

// dedup removes duplicate flag-value pairs from a slice, preserving order.
// Flags like "-v" and "-e" consume the next element as their value,
// so "-v foo" and "-v bar" are treated as distinct pairs.
func dedup(items []string) []string {
	if len(items) == 0 {
		return nil
	}
	// Flags that take a following value argument
	pairedFlags := map[string]bool{"-v": true, "-e": true, "-p": true, "-l": true}

	seen := make(map[string]bool, len(items))
	var result []string
	for i := 0; i < len(items); i++ {
		if pairedFlags[items[i]] && i+1 < len(items) {
			pair := items[i] + "\x00" + items[i+1]
			if !seen[pair] {
				seen[pair] = true
				result = append(result, items[i], items[i+1])
			}
			i++ // skip value
		} else {
			if !seen[items[i]] {
				seen[items[i]] = true
				result = append(result, items[i])
			}
		}
	}
	return result
}

// expandParams replaces ${PARAM} references in string slices with their values.
func expandParams(items []string, params map[string]string) []string {
	if len(params) == 0 || len(items) == 0 {
		return items
	}
	result := make([]string, len(items))
	for i, item := range items {
		s := item
		for k, v := range params {
			s = strings.ReplaceAll(s, "${"+k+"}", v)
		}
		result[i] = s
	}
	return result
}

func sliceEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
