// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"golang.org/x/term"
)

// logTime controls whether timestamps are prepended to log output.
var logTime bool

// SetLogTime enables or disables timestamp prefixes on log output.
func SetLogTime(enabled bool) {
	logTime = enabled
}

func timePrefix() string {
	if !logTime {
		return ""
	}
	return fmt.Sprintf("[%s] ", time.Now().Format("15:04:05"))
}

// LogPrintln prints a line, optionally prefixed with a timestamp.
func LogPrintln(a ...any) {
	if logTime {
		fmt.Print(timePrefix())
	}
	fmt.Println(a...)
}

// LogPrintf prints a formatted string, optionally prefixed with a timestamp.
func LogPrintf(format string, a ...any) {
	if logTime {
		fmt.Print(timePrefix())
	}
	fmt.Printf(format, a...)
}

// LogFprintf prints a formatted string to the given writer, optionally prefixed with a timestamp.
func LogFprintf(w io.Writer, format string, a ...any) {
	if logTime {
		fmt.Fprint(w, timePrefix())
	}
	fmt.Fprintf(w, format, a...)
}

// LogTimef prints a formatted string only when --log-time is enabled (for timing-only messages).
func LogTimef(w io.Writer, format string, a ...any) {
	if !logTime {
		return
	}
	fmt.Fprint(w, timePrefix())
	fmt.Fprintf(w, format, a...)
}

// stderrIsTerminal reports whether stderr is a terminal; a variable so tests,
// which never run on one, can say otherwise.
var stderrIsTerminal = func() bool { return term.IsTerminal(int(os.Stderr.Fd())) }

// rawSafe ends each line of a status message with "\r\n" when it is written
// alongside a foreground container on a terminal, as the browser opener's
// "Opened …" and the tunnel watcher's "Tunnel opened …" are. The foreground
// `docker run` gets -i -t there, and the docker client puts the terminal in raw
// mode for it:
// a bare "\n" then moves down a line without returning to the left margin, so
// the message leaves the cursor mid-line — under the text it just printed —
// and the container's next output, or the shell prompt after it, starts there.
// A terminal in normal mode just sees an extra "\r" before its own, which moves
// nothing. Output that is not a terminal (a log file) keeps plain "\n".
func rawSafe(s string, foreground bool) string {
	if !foreground || !stderrIsTerminal() {
		return s
	}
	return strings.ReplaceAll(s, "\n", "\r\n")
}
