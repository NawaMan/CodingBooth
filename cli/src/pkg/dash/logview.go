// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"errors"
	"io"
	"os"
	"os/exec"
)

// logView shows a booth's log in the dashboard's terminal (l): the log
// command piped into a pager, or, with no pager, the log command alone.
//
// With a pager, the log command must not be in the terminal's foreground
// process group (the caller detaches it): ctrl+c pauses following in less,
// and would otherwise also end the command feeding it, so following could
// never resume. When the pager quits, the log command is stopped.
type logView struct {
	logs  *exec.Cmd // `booth logs …`
	pager *exec.Cmd // nil: the log command gets the terminal itself
	in    io.Reader
	out   io.Writer
	err   io.Writer
}

func (v *logView) SetStdin(r io.Reader)  { v.in = r }
func (v *logView) SetStdout(w io.Writer) { v.out = w }
func (v *logView) SetStderr(w io.Writer) { v.err = w }

func (v *logView) Run() error {
	if v.pager == nil {
		v.logs.Stdin, v.logs.Stdout, v.logs.Stderr = v.in, v.out, v.err
		// Following ends with ctrl+c, which is how the user leaves.
		return endedByUser(v.logs.Run())
	}

	read, write, err := os.Pipe()
	if err != nil {
		return err
	}
	defer read.Close()
	v.logs.Stdout, v.logs.Stderr = write, write
	if err := v.logs.Start(); err != nil {
		write.Close()
		return err
	}
	write.Close() // the pager sees the end of the log when the command ends
	v.pager.Stdin, v.pager.Stdout, v.pager.Stderr = read, v.out, v.err
	pagerErr := v.pager.Run()

	stopGroup(v.logs)
	_ = v.logs.Wait()
	return endedByUser(pagerErr)
}

// endedByUser: a non-zero exit (ctrl+c, a pager's own status) is how these
// end, not a failure; only a command that could not run is.
func endedByUser(err error) error {
	var exited *exec.ExitError
	if errors.As(err, &exited) {
		return nil
	}
	return err
}
