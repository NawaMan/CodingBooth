// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
)

// holdOnFailure runs a command in the dashboard's terminal and, when it fails,
// waits for Enter before the dashboard takes the screen back: otherwise the
// reason it printed would vanish with the switch back.
type holdOnFailure struct {
	cmd  *exec.Cmd
	what string // "start web", for the closing line
	// banner, when set, is printed before the command runs, and no failure is
	// held: a shell's exit status is its last command's, not a failure.
	banner string
	in     io.Reader
	out    io.Writer
}

func (h *holdOnFailure) SetStdin(r io.Reader) {
	h.in = r
	if h.cmd.Stdin == nil {
		h.cmd.Stdin = r
	}
}

func (h *holdOnFailure) SetStdout(w io.Writer) {
	h.out = w
	if h.cmd.Stdout == nil {
		h.cmd.Stdout = w
	}
}

func (h *holdOnFailure) SetStderr(w io.Writer) {
	if h.cmd.Stderr == nil {
		h.cmd.Stderr = w
	}
}

func (h *holdOnFailure) Run() error {
	if h.banner != "" {
		if h.out != nil {
			fmt.Fprintln(h.out, h.banner)
		}
		if err := h.cmd.Run(); err != nil {
			if _, exited := err.(*exec.ExitError); !exited {
				return err
			}
		}
		return nil
	}
	err := h.cmd.Run()
	if err != nil && h.in != nil && h.out != nil {
		fmt.Fprintf(h.out, "\nCould not %s (%v). Press Enter to return to booth dashboard.", h.what, err)
		_, _ = bufio.NewReader(h.in).ReadString('\n')
	}
	return err
}
