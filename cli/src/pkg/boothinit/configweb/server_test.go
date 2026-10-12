// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"bytes"
	"encoding/json"
	"net"
	"net/http"
	"testing"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/tui"
)

func TestRun_ToggleAndSaveReturnsDSL(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	token := "run-test-token"
	baseURL := "http://" + listener.Addr().String()

	finished := make(chan struct {
		result *tui.ConfigResult
		err    error
	}, 1)
	go func() {
		result, runErr := Run(Options{
			Registry:    sessionRegistry(),
			Listener:    listener,
			Token:       token,
			OpenBrowser: false,
			Output:      &bytes.Buffer{},
		})
		finished <- struct {
			result *tui.ConfigResult
			err    error
		}{result, runErr}
	}()

	waitForServer(t, baseURL+"/api/state", token)

	toggleBody, _ := json.Marshal(map[string]string{"key": "go"})
	status := postJSON(t, baseURL+"/api/toggle", token, toggleBody)
	if status != http.StatusOK {
		t.Fatalf("toggle status = %d", status)
	}
	status = postJSON(t, baseURL+"/api/save", token, []byte(`{"mode":"save"}`))
	if status != http.StatusOK {
		t.Fatalf("save status = %d", status)
	}

	select {
	case done := <-finished:
		if done.err != nil {
			t.Fatal(done.err)
		}
		if done.result == nil || !done.result.Confirmed {
			t.Fatal("save should confirm")
		}
		if done.result.SelectDSL != "go+linter" {
			t.Fatalf("DSL = %q, want go+linter", done.result.SelectDSL)
		}
	case <-time.After(serverBudget):
		t.Fatal("Run did not return after save")
	}
}

// serverBudget is how long a test here waits for the server to answer, and for
// Run to return once it has. It is a failure budget, not a measurement: the
// test normally finishes in milliseconds, so a generous number only changes how
// long a genuinely broken case takes to report. Two seconds was not generous
// enough — `go test ./...` builds and runs several packages at once, and on a
// loaded machine this test lost that race about one run in five.
const serverBudget = 30 * time.Second

func waitForServer(t *testing.T, url, token string) {
	t.Helper()
	deadline := time.Now().Add(serverBudget)
	for {
		request, _ := http.NewRequest(http.MethodGet, url, nil)
		request.Header.Set(tokenHeader, token)
		response, err := http.DefaultClient.Do(request)
		if err == nil {
			response.Body.Close()
			if response.StatusCode == http.StatusOK {
				return
			}
		}
		if time.Now().After(deadline) {
			t.Fatal("server did not come up")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func postJSON(t *testing.T, url, token string, body []byte) int {
	t.Helper()
	request, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	request.Header.Set(tokenHeader, token)
	request.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	return response.StatusCode
}
