// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"time"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/tui"
)

// Options configures the host-side config Web UI.
type Options struct {
	Registry    *tmpl.TemplateRegistry
	Pre         *tui.PreSelection
	Warning     string
	Drifted     []string
	PortFlag    string
	Listener    net.Listener // tests; when set, PortFlag is ignored
	Token       string       // tests; generated when empty
	OpenBrowser bool
	Output      io.Writer
}

// Run serves the config Web UI on 127.0.0.1:<booth-port> until the user saves
// or quits, then returns the same ConfigResult the TUI would.
func Run(opts Options) (*tui.ConfigResult, error) {
	output := opts.Output
	if output == nil {
		output = os.Stderr
	}

	listener := opts.Listener
	if listener == nil {
		port := ResolveListenPort(opts.PortFlag)
		var err error
		listener, err = ListenLoopback(port)
		if err != nil {
			return nil, err
		}
	}
	defer listener.Close()

	token := opts.Token
	if token == "" {
		var err error
		token, err = newToken()
		if err != nil {
			return nil, err
		}
	}

	session := NewSession(opts.Registry, opts.Pre, opts.Warning, opts.Drifted)
	done := make(chan Outcome, 1)
	server := &http.Server{
		Handler:           NewMux(session, token, done),
		ReadHeaderTimeout: 5 * time.Second,
	}

	url := "http://" + listener.Addr().String() + "/?token=" + token
	fmt.Fprintf(output, "Config UI: %s\n", url)
	fmt.Fprintln(output, "(loopback only; the token is required to save)")

	if opts.OpenBrowser {
		if err := openURL(url); err != nil {
			fmt.Fprintf(output, "Could not open a browser: %v\nOpen the URL yourself.\n", err)
		}
	}

	serveErr := make(chan error, 1)
	go func() {
		err := server.Serve(listener)
		if err != nil && err != http.ErrServerClosed {
			serveErr <- err
		}
	}()

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)
	defer signal.Stop(interrupt)

	var outcome Outcome
	select {
	case err := <-serveErr:
		return nil, err
	case <-interrupt:
		outcome = Outcome{Result: &tui.ConfigResult{Confirmed: false}}
	case outcome = <-done:
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)

	if outcome.Result == nil {
		return &tui.ConfigResult{Confirmed: false}, nil
	}
	return outcome.Result, nil
}

func newToken() (string, error) {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", fmt.Errorf("generating config UI token: %w", err)
	}
	return hex.EncodeToString(bytes[:]), nil
}
