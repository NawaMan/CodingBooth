// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package catalog collects the versioned identity of every catalog item — setup
// and install scripts, helpers, libs, asset directories, templates, extensions —
// as a manifest of (kind, name, cb-version, sha256). The cb-version is written by
// hand and says what kind of change happened; the sha256 proves that something
// changed. Check binds the two against a baseline manifest. See
// docs/CATALOG_VERSIONING.md.
package catalog

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"
)

// ManifestPath is where the generated manifest lives, relative to the repo root.
const ManifestPath = "build/catalog-manifest.tsv"

// Setup-side and template-side roots, relative to the repo root.
const (
	SetupsDir    = "variants/base/setups"
	TemplatesDir = "templates"
)

// Item kinds, in manifest order.
const (
	KindSetup     = "setup"
	KindInstall   = "install"
	KindHelper    = "helper"
	KindLib       = "lib"
	KindAssets    = "assets"
	KindTemplate  = "template"
	KindExtension = "extension"
)

var kindOrder = map[string]int{
	KindSetup: 0, KindInstall: 1, KindHelper: 2, KindLib: 3, KindAssets: 4, KindTemplate: 5, KindExtension: 6,
}

// AssetsVersionFile holds the cb-version of an asset directory, whose files
// (svg, ico, json, ...) cannot all carry a header comment.
const AssetsVersionFile = ".cb-version"

// Item is one catalog entry. Name is what a user writes: `setup go` → "go",
// `install npm` → "npm", `go+linter` → "go+linter". Path is the file that
// carries the cb-version, relative to the repo root.
type Item struct {
	Kind    string
	Name    string
	Version string
	SHA256  string
	Path    string
}

// Key identifies an item across manifests.
func (i Item) Key() string { return i.Kind + " " + i.Name }

// scriptVersionRe finds the cb-version in a script's header, whatever its
// comment syntax: `# cb-version: 1.0.0`, `// cb-version: 1.0.0`,
// `<!-- cb-version: 1.0.0 -->`.
var scriptVersionRe = regexp.MustCompile(`cb-version:\s*([^\s>*]+)`)

// scriptHeaderLines is how far into a script the cb-version is looked for.
const scriptHeaderLines = 20

// Collect walks the setups and templates trees under root and returns every
// catalog item, sorted by kind then name. A missing or malformed cb-version is
// not an error here — the item is returned with whatever was found, and Check
// reports it.
func Collect(root string) ([]Item, error) {
	var items []Item
	setups, err := collectSetups(root)
	if err != nil {
		return nil, err
	}
	items = append(items, setups...)
	tmpls, err := collectTemplates(root)
	if err != nil {
		return nil, err
	}
	items = append(items, tmpls...)
	Sort(items)
	return items, nil
}

// Sort orders items by kind, then name.
func Sort(items []Item) {
	sort.Slice(items, func(a, b int) bool {
		if items[a].Kind != items[b].Kind {
			return kindOrder[items[a].Kind] < kindOrder[items[b].Kind]
		}
		return items[a].Name < items[b].Name
	})
}

func collectSetups(root string) ([]Item, error) {
	dir := filepath.Join(root, SetupsDir)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", SetupsDir, err)
	}
	var items []Item
	for _, e := range entries {
		name := e.Name()
		rel := filepath.ToSlash(filepath.Join(SetupsDir, name))
		full := filepath.Join(dir, name)
		switch {
		case name == "future":
			// Parked, abandoned setups — not part of the catalog.
			continue
		case name == "libs" && e.IsDir():
			libs, err := collectLibs(root)
			if err != nil {
				return nil, err
			}
			items = append(items, libs...)
		case e.IsDir():
			sum, err := treeHash(full, nil)
			if err != nil {
				return nil, err
			}
			ver, _ := os.ReadFile(filepath.Join(full, AssetsVersionFile))
			items = append(items, Item{
				Kind: KindAssets, Name: name, Version: strings.TrimSpace(string(ver)),
				SHA256: sum, Path: rel + "/" + AssetsVersionFile,
			})
		default:
			kind, itemName := KindHelper, name
			if n, ok := strings.CutSuffix(name, "--setup.sh"); ok {
				kind, itemName = KindSetup, n
			} else if n, ok := strings.CutSuffix(name, "--install.sh"); ok {
				kind, itemName = KindInstall, n
			}
			item, err := scriptItem(full, rel, kind, itemName)
			if err != nil {
				return nil, err
			}
			items = append(items, item)
		}
	}
	return items, nil
}

func collectLibs(root string) ([]Item, error) {
	dir := filepath.Join(root, SetupsDir, "libs")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var items []Item
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		rel := filepath.ToSlash(filepath.Join(SetupsDir, "libs", e.Name()))
		item, err := scriptItem(filepath.Join(dir, e.Name()), rel, KindLib, e.Name())
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func scriptItem(full, rel, kind, name string) (Item, error) {
	data, err := os.ReadFile(full)
	if err != nil {
		return Item{}, err
	}
	return Item{Kind: kind, Name: name, Version: ScriptVersion(data), SHA256: hashBytes(data), Path: rel}, nil
}

// ScriptVersion returns the cb-version declared in a script's header, or "".
func ScriptVersion(data []byte) string {
	sc := bufio.NewScanner(strings.NewReader(string(data)))
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for n := 0; n < scriptHeaderLines && sc.Scan(); n++ {
		if m := scriptVersionRe.FindStringSubmatch(sc.Text()); m != nil {
			return m[1]
		}
	}
	return ""
}

func collectTemplates(root string) ([]Item, error) {
	troot := filepath.Join(root, TemplatesDir)
	cats, err := os.ReadDir(troot)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", TemplatesDir, err)
	}
	var items []Item
	for _, cat := range cats {
		if !cat.IsDir() {
			continue
		}
		tmpls, err := os.ReadDir(filepath.Join(troot, cat.Name()))
		if err != nil {
			return nil, err
		}
		for _, t := range tmpls {
			if !t.IsDir() {
				continue
			}
			got, err := collectTemplateDir(root, cat.Name(), t.Name())
			if err != nil {
				return nil, err
			}
			items = append(items, got...)
		}
	}
	return items, nil
}

// collectTemplateDir returns the template in templates/<cat>/<name>/ and its
// extensions. The template's hash covers template.toml plus every other file in
// its directory that does not belong to an extension (home-seed/, file-based
// segments, ...), so a change to any of them needs a bump.
func collectTemplateDir(root, cat, name string) ([]Item, error) {
	dir := filepath.Join(root, TemplatesDir, cat, name)
	spec := filepath.Join(dir, "template.toml")
	if _, err := os.Stat(spec); err != nil {
		return nil, nil // not a template directory
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var items []Item
	// Paths (relative to dir) that belong to an extension, not to the template.
	extOwned := map[string]bool{}
	for _, e := range entries {
		en := e.Name()
		rel := filepath.ToSlash(filepath.Join(TemplatesDir, cat, name, en))
		if ext, ok := strings.CutSuffix(en, "--extension.toml"); ok && !e.IsDir() {
			extOwned[en] = true
			item, err := tomlItem(filepath.Join(dir, en), rel, KindExtension, name+"+"+ext, nil)
			if err != nil {
				return nil, err
			}
			items = append(items, item)
			continue
		}
		if e.IsDir() {
			sub := filepath.Join(dir, en, "template.toml")
			if _, err := os.Stat(sub); err == nil {
				// Directory-form (legacy) extension: the whole subdirectory.
				extOwned[en] = true
				sum, err := treeHash(filepath.Join(dir, en), nil)
				if err != nil {
					return nil, err
				}
				item, err := tomlItem(sub, rel+"/template.toml", KindExtension, name+"+"+en, &sum)
				if err != nil {
					return nil, err
				}
				items = append(items, item)
			}
		}
	}
	sum, err := treeHash(dir, extOwned)
	if err != nil {
		return nil, err
	}
	rel := filepath.ToSlash(filepath.Join(TemplatesDir, cat, name, "template.toml"))
	item, err := tomlItem(spec, rel, KindTemplate, name, &sum)
	if err != nil {
		return nil, err
	}
	return append(items, item), nil
}

// tomlItem reads a template or extension file. hash overrides the file's own
// hash when the item spans more than one file.
func tomlItem(full, rel, kind, name string, hash *string) (Item, error) {
	data, err := os.ReadFile(full)
	if err != nil {
		return Item{}, err
	}
	ver, err := TOMLVersion(data)
	if err != nil {
		return Item{}, fmt.Errorf("%s: %w", rel, err)
	}
	sum := hashBytes(data)
	if hash != nil {
		sum = *hash
	}
	return Item{Kind: kind, Name: name, Version: ver, SHA256: sum, Path: rel}, nil
}

// TOMLVersion returns the top-level cb-version of a template or extension file.
func TOMLVersion(data []byte) (string, error) {
	var spec struct {
		CBVersion string `toml:"cb-version"`
	}
	if _, err := toml.Decode(string(data), &spec); err != nil {
		return "", err
	}
	return spec.CBVersion, nil
}

// TOMLParams returns a template's param names in declaration order — the order
// positional values (`java:21,corretto`) map onto.
func TOMLParams(data []byte) ([]string, error) {
	var spec map[string]any
	md, err := toml.Decode(string(data), &spec)
	if err != nil {
		return nil, err
	}
	var params []string
	for _, k := range md.Keys() {
		if len(k) == 2 && k[0] == "params" {
			params = append(params, k[1])
		}
	}
	return params, nil
}

func hashBytes(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// treeHash hashes a directory: when it holds exactly one file, that file's own
// hash (so a lone template.toml hashes like the file itself); otherwise the
// hash of the sorted "relpath<TAB>filehash" lines. Top-level entries named in
// skip are left out.
func treeHash(dir string, skip map[string]bool) (string, error) {
	var lines []string
	var lone string
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		if rel == "." {
			return nil
		}
		top := strings.SplitN(filepath.ToSlash(rel), "/", 2)[0]
		if skip[top] {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			return nil
		}
		data, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		lone = hashBytes(data)
		lines = append(lines, filepath.ToSlash(rel)+"\t"+lone)
		return nil
	})
	if err != nil {
		return "", err
	}
	if len(lines) == 1 {
		return lone, nil
	}
	sort.Strings(lines)
	return hashBytes([]byte(strings.Join(lines, "\n") + "\n")), nil
}
