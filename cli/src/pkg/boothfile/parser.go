// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package boothfile provides parsing and compilation of Boothfiles into Dockerfiles.
//
// Boothfile is a higher-level DSL that compiles to Dockerfiles, aimed at simplifying
// CodingBooth configuration by hiding boilerplate and providing intent-based syntax.
//
// Example Boothfile:
//
//	# syntax=codingbooth/boothfile:1
//	setup python 3.12
//	install pip django
//
// This compiles to a full Dockerfile with the required CodingBooth prologue.
package boothfile

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strings"
)

// SyntaxVersion is the expected syntax directive version.
const SyntaxVersion = "codingbooth/boothfile:1"

// SyntaxDirective is the full syntax line expected at the start of a Boothfile.
const SyntaxDirective = "# syntax=" + SyntaxVersion

// CommandType represents the type of a parsed command.
type CommandType int

const (
	CommandUnknown CommandType = iota
	CommandComment
	CommandBlank
	CommandRun
	CommandRunHeredoc
	CommandCopy
	CommandEnv
	CommandWorkdir
	CommandExpose
	CommandLabel
	CommandArg
	CommandSetup
	CommandInstall
	CommandDocker // Escape hatch
)

// String returns a string representation of the command type.
func (ct CommandType) String() string {
	switch ct {
	case CommandComment:
		return "comment"
	case CommandBlank:
		return "blank"
	case CommandRun:
		return "run"
	case CommandRunHeredoc:
		return "run-heredoc"
	case CommandCopy:
		return "copy"
	case CommandEnv:
		return "env"
	case CommandWorkdir:
		return "workdir"
	case CommandExpose:
		return "expose"
	case CommandLabel:
		return "label"
	case CommandArg:
		return "arg"
	case CommandSetup:
		return "setup"
	case CommandInstall:
		return "install"
	case CommandDocker:
		return "DOCKER"
	default:
		return "unknown"
	}
}

// HeredocMode represents how heredoc content should be joined.
type HeredocMode int

const (
	HeredocVerbatim  HeredocMode = iota // Pass through as Docker heredoc
	HeredocAndJoin                      // Join lines with &&
	HeredocSemiJoin                     // Join lines with ;
)

// String returns a string representation of the heredoc mode.
func (hm HeredocMode) String() string {
	switch hm {
	case HeredocVerbatim:
		return "verbatim"
	case HeredocAndJoin:
		return "and-join"
	case HeredocSemiJoin:
		return "semi-join"
	default:
		return "unknown"
	}
}

// Command represents a parsed Boothfile command.
type Command struct {
	Type       CommandType
	LineNumber int
	Raw        string   // Original line(s) from the file
	Args       []string // Parsed arguments

	// For heredoc commands
	HeredocMode      HeredocMode
	HeredocDelimiter string
	HeredocContent   []string
}

// ParseError represents an error that occurred during parsing.
type ParseError struct {
	LineNumber int
	Message    string
	Hint       string
}

// Error implements the error interface.
func (e ParseError) Error() string {
	if e.Hint != "" {
		return fmt.Sprintf("Boothfile:%d: %s\nHint: %s", e.LineNumber, e.Message, e.Hint)
	}
	return fmt.Sprintf("Boothfile:%d: %s", e.LineNumber, e.Message)
}

// ParseResult contains the result of parsing a Boothfile.
type ParseResult struct {
	Commands []Command
	Errors   []ParseError
	Warnings []ParseError
}

// HasErrors returns true if there were parsing errors.
func (pr ParseResult) HasErrors() bool {
	return len(pr.Errors) > 0
}

// HasWarnings returns true if there were parsing warnings.
func (pr ParseResult) HasWarnings() bool {
	return len(pr.Warnings) > 0
}

// Parser parses Boothfiles into structured commands.
type Parser struct {
	strict bool
}

// NewParser creates a new Boothfile parser.
func NewParser() *Parser {
	return &Parser{strict: false}
}

// NewStrictParser creates a new Boothfile parser in strict mode.
// In strict mode, warnings are treated as errors.
func NewStrictParser() *Parser {
	return &Parser{strict: true}
}

// Regex patterns for parsing
var (
	// Matches: run <<END, run &&<<END, run ;<<END
	heredocStartPattern = regexp.MustCompile(`^run\s*(&&|;)?<<(\w+)\s*(?:#.*)?$`)

	// Matches command and rest of line
	commandPattern = regexp.MustCompile(`^(\w+)\s*(.*)$`)

	// Matches inline comment
	inlineCommentPattern = regexp.MustCompile(`^(.*?)\s*#.*$`)
)

// Parse parses a Boothfile from a reader.
func (p *Parser) Parse(r io.Reader) ParseResult {
	result := ParseResult{
		Commands: make([]Command, 0),
		Errors:   make([]ParseError, 0),
		Warnings: make([]ParseError, 0),
	}

	scanner := bufio.NewScanner(r)
	lineNumber := 0
	syntaxFound := false

	for scanner.Scan() {
		lineNumber++
		line := scanner.Text()
		startLineNumber := lineNumber

		// Handle backslash line continuation:
		// If a line ends with '\' (ignoring trailing whitespace), the next line
		// is joined with a single space separating them.
		for {
			trimmed := strings.TrimRight(line, " \t")
			if !strings.HasSuffix(trimmed, `\`) {
				break
			}
			// Strip the trailing backslash and any whitespace before it
			line = strings.TrimRight(trimmed[:len(trimmed)-1], " \t")
			if !scanner.Scan() {
				break
			}
			lineNumber++
			nextLine := strings.TrimLeft(scanner.Text(), " \t")
			line = line + " " + nextLine
		}

		// First non-blank, non-comment line must be syntax directive
		if !syntaxFound {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				result.Commands = append(result.Commands, Command{
					Type:       CommandBlank,
					LineNumber: startLineNumber,
					Raw:        line,
				})
				continue
			}

			// Check for syntax directive
			if strings.HasPrefix(trimmed, "# syntax=") {
				syntaxFound = true
				if trimmed != SyntaxDirective {
					result.Errors = append(result.Errors, ParseError{
						LineNumber: startLineNumber,
						Message:    fmt.Sprintf("Invalid syntax directive. Expected: %s", SyntaxDirective),
						Hint:       "The first non-blank line must be exactly: " + SyntaxDirective,
					})
				}
				result.Commands = append(result.Commands, Command{
					Type:       CommandComment,
					LineNumber: startLineNumber,
					Raw:        line,
				})
				continue
			}

			// Not a syntax directive - error
			result.Errors = append(result.Errors, ParseError{
				LineNumber: startLineNumber,
				Message:    "Missing syntax directive",
				Hint:       "Boothfile must start with: " + SyntaxDirective,
			})
			syntaxFound = true // Continue parsing anyway
		}

		// Parse the line
		cmd, err := p.parseLine(line, startLineNumber, scanner, &lineNumber)
		if err != nil {
			result.Errors = append(result.Errors, *err)
			continue
		}

		if cmd != nil {
			result.Commands = append(result.Commands, *cmd)
		}
	}

	if scanErr := scanner.Err(); scanErr != nil {
		result.Errors = append(result.Errors, ParseError{
			LineNumber: lineNumber,
			Message:    fmt.Sprintf("Error reading file: %v", scanErr),
		})
	}

	return result
}

// ParseString parses a Boothfile from a string.
func (p *Parser) ParseString(content string) ParseResult {
	return p.Parse(strings.NewReader(content))
}

// parseLine parses a single line (or multi-line for heredocs).
func (p *Parser) parseLine(line string, lineNumber int, scanner *bufio.Scanner, currentLine *int) (*Command, *ParseError) {
	trimmed := strings.TrimSpace(line)

	// Blank line
	if trimmed == "" {
		return &Command{
			Type:       CommandBlank,
			LineNumber: lineNumber,
			Raw:        line,
		}, nil
	}

	// Full-line comment
	if strings.HasPrefix(trimmed, "#") {
		return &Command{
			Type:       CommandComment,
			LineNumber: lineNumber,
			Raw:        line,
		}, nil
	}

	// Check for heredoc start
	if heredocMatch := heredocStartPattern.FindStringSubmatch(trimmed); heredocMatch != nil {
		return p.parseHeredoc(line, lineNumber, heredocMatch, scanner, currentLine)
	}

	// Check for DOCKER escape hatch (must be uppercase)
	if strings.HasPrefix(trimmed, "DOCKER ") {
		return &Command{
			Type:       CommandDocker,
			LineNumber: lineNumber,
			Raw:        line,
			Args:       []string{strings.TrimPrefix(trimmed, "DOCKER ")},
		}, nil
	}

	// Parse regular command
	return p.parseCommand(trimmed, lineNumber, line)
}

// parseHeredoc parses a heredoc block.
func (p *Parser) parseHeredoc(startLine string, startLineNumber int, match []string, scanner *bufio.Scanner, currentLine *int) (*Command, *ParseError) {
	// match[1] = mode (empty, "&&", or ";")
	// match[2] = delimiter
	modeStr := match[1]
	delimiter := match[2]

	var mode HeredocMode
	switch modeStr {
	case "&&":
		mode = HeredocAndJoin
	case ";":
		mode = HeredocSemiJoin
	default:
		mode = HeredocVerbatim
	}

	content := make([]string, 0)
	rawLines := []string{startLine}

	for scanner.Scan() {
		*currentLine++
		line := scanner.Text()
		rawLines = append(rawLines, line)

		if strings.TrimSpace(line) == delimiter {
			return &Command{
				Type:             CommandRunHeredoc,
				LineNumber:       startLineNumber,
				Raw:              strings.Join(rawLines, "\n"),
				HeredocMode:      mode,
				HeredocDelimiter: delimiter,
				HeredocContent:   content,
			}, nil
		}

		content = append(content, line)
	}

	// EOF without closing delimiter
	return nil, &ParseError{
		LineNumber: startLineNumber,
		Message:    fmt.Sprintf("Unclosed heredoc block. Expected closing delimiter: %s", delimiter),
		Hint:       "The closing delimiter must appear alone on its own line.",
	}
}

// parseCommand parses a regular (non-heredoc) command.
func (p *Parser) parseCommand(trimmed string, lineNumber int, raw string) (*Command, *ParseError) {
	// Remove inline comment for parsing (but keep in raw)
	withoutComment := trimmed
	if idx := strings.Index(trimmed, "#"); idx > 0 {
		// Check if # is inside quotes (simple heuristic)
		beforeHash := trimmed[:idx]
		if strings.Count(beforeHash, `"`)%2 == 0 && strings.Count(beforeHash, `'`)%2 == 0 {
			withoutComment = strings.TrimSpace(beforeHash)
		}
	}

	match := commandPattern.FindStringSubmatch(withoutComment)
	if match == nil {
		return nil, &ParseError{
			LineNumber: lineNumber,
			Message:    fmt.Sprintf("Invalid command syntax: %s", trimmed),
		}
	}

	cmdName := strings.ToLower(match[1])
	argsStr := match[2]

	// Map command name to type
	cmdType := p.mapCommandType(cmdName)
	if cmdType == CommandUnknown {
		// Check for common typos
		suggestion := p.suggestCommand(cmdName)
		hint := ""
		if suggestion != "" {
			hint = fmt.Sprintf("Did you mean '%s'?", suggestion)
		}
		return nil, &ParseError{
			LineNumber: lineNumber,
			Message:    fmt.Sprintf("Unknown command: %s", cmdName),
			Hint:       hint,
		}
	}

	// Parse arguments based on command type
	args := p.parseArgs(argsStr, cmdType)

	return &Command{
		Type:       cmdType,
		LineNumber: lineNumber,
		Raw:        raw,
		Args:       args,
	}, nil
}

// mapCommandType maps a command name to its type.
func (p *Parser) mapCommandType(name string) CommandType {
	switch name {
	case "run":
		return CommandRun
	case "copy":
		return CommandCopy
	case "env":
		return CommandEnv
	case "workdir":
		return CommandWorkdir
	case "expose":
		return CommandExpose
	case "label":
		return CommandLabel
	case "arg":
		return CommandArg
	case "setup":
		return CommandSetup
	case "install":
		return CommandInstall
	default:
		return CommandUnknown
	}
}

// suggestCommand returns a suggestion for a misspelled command.
func (p *Parser) suggestCommand(name string) string {
	commands := []string{"run", "copy", "env", "workdir", "expose", "label", "arg", "setup", "install"}

	for _, cmd := range commands {
		// Simple Levenshtein-like check: if most characters match
		if len(name) > 0 && len(cmd) > 0 {
			if strings.HasPrefix(cmd, name[:1]) && abs(len(cmd)-len(name)) <= 2 {
				// Check character overlap
				matches := 0
				for i := 0; i < len(name) && i < len(cmd); i++ {
					if name[i] == cmd[i] {
						matches++
					}
				}
				if matches >= len(name)-2 || matches >= len(cmd)-2 {
					return cmd
				}
			}
		}
	}
	return ""
}

// parseArgs parses the argument string for a command.
func (p *Parser) parseArgs(argsStr string, cmdType CommandType) []string {
	argsStr = strings.TrimSpace(argsStr)
	if argsStr == "" {
		return []string{}
	}

	// For most commands, split on whitespace
	// But preserve quoted strings
	return splitArgs(argsStr)
}

// splitArgs splits an argument string, respecting quotes.
func splitArgs(s string) []string {
	var args []string
	var current strings.Builder
	inQuote := false
	quoteChar := rune(0)

	for _, r := range s {
		switch {
		case (r == '"' || r == '\'') && !inQuote:
			inQuote = true
			quoteChar = r
			current.WriteRune(r)
		case r == quoteChar && inQuote:
			inQuote = false
			quoteChar = 0
			current.WriteRune(r)
		case (r == ' ' || r == '\t') && !inQuote:
			if current.Len() > 0 {
				args = append(args, current.String())
				current.Reset()
			}
		default:
			current.WriteRune(r)
		}
	}

	if current.Len() > 0 {
		args = append(args, current.String())
	}

	return args
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
