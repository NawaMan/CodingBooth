// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothfile

import (
	"fmt"
	"strings"
)

// DefaultRepo is the default Docker repository for CodingBooth images.
const DefaultRepo = "nawaman/codingbooth"

// DefaultVariant is the default variant when not specified.
const DefaultVariant = "base"

// DefaultVersion is the default version tag when not specified.
const DefaultVersion = "latest"

// CompilerOptions contains options for the Boothfile compiler.
type CompilerOptions struct {
	// CustomSetupsDir is the path to check for custom setup scripts (e.g., ".booth/setups")
	// If empty, custom setup detection is disabled.
	CustomSetupsDir string

	// CheckCustomSetupExists is a function that checks if a custom setup script exists.
	// If nil, no custom setup detection is performed.
	CheckCustomSetupExists func(name string) bool
}

// Compiler compiles parsed Boothfile commands into a Dockerfile.
type Compiler struct {
	options CompilerOptions
}

// NewCompiler creates a new Boothfile compiler with default options.
func NewCompiler() *Compiler {
	return &Compiler{
		options: CompilerOptions{},
	}
}

// NewCompilerWithOptions creates a new Boothfile compiler with the given options.
func NewCompilerWithOptions(options CompilerOptions) *Compiler {
	return &Compiler{
		options: options,
	}
}

// CompileResult contains the result of compiling a Boothfile.
type CompileResult struct {
	Dockerfile string
	Errors     []ParseError
	Warnings   []ParseError
}

// HasErrors returns true if there were compilation errors.
func (cr CompileResult) HasErrors() bool {
	return len(cr.Errors) > 0
}

// Compile compiles a ParseResult into a Dockerfile string.
func (c *Compiler) Compile(parseResult ParseResult) CompileResult {
	result := CompileResult{
		Errors:   append([]ParseError{}, parseResult.Errors...),
		Warnings: append([]ParseError{}, parseResult.Warnings...),
	}

	// If there were parse errors, don't compile
	if parseResult.HasErrors() {
		return result
	}

	var sb strings.Builder

	// Write prologue
	c.writePrologue(&sb)

	// Compile each command
	for _, cmd := range parseResult.Commands {
		line, err := c.compileCommand(cmd)
		if err != nil {
			result.Errors = append(result.Errors, *err)
			continue
		}
		if line != "" {
			sb.WriteString(line)
			sb.WriteString("\n")
		}
	}

	result.Dockerfile = sb.String()
	return result
}

// writePrologue writes the fixed Dockerfile prologue.
func (c *Compiler) writePrologue(sb *strings.Builder) {
	prologue := `# syntax=docker/dockerfile:1
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

WORKDIR /opt/codingbooth/setups

`
	sb.WriteString(prologue)
}

// compileCommand compiles a single command to Dockerfile instruction(s).
func (c *Compiler) compileCommand(cmd Command) (string, *ParseError) {
	switch cmd.Type {
	case CommandComment, CommandBlank:
		// Comments and blank lines are stripped
		return "", nil

	case CommandRun:
		return c.compileRun(cmd)

	case CommandRunHeredoc:
		return c.compileRunHeredoc(cmd)

	case CommandCopy:
		return c.compileCopy(cmd)

	case CommandEnv:
		return c.compileEnv(cmd)

	case CommandWorkdir:
		return c.compileWorkdir(cmd)

	case CommandExpose:
		return c.compileExpose(cmd)

	case CommandLabel:
		return c.compileLabel(cmd)

	case CommandArg:
		return c.compileArg(cmd)

	case CommandSetup:
		return c.compileSetup(cmd)

	case CommandInstall:
		return c.compileInstall(cmd)

	case CommandDocker:
		return c.compileDocker(cmd)

	default:
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    fmt.Sprintf("Unknown command type: %v", cmd.Type),
		}
	}
}

// compileRun compiles a simple run command.
func (c *Compiler) compileRun(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "run command requires arguments",
		}
	}
	return "RUN " + strings.Join(cmd.Args, " "), nil
}

// compileRunHeredoc compiles a heredoc run command.
func (c *Compiler) compileRunHeredoc(cmd Command) (string, *ParseError) {
	switch cmd.HeredocMode {
	case HeredocVerbatim:
		return c.compileHeredocVerbatim(cmd)
	case HeredocAndJoin:
		return c.compileHeredocJoin(cmd, " && ")
	case HeredocSemiJoin:
		return c.compileHeredocJoin(cmd, "; ")
	default:
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    fmt.Sprintf("Unknown heredoc mode: %v", cmd.HeredocMode),
		}
	}
}

// compileHeredocVerbatim compiles a verbatim heredoc (pass-through to Docker).
func (c *Compiler) compileHeredocVerbatim(cmd Command) (string, *ParseError) {
	var sb strings.Builder
	sb.WriteString("RUN <<")
	sb.WriteString(cmd.HeredocDelimiter)
	sb.WriteString("\n")
	for _, line := range cmd.HeredocContent {
		sb.WriteString(line)
		sb.WriteString("\n")
	}
	sb.WriteString(cmd.HeredocDelimiter)
	return sb.String(), nil
}

// compileHeredocJoin compiles a heredoc with line joining.
func (c *Compiler) compileHeredocJoin(cmd Command, joiner string) (string, *ParseError) {
	// Process content: collapse continuations, skip blanks/comments, join
	lines := c.processHeredocContent(cmd.HeredocContent)

	if len(lines) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "heredoc block is empty after processing",
		}
	}

	// Format with continuation backslashes for readability
	if len(lines) == 1 {
		return "RUN " + lines[0], nil
	}

	var sb strings.Builder
	sb.WriteString("RUN ")
	for i, line := range lines {
		sb.WriteString(line)
		if i < len(lines)-1 {
			sb.WriteString(" \\")
			sb.WriteString("\n    ")
			sb.WriteString(strings.TrimSuffix(joiner, " "))
			sb.WriteString(" ")
		}
	}
	return sb.String(), nil
}

// processHeredocContent processes heredoc lines for && or ; joining.
func (c *Compiler) processHeredocContent(content []string) []string {
	// Step 1: Collapse line continuations
	collapsed := make([]string, 0)
	var current strings.Builder

	for _, line := range content {
		trimmed := strings.TrimRight(line, " \t")
		if strings.HasSuffix(trimmed, "\\") {
			// Continuation - append without the backslash
			current.WriteString(strings.TrimSuffix(trimmed, "\\"))
			current.WriteString(" ")
		} else {
			current.WriteString(trimmed)
			if current.Len() > 0 {
				collapsed = append(collapsed, current.String())
			}
			current.Reset()
		}
	}
	// Don't forget any remaining content
	if current.Len() > 0 {
		collapsed = append(collapsed, current.String())
	}

	// Step 2: Filter out blank lines and comments
	result := make([]string, 0)
	for _, line := range collapsed {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if strings.HasPrefix(trimmed, "#") {
			continue
		}
		result = append(result, trimmed)
	}

	return result
}

// compileCopy compiles a copy command.
func (c *Compiler) compileCopy(cmd Command) (string, *ParseError) {
	if len(cmd.Args) < 2 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "copy command requires source and destination",
		}
	}
	return "COPY " + strings.Join(cmd.Args, " "), nil
}

// compileEnv compiles an env command.
func (c *Compiler) compileEnv(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "env command requires KEY=value",
		}
	}
	return "ENV " + strings.Join(cmd.Args, " "), nil
}

// compileWorkdir compiles a workdir command.
func (c *Compiler) compileWorkdir(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "workdir command requires a path",
		}
	}
	return "WORKDIR " + cmd.Args[0], nil
}

// compileExpose compiles an expose command.
func (c *Compiler) compileExpose(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "expose command requires a port number",
		}
	}
	return "EXPOSE " + strings.Join(cmd.Args, " "), nil
}

// compileLabel compiles a label command.
func (c *Compiler) compileLabel(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "label command requires key=value",
		}
	}
	return "LABEL " + strings.Join(cmd.Args, " "), nil
}

// compileArg compiles an arg command.
func (c *Compiler) compileArg(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "arg command requires NAME or NAME=default",
		}
	}
	return "ARG " + strings.Join(cmd.Args, " "), nil
}

// compileSetup compiles a setup command.
func (c *Compiler) compileSetup(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "setup command requires a tool name",
		}
	}

	toolName := cmd.Args[0]
	scriptArgs := cmd.Args[1:]

	var lines []string

	// Check for custom setup script
	if c.options.CheckCustomSetupExists != nil && c.options.CheckCustomSetupExists(toolName) {
		// Add COPY for custom script
		srcPath := fmt.Sprintf("%s/%s--setup.sh", c.options.CustomSetupsDir, toolName)
		dstPath := fmt.Sprintf("/opt/codingbooth/setups/%s--setup.sh", toolName)
		lines = append(lines, fmt.Sprintf("COPY %s %s", srcPath, dstPath))
	}

	// Build RUN command
	runCmd := fmt.Sprintf("RUN %s--setup.sh", toolName)
	if len(scriptArgs) > 0 {
		runCmd += " " + strings.Join(scriptArgs, " ")
	}
	lines = append(lines, runCmd)

	return strings.Join(lines, "\n"), nil
}

// compileInstall compiles an install command.
func (c *Compiler) compileInstall(cmd Command) (string, *ParseError) {
	if len(cmd.Args) < 2 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "install command requires a tool and at least one package",
		}
	}

	toolName := cmd.Args[0]
	packages := cmd.Args[1:]

	var lines []string

	// Check for custom install script
	if c.options.CheckCustomSetupExists != nil && c.options.CheckCustomSetupExists(toolName) {
		// Add COPY for custom script
		srcPath := fmt.Sprintf("%s/%s--install.sh", c.options.CustomSetupsDir, toolName)
		dstPath := fmt.Sprintf("/opt/codingbooth/setups/%s--install.sh", toolName)
		lines = append(lines, fmt.Sprintf("COPY %s %s", srcPath, dstPath))
	}

	// Build RUN command
	runCmd := fmt.Sprintf("RUN %s--install.sh %s", toolName, strings.Join(packages, " "))
	lines = append(lines, runCmd)

	return strings.Join(lines, "\n"), nil
}

// compileDocker compiles a DOCKER escape hatch command.
func (c *Compiler) compileDocker(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "DOCKER escape hatch requires a Dockerfile instruction",
		}
	}
	// Pass through verbatim (DOCKER prefix already stripped by parser)
	return cmd.Args[0], nil
}

// CompileString is a convenience function to parse and compile a Boothfile string.
func CompileString(content string) CompileResult {
	parser := NewParser()
	parseResult := parser.ParseString(content)

	compiler := NewCompiler()
	return compiler.Compile(parseResult)
}
