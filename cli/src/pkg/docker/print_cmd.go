package docker

import (
	"fmt"
	"regexp"
	"strings"
)

// simpleArgPattern matches arguments that don't need quoting (alphanumeric + _./:-).
var simpleArgPattern = regexp.MustCompile(`^[A-Za-z0-9_./:-]+$`)

// PrintCmd formats and prints a command with proper shell escaping.
func printCmd(command string, argGroups ...[]string) {
	fmt.Print(formatArg(command))

	for _, group := range argGroups {
		if len(group) == 0 {
			continue
		}
		fmt.Printf(" \\\n    ")
		for i, arg := range group {
			escaped := formatArg(arg)
			if i > 0 {
				fmt.Printf(" ")
			}
			fmt.Printf("%s", escaped)
		}
	}
	fmt.Println()
}

// formatArg returns the argument, escaped if necessary.
func formatArg(arg string) string {
	if simpleArgPattern.MatchString(arg) {
		return arg
	}
	return escapeArg(arg)
}

// escapeArg wraps an argument in single quotes and escapes any single quotes within it.
func escapeArg(arg string) string {
	escaped := strings.ReplaceAll(arg, "'", "'\\''")
	return fmt.Sprintf("'%s'", escaped)
}
