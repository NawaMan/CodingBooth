// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"io"
	"time"
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
