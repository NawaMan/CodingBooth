// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothfile

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// DefaultRepo is the default Docker repository for CodingBooth images.
const DefaultRepo = "nawaman/codingbooth"

// DefaultVariant is the default variant when not specified.
const DefaultVariant = "base"

// DefaultVersion is the default version tag when not specified.
const DefaultVersion = "latest"

// ProjectSetupsPath is the destination path for custom setup scripts in the container.
const ProjectSetupsPath = "/home/coder/.booth/setups"

// CompilerOptions contains options for the Boothfile compiler.
type CompilerOptions struct {
	// CustomSetupsDir is the source path for custom setup scripts (e.g., ".booth/setups")
	CustomSetupsDir string

	// HasCustomSetups indicates whether the CustomSetupsDir exists and should be copied.
	// If true, the compiler will add COPY and ENV PATH instructions.
	HasCustomSetups bool

	// KnownSetupScripts is a list of known setup script names (without --setup.sh suffix).
	// Used for validation and suggestions.
	KnownSetupScripts []string

	// KnownInstallScripts is a list of known install script names (without --install.sh suffix).
	// Used for validation and suggestions.
	KnownInstallScripts []string

	// CustomSetupScripts is a list of custom setup script names from .booth/setups/.
	// These are added to the known scripts for validation.
	CustomSetupScripts []string

	// CustomInstallScripts is a list of custom install script names from .booth/setups/.
	// These are added to the known scripts for validation.
	CustomInstallScripts []string
}

// Compiler compiles parsed Boothfile commands into a Dockerfile.
type Compiler struct {
	options  CompilerOptions
	warnings []ParseError // Accumulated warnings during compilation
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

// HasWarnings returns true if there were compilation warnings.
func (cr CompileResult) HasWarnings() bool {
	return len(cr.Warnings) > 0
}

// Compile compiles a ParseResult into a Dockerfile string.
func (c *Compiler) Compile(parseResult ParseResult) CompileResult {
	// Initialize compiler warnings
	c.warnings = make([]ParseError, 0)

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
		// Handle blank lines specially - emit empty line for readability
		if cmd.Type == CommandBlank {
			sb.WriteString("\n")
			continue
		}

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

	// Append any warnings accumulated during compilation
	result.Warnings = append(result.Warnings, c.warnings...)

	return result
}

// writePrologue writes the fixed Dockerfile prologue.
func (c *Compiler) writePrologue(sb *strings.Builder) {
	prologue := `# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

`
	sb.WriteString(prologue)

	// If custom setups directory exists, copy it and prepend to PATH
	if c.options.HasCustomSetups && c.options.CustomSetupsDir != "" {
		sb.WriteString(fmt.Sprintf("COPY %s/ %s/\n", c.options.CustomSetupsDir, ProjectSetupsPath))
		sb.WriteString(fmt.Sprintf("ENV PATH=%s:$PATH\n", ProjectSetupsPath))
		sb.WriteString("\n")
	}
}

// compileCommand compiles a single command to Dockerfile instruction(s).
func (c *Compiler) compileCommand(cmd Command) (string, *ParseError) {
	switch cmd.Type {
	case CommandBlank:
		// Blank lines pass through for readability
		return "", nil

	case CommandComment:
		// Pass through comments (except syntax directive which is in prologue)
		raw := strings.TrimSpace(cmd.Raw)
		if strings.HasPrefix(raw, "# syntax=") {
			return "", nil
		}
		return raw, nil

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
// Custom setup scripts are found via PATH (project setups are prepended in prologue).
func (c *Compiler) compileSetup(cmd Command) (string, *ParseError) {
	if len(cmd.Args) == 0 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "setup command requires a tool name",
		}
	}

	toolName := cmd.Args[0]
	scriptArgs := cmd.Args[1:]

	// Validate script name if we have known scripts configured
	if c.hasKnownScripts() && !c.isKnownSetupScript(toolName) {
		// Combine all known setup scripts for suggestion
		allKnown := append([]string{}, c.options.KnownSetupScripts...)
		allKnown = append(allKnown, c.options.CustomSetupScripts...)

		hint := ""
		if suggestion := suggestScript(toolName, allKnown); suggestion != "" {
			hint = fmt.Sprintf("Did you mean '%s'?", suggestion)
		}
		c.addWarning(cmd.LineNumber, fmt.Sprintf("Unknown setup script '%s'", toolName), hint)
	}

	// Build RUN command - script is found via PATH
	runCmd := fmt.Sprintf("RUN %s--setup.sh", toolName)
	if len(scriptArgs) > 0 {
		runCmd += " " + strings.Join(scriptArgs, " ")
	}

	return runCmd, nil
}

// compileInstall compiles an install command.
// Custom install scripts are found via PATH (project setups are prepended in prologue).
func (c *Compiler) compileInstall(cmd Command) (string, *ParseError) {
	if len(cmd.Args) < 2 {
		return "", &ParseError{
			LineNumber: cmd.LineNumber,
			Message:    "install command requires a tool and at least one package",
		}
	}

	toolName := cmd.Args[0]
	packages := cmd.Args[1:]

	// Validate script name if we have known scripts configured
	if c.hasKnownScripts() && !c.isKnownInstallScript(toolName) {
		// Combine all known install scripts for suggestion
		allKnown := append([]string{}, c.options.KnownInstallScripts...)
		allKnown = append(allKnown, c.options.CustomInstallScripts...)

		hint := ""
		if suggestion := suggestScript(toolName, allKnown); suggestion != "" {
			hint = fmt.Sprintf("Did you mean '%s'?", suggestion)
		}
		c.addWarning(cmd.LineNumber, fmt.Sprintf("Unknown install script '%s'", toolName), hint)
	}

	// Build RUN command - script is found via PATH
	return fmt.Sprintf("RUN %s--install.sh %s", toolName, strings.Join(packages, " ")), nil
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

// isKnownSetupScript checks if a script name is in the known setup scripts list.
func (c *Compiler) isKnownSetupScript(name string) bool {
	// Check built-in scripts
	for _, s := range c.options.KnownSetupScripts {
		if s == name {
			return true
		}
	}
	// Check custom scripts
	for _, s := range c.options.CustomSetupScripts {
		if s == name {
			return true
		}
	}
	return false
}

// isKnownInstallScript checks if a script name is in the known install scripts list.
func (c *Compiler) isKnownInstallScript(name string) bool {
	// Check built-in scripts
	for _, s := range c.options.KnownInstallScripts {
		if s == name {
			return true
		}
	}
	// Check custom scripts
	for _, s := range c.options.CustomInstallScripts {
		if s == name {
			return true
		}
	}
	return false
}

// suggestScript returns a suggestion for a misspelled script name.
func suggestScript(name string, known []string) string {
	bestMatch := ""
	bestScore := 0

	for _, s := range known {
		score := similarityScore(name, s)
		if score > bestScore {
			bestScore = score
			bestMatch = s
		}
	}

	// Only suggest if reasonably similar (at least 50% match)
	if bestScore >= len(name)/2 {
		return bestMatch
	}
	return ""
}

// similarityScore returns a simple similarity score between two strings.
// Higher scores mean more similar.
func similarityScore(a, b string) int {
	if a == b {
		return len(a) * 2
	}

	score := 0

	// Same first letter bonus
	if len(a) > 0 && len(b) > 0 && a[0] == b[0] {
		score += 2
	}

	// Count matching characters in order
	j := 0
	for i := 0; i < len(a) && j < len(b); i++ {
		if a[i] == b[j] {
			score++
			j++
		}
	}

	// Penalize length difference
	lenDiff := len(a) - len(b)
	if lenDiff < 0 {
		lenDiff = -lenDiff
	}
	score -= lenDiff / 2

	return score
}

// addWarning adds a warning to the compiler's warning list.
func (c *Compiler) addWarning(lineNumber int, message string, hint string) {
	c.warnings = append(c.warnings, ParseError{
		LineNumber: lineNumber,
		Message:    message,
		Hint:       hint,
	})
}

// hasKnownScripts returns true if the compiler has any known scripts configured.
func (c *Compiler) hasKnownScripts() bool {
	return len(c.options.KnownSetupScripts) > 0 ||
		len(c.options.KnownInstallScripts) > 0 ||
		len(c.options.CustomSetupScripts) > 0 ||
		len(c.options.CustomInstallScripts) > 0
}

// ScanSetupsDir scans a directory for setup and install scripts.
// Returns two slices: setup script names and install script names (without suffixes).
func ScanSetupsDir(dir string) (setupScripts []string, installScripts []string) {
	if dir == "" {
		return nil, nil
	}

	info, err := os.Stat(dir)
	if err != nil || !info.IsDir() {
		return nil, nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, nil
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(name, "--setup.sh") {
			scriptName := strings.TrimSuffix(name, "--setup.sh")
			setupScripts = append(setupScripts, scriptName)
		} else if strings.HasSuffix(name, "--install.sh") {
			scriptName := strings.TrimSuffix(name, "--install.sh")
			installScripts = append(installScripts, scriptName)
		}
	}

	return setupScripts, installScripts
}

// FindBuiltinSetupsDir attempts to find the built-in setups directory.
// It checks several locations relative to the executable and working directory.
func FindBuiltinSetupsDir() string {
	// Candidates to check
	candidates := []string{}

	// Check CODINGBOOTH_SETUPS_DIR environment variable first
	if envDir := os.Getenv("CODINGBOOTH_SETUPS_DIR"); envDir != "" {
		candidates = append(candidates, envDir)
	}

	// Check relative to executable
	if exe, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exe)
		// Walk up parent directories looking for variants/base/setups
		dir := exeDir
		for i := 0; i < 6; i++ {
			candidates = append(candidates, filepath.Join(dir, "variants", "base", "setups"))
			dir = filepath.Dir(dir)
		}
	}

	// Check relative to working directory
	if wd, err := os.Getwd(); err == nil {
		// Walk up parent directories looking for variants/base/setups
		dir := wd
		for i := 0; i < 6; i++ {
			candidates = append(candidates, filepath.Join(dir, "variants", "base", "setups"))
			dir = filepath.Dir(dir)
		}
	}

	// Return first valid directory
	for _, dir := range candidates {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			// Verify it looks like a setups directory (has at least one --setup.sh file)
			if entries, err := os.ReadDir(dir); err == nil {
				for _, entry := range entries {
					if strings.HasSuffix(entry.Name(), "--setup.sh") {
						return dir
					}
				}
			}
		}
	}

	return ""
}
