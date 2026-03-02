// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"strings"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// runTemplate handles the "template" command and its subcommands.
func runTemplate(version string) {
	args := os.Args[2:] // skip "codingbooth" and "template"

	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		printTemplateHelp()
		if len(args) == 0 {
			os.Exit(1)
		}
		return
	}

	subCmd := args[0]
	switch subCmd {
	case "list":
		runTemplateList(version, args[1:])
	case "search":
		runTemplateSearch(version, args[1:])
	case "show":
		runTemplateShow(version, args[1:])
	case "cat":
		runTemplateCat(version, args[1:])
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown template subcommand: %s\n\n", subCmd)
		printTemplateHelp()
		os.Exit(1)
	}
}

func printTemplateHelp() {
	fmt.Println(`Usage: codingbooth template <command> [flags]

Commands:
  list                     List available templates
  search <term>            Search templates by name, description, or tag
  show <name>              Show detailed information about a template
  cat <name>               Show the code/content of a template

Flags:
  --templates-path <dir>   Use local templates directory (or set CB_TEMPLATES_PATH)
  --version <ver>          Use templates from a specific release version
  --full                   Show all templates including secondary (for list/search)
  --detail                 Show file and segment contents (for show)

Examples:
  codingbooth template list
  codingbooth template list --full
  codingbooth template search python
  codingbooth template show go
  codingbooth template show python+uv
  codingbooth template show python+uv --detail
  codingbooth template cat go`)
}

// runTemplateList handles: codingbooth template list [--templates-path <dir>] [--full]
func runTemplateList(version string, args []string) {
	flags := parseInitFlags(args)
	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()

	registry, err := tmpl.LoadRegistry(templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	if !flags.full {
		registry = registry.FilterPrimary()
	}

	tmpl.FormatRegistryList(os.Stdout, registry, true) // show auto-select extensions in list

	fmt.Println()
	fmt.Println("  * Auto-selected extension")

	if !flags.full {
		fmt.Println("\nUse --full to see all available templates.")
	}
	fmt.Println("Use 'template search <term>' to find templates by name or tag.")
	fmt.Println("Use 'template show <name>' for detailed information about a template and its extensions.")
}

// runTemplateSearch handles: codingbooth template search <term> [--templates-path <dir>] [--full]
func runTemplateSearch(version string, args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Error: 'template search' requires a search term")
		fmt.Fprintln(os.Stderr, "Usage: codingbooth template search <term>")
		os.Exit(1)
	}

	searchTerm := args[0]
	flags := parseInitFlags(args[1:])
	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()

	registry, err := tmpl.LoadRegistry(templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	filtered := registry.Search(searchTerm)

	if len(filtered.Categories) == 0 {
		fmt.Println("No templates found matching:", searchTerm)
		return
	}

	tmpl.FormatRegistryList(os.Stdout, filtered, true)
}

// runTemplateShow handles: codingbooth template show <name> [--templates-path <dir>]
func runTemplateShow(version string, args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Error: 'template show' requires a template name")
		fmt.Fprintln(os.Stderr, "Usage: codingbooth template show <name>")
		os.Exit(1)
	}

	templateName := args[0]
	flags := parseInitFlags(args[1:])
	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()

	registry, err := tmpl.LoadRegistry(templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	// Support "parent+extension" syntax (e.g. "python+uv")
	if parts := strings.SplitN(templateName, "+", 2); len(parts) == 2 {
		parent, ok := registry.ByName[parts[0]]
		if !ok {
			fmt.Fprintf(os.Stderr, "Error: template %q not found\n", parts[0])
			fmt.Fprintln(os.Stderr, "Use 'codingbooth template list' to see available templates.")
			os.Exit(1)
		}
		for _, ext := range parent.Extensions {
			if ext.Name == parts[1] {
				tmpl.FormatTemplateDetail(os.Stdout, ext, registry, flags.detail)
				return
			}
		}
		fmt.Fprintf(os.Stderr, "Error: extension %q not found in template %q\n", parts[1], parts[0])
		fmt.Fprintf(os.Stderr, "Use 'codingbooth template show %s' to see available extensions.\n", parts[0])
		os.Exit(1)
	}

	t, ok := registry.ByName[templateName]
	if !ok {
		fmt.Fprintf(os.Stderr, "Error: template %q not found\n", templateName)
		fmt.Fprintln(os.Stderr, "Use 'codingbooth template list' to see available templates.")
		os.Exit(1)
	}

	tmpl.FormatTemplateDetail(os.Stdout, t, registry, flags.detail)
}

// runTemplateCat handles: codingbooth template cat <name> [--templates-path <dir>]
func runTemplateCat(version string, args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Error: 'template cat' requires a template name")
		fmt.Fprintln(os.Stderr, "Usage: codingbooth template cat <name>")
		os.Exit(1)
	}

	templateName := args[0]
	flags := parseInitFlags(args[1:])
	templatesPath, cleanup := resolveTemplatesPath(flags, version)
	defer cleanup()

	registry, err := tmpl.LoadRegistry(templatesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading templates: %v\n", err)
		os.Exit(1)
	}

	// Support "parent+extension" syntax (e.g. "python+uv")
	if parts := strings.SplitN(templateName, "+", 2); len(parts) == 2 {
		parent, ok := registry.ByName[parts[0]]
		if !ok {
			fmt.Fprintf(os.Stderr, "Error: template %q not found\n", parts[0])
			fmt.Fprintln(os.Stderr, "Use 'codingbooth template list' to see available templates.")
			os.Exit(1)
		}
		for _, ext := range parent.Extensions {
			if ext.Name == parts[1] {
				tmpl.FormatTemplateCat(os.Stdout, ext)
				return
			}
		}
		fmt.Fprintf(os.Stderr, "Error: extension %q not found in template %q\n", parts[1], parts[0])
		fmt.Fprintf(os.Stderr, "Use 'codingbooth template show %s' to see available extensions.\n", parts[0])
		os.Exit(1)
	}

	t, ok := registry.ByName[templateName]
	if !ok {
		fmt.Fprintf(os.Stderr, "Error: template %q not found\n", templateName)
		fmt.Fprintln(os.Stderr, "Use 'codingbooth template list' to see available templates.")
		os.Exit(1)
	}

	tmpl.FormatTemplateCat(os.Stdout, t)
}
