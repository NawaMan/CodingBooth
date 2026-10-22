// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package completion

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/cache"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// boothListTimeout bounds the engine query behind booth-name completion. A
// stuck engine must not hang the shell; it only loses the names.
const boothListTimeout = 3 * time.Second

// LiveSources reads the real machine and project.
type LiveSources struct {
	// Version is the binary's own version: the catalog to read when the words
	// name no --version or --templates-path.
	Version string
}

func (s LiveSources) Booths(ctx Context) []string {
	args := []string{"--name-only"}
	if ctx.Engine != "" {
		args = append(args, "--engine", ctx.Engine)
	}
	done := make(chan []string, 1)
	go func() {
		var out bytes.Buffer
		if err := lifecycle.List(args, &out, io.Discard); err != nil {
			done <- nil
			return
		}
		done <- strings.Fields(out.String())
	}()
	select {
	case names := <-done:
		return names
	case <-time.After(boothListTimeout):
		return nil
	}
}

func (s LiveSources) Templates(ctx Context) []TemplateInfo {
	stock := ctx.TemplatesPath
	if stock == "" {
		stock = os.Getenv("CB_TEMPLATES_PATH")
	}
	if stock == "" {
		version := ctx.Version
		if version == "" {
			version = s.Version
		}
		dir, cleanup, err := cache.ResolveCachedTemplatesDir(version)
		if err != nil {
			return nil
		}
		defer cleanup()
		stock = dir
	}

	registry, err := tmpl.LoadMergedRegistry(stock, projectRoot(ctx), io.Discard)
	if err != nil {
		return nil
	}
	var infos []TemplateInfo
	for _, category := range registry.Categories {
		for _, t := range category.Templates {
			info := TemplateInfo{Name: t.Name, Desc: t.DisplayDesc}
			for _, ext := range t.Extensions {
				info.Extensions = append(info.Extensions, ext.Name)
			}
			infos = append(infos, info)
		}
	}
	return infos
}

// Profiles are the names of .booth/<name>--config.toml and .booth/.<name>--env.
func (s LiveSources) Profiles(ctx Context) []string {
	boothDir := filepath.Join(projectRoot(ctx), ".booth")
	seen := map[string]bool{}
	var names []string
	add := func(pattern, prefix, suffix string) {
		matches, _ := filepath.Glob(filepath.Join(boothDir, pattern))
		for _, m := range matches {
			name := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(m), prefix), suffix)
			if name != "" && !seen[name] {
				seen[name] = true
				names = append(names, name)
			}
		}
	}
	add("*--config.toml", "", "--config.toml")
	add(".*--env", ".", "--env")
	return names
}

// ConfigKeys are the keys a config.toml is read for.
func (s LiveSources) ConfigKeys() []string {
	var keys []string
	for key, spec := range appctx.ConfigKeys() {
		if spec.Read {
			keys = append(keys, key)
		}
	}
	return keys
}

func projectRoot(ctx Context) string {
	if ctx.Code != "" {
		// The shell hands the word over as typed, so a ~ is still literal.
		if rest, ok := strings.CutPrefix(ctx.Code, "~/"); ok {
			if home, err := os.UserHomeDir(); err == nil {
				return filepath.Join(home, rest)
			}
		}
		return ctx.Code
	}
	if wd, err := os.Getwd(); err == nil {
		return wd
	}
	return "."
}
