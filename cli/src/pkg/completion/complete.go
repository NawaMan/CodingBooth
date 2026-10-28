// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package completion

import (
	"fmt"
	"io"
	"sort"
	"strings"
)

// Directive tells the shell what to do beyond the listed items.
type Directive string

const (
	Words Directive = "words" // offer the items only
	Files Directive = "files" // complete a host file path
	Dirs  Directive = "dirs"  // complete a host directory path
)

// Item is one candidate. Desc is shown by zsh and fish; bash drops it.
type Item struct {
	Value string
	Desc  string
}

// Result is the answer for one completion request.
type Result struct {
	Items     []Item
	Directive Directive
	// NoSpace asks the shell not to add a space after the item, because more
	// of the same word follows (`--set key=`).
	NoSpace bool
}

// Context is what the words typed so far say about where to look.
type Context struct {
	Code          string // --code
	TemplatesPath string // --templates-path
	Version       string // --version
	Engine        string // --engine
}

// TemplateInfo is a template and the names of its extensions.
type TemplateInfo struct {
	Name       string
	Desc       string
	Extensions []string
}

// Sources provides the values that depend on the machine and the project.
// Each must be quick and must never download, prompt, or print; anything that
// fails just offers nothing.
type Sources interface {
	Booths(ctx Context) []string
	Templates(ctx Context) []TemplateInfo
	Profiles(ctx Context) []string
	ConfigKeys() []string
	Worktrees(ctx Context) []Item // the values --worktree takes, each described
}

// Complete answers for words: what follows the program name, the last one
// being the word under the cursor (empty when the cursor is after a space).
func Complete(root *Command, words []string, src Sources) Result {
	if len(words) == 0 {
		words = []string{""}
	}
	cur := words[len(words)-1]
	prior := words[:len(words)-1]

	cmd := root
	atStart := true // no flag or positional yet at this command level
	pos := 0
	var pending *Flag
	ctx := Context{}

	for i := 0; i < len(prior); i++ {
		w := prior[i]
		if w == "--" {
			// The rest is a command for inside the booth, or literal paths.
			return Result{Directive: Files}
		}
		if atStart {
			if sub := cmd.Sub(w); sub != nil {
				cmd, pos = sub, 0
				continue
			}
		}
		atStart = false
		if len(w) > 1 && strings.HasPrefix(w, "-") {
			name, value, hasValue := strings.Cut(w, "=")
			f := cmd.Flag(name)
			if f == nil || f.Kind == None || hasValue {
				recordContext(&ctx, name, value)
				continue
			}
			if i+1 == len(prior) {
				pending = f
				continue
			}
			i++
			recordContext(&ctx, name, prior[i])
			continue
		}
		pos++
	}

	if pending != nil {
		return values(root, pending.Kind, pending.Values, cur, "", ctx, src)
	}

	if strings.HasPrefix(cur, "--") {
		if name, partial, ok := strings.Cut(cur, "="); ok {
			if f := cmd.Flag(name); f != nil && f.Kind != None {
				return values(root, f.Kind, f.Values, partial, name+"=", ctx, src)
			}
			return Result{Directive: Words}
		}
	}
	if strings.HasPrefix(cur, "-") {
		return Result{Items: flagItems(cmd, cur), Directive: Words}
	}

	result := Result{Directive: Words}
	if atStart {
		for _, sub := range cmd.Subs {
			if !sub.Hidden && strings.HasPrefix(sub.Name, cur) {
				result.Items = append(result.Items, Item{sub.Name, sub.Desc})
			}
		}
	}
	if kind, ok := positional(cmd, pos); ok {
		more := values(root, kind, nil, cur, "", ctx, src)
		result.Items = append(result.Items, more.Items...)
		result.Directive = more.Directive
		result.NoSpace = more.NoSpace
	} else if len(result.Items) == 0 && cur == "" {
		// Nothing positional is left: the flags are what can come next.
		result.Items = flagItems(cmd, cur)
	}
	return result
}

func recordContext(ctx *Context, name, value string) {
	switch name {
	case "--code":
		ctx.Code = value
	case "--templates-path":
		ctx.TemplatesPath = value
	case "--version":
		ctx.Version = value
	case "--engine":
		ctx.Engine = value
	}
}

func positional(cmd *Command, pos int) (Kind, bool) {
	if pos < len(cmd.Args) {
		return cmd.Args[pos], true
	}
	if cmd.Variadic && len(cmd.Args) > 0 {
		return cmd.Args[len(cmd.Args)-1], true
	}
	return None, false
}

// flagItems lists the flags spelled with prefix cur. A flag's short alias is
// left out unless cur already names it, so `-<Tab>` lists each flag once.
func flagItems(cmd *Command, cur string) []Item {
	var items []Item
	for _, f := range cmd.Flags {
		hasLong := false
		for _, n := range f.Names {
			if strings.HasPrefix(n, "--") {
				hasLong = true
			}
		}
		for _, n := range f.Names {
			short := !strings.HasPrefix(n, "--")
			if short && hasLong && (cur == "" || cur == "-" || strings.HasPrefix(cur, "--")) {
				continue
			}
			if strings.HasPrefix(n, cur) {
				items = append(items, Item{Value: n})
			}
		}
	}
	return items
}

func values(root *Command, kind Kind, enum []string, cur, prefix string, ctx Context, src Sources) Result {
	words := func(list []string) Result {
		return Result{Items: matching(prefix, list, cur), Directive: Words}
	}
	switch kind {
	case File:
		return Result{Directive: Files}
	case Dir:
		return Result{Directive: Dirs}
	case Enum:
		return words(enum)
	case Booth:
		return words(sorted(src.Booths(ctx)))
	case CommandName:
		var names []string
		for _, sub := range root.Subs {
			if !sub.Hidden {
				names = append(names, sub.Name)
			}
		}
		return words(names)
	case Template:
		var items []Item
		for _, t := range src.Templates(ctx) {
			if strings.HasPrefix(t.Name, cur) {
				items = append(items, Item{prefix + t.Name, t.Desc})
			}
		}
		return Result{Items: items, Directive: Words}
	case Select:
		return selectValues(cur, prefix, ctx, src)
	case Profile:
		head, frag := splitLast(cur, ",")
		listed := map[string]bool{}
		for _, name := range strings.Split(head, ",") {
			listed[name] = true
		}
		var rest []string
		for _, name := range sorted(src.Profiles(ctx)) {
			if !listed[name] {
				rest = append(rest, name)
			}
		}
		return Result{Items: matching(prefix+head, rest, frag), Directive: Words}
	case Worktree:
		var items []Item
		for _, it := range src.Worktrees(ctx) {
			if strings.HasPrefix(it.Value, cur) {
				items = append(items, Item{prefix + it.Value, it.Desc})
			}
		}
		return Result{Items: items, Directive: Words}
	case ConfigKey:
		return words(sorted(src.ConfigKeys()))
	case ConfigSet:
		if strings.Contains(cur, "=") {
			return Result{Directive: Words}
		}
		var keys []string
		for _, k := range sorted(src.ConfigKeys()) {
			keys = append(keys, k+"=")
		}
		return Result{Items: matching(prefix, keys, cur), Directive: Words, NoSpace: true}
	}
	return Result{Directive: Words}
}

// selectValues completes one fragment of a selection like `go+vscode-ext,python`:
// a template name after a comma (or at the start), and one of that template's
// extensions after a plus.
func selectValues(cur, prefix string, ctx Context, src Sources) Result {
	cut := strings.LastIndexAny(cur, ",+")
	head, frag := cur[:cut+1], cur[cut+1:]
	templates := src.Templates(ctx)

	var items []Item
	if cut >= 0 && cur[cut] == '+' {
		group := cur[strings.LastIndex(cur[:cut], ",")+1 : cut]
		base, _, _ := strings.Cut(group, "+")
		base, _, _ = strings.Cut(base, ":")
		for _, t := range templates {
			if t.Name == base {
				for _, ext := range t.Extensions {
					if strings.HasPrefix(ext, frag) {
						items = append(items, Item{Value: prefix + head + ext})
					}
				}
			}
		}
	} else {
		for _, t := range templates {
			if strings.HasPrefix(t.Name, frag) {
				items = append(items, Item{prefix + head + t.Name, t.Desc})
			}
		}
	}
	return Result{Items: items, Directive: Words}
}

func splitLast(s, sep string) (head, last string) {
	i := strings.LastIndex(s, sep)
	return s[:i+1], s[i+1:]
}

func matching(prefix string, list []string, cur string) []Item {
	var items []Item
	for _, v := range list {
		if strings.HasPrefix(v, cur) {
			items = append(items, Item{Value: prefix + v})
		}
	}
	return items
}

func sorted(list []string) []string {
	out := append([]string(nil), list...)
	sort.Strings(out)
	return out
}

// Write prints a result in the form the shell scripts read: one item per line
// as value<TAB>description, then a last line `:<directive>` with `,nospace`
// appended when asked.
func Write(w io.Writer, r Result) {
	for _, it := range r.Items {
		if it.Desc != "" {
			fmt.Fprintf(w, "%s\t%s\n", it.Value, it.Desc)
		} else {
			fmt.Fprintln(w, it.Value)
		}
	}
	directive := r.Directive
	if directive == "" {
		directive = Words
	}
	if r.NoSpace {
		fmt.Fprintf(w, ":%s,nospace\n", directive)
	} else {
		fmt.Fprintf(w, ":%s\n", directive)
	}
}
