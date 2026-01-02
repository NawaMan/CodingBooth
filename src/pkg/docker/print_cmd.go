package docker

import (
	"fmt"
	"regexp"
	"strings"
)

// simpleArgPattern matches arguments that don't need quoting (alphanumeric + _./:-).
var simpleArgPattern = regexp.MustCompile(`^[A-Za-z0-9_./:-]+$`)

// PrintCmd formats and prints a command with proper shell escaping.
func PrintCmd(command string, args ...string) {
	printText(command)

	for _, arg := range args {
		printText(arg)
	}

	fmt.Printf("\n")
}

// printText prints an argument with proper shell escaping.
func printText(arg string) {
	if simpleArgPattern.MatchString(arg) {
		fmt.Printf("%s ", arg)
	} else {
		fmt.Printf("%s ", escapeArg(arg))
	}
}

// escapeArg wraps an argument in single quotes and escapes any single quotes within it.
func escapeArg(arg string) string {
	escaped := strings.ReplaceAll(arg, "'", "'\\''")
	return fmt.Sprintf("'%s'", escaped)
}
