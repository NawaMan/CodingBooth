// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

const testToken = "test-token-0001"

func testRequest(method, path string, token string, body any) *http.Request {
	var reader *bytes.Reader
	if body != nil {
		raw, _ := json.Marshal(body)
		reader = bytes.NewReader(raw)
	} else {
		reader = bytes.NewReader(nil)
	}
	request := httptest.NewRequest(method, path, reader)
	if token != "" {
		request.Header.Set(tokenHeader, token)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	return request
}

func TestMux_RejectsMissingToken(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	handler := NewMux(session, testToken, make(chan Outcome, 1))
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodGet, "/api/catalog", "", nil))
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", recorder.Code)
	}
}

func TestMux_ToggleAndSaveProducesDSL(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	done := make(chan Outcome, 1)
	handler := NewMux(session, testToken, done)

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodGet, "/api/catalog", testToken, nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("catalog status = %d", recorder.Code)
	}
	var catalog Catalog
	if err := json.Unmarshal(recorder.Body.Bytes(), &catalog); err != nil {
		t.Fatal(err)
	}
	if len(catalog.Categories) != 2 {
		t.Fatalf("categories = %d, want 2 from the test registry", len(catalog.Categories))
	}

	recorder = httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/toggle", testToken, map[string]string{"key": "go"}))
	if recorder.Code != http.StatusOK {
		t.Fatalf("toggle status = %d body %s", recorder.Code, recorder.Body.String())
	}

	recorder = httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/save", testToken, map[string]string{"mode": "save"}))
	if recorder.Code != http.StatusOK {
		t.Fatalf("save status = %d body %s", recorder.Code, recorder.Body.String())
	}
	select {
	case outcome := <-done:
		if outcome.Result == nil || !outcome.Result.Confirmed {
			t.Fatal("save should confirm")
		}
		if outcome.Result.SelectDSL != "go+linter" {
			t.Fatalf("DSL = %q, want go+linter", outcome.Result.SelectDSL)
		}
	default:
		t.Fatal("save did not send an outcome")
	}
}

func TestMux_HandWrittenSaveConflictsUntilChosen(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", []string{"Boothfile"})
	done := make(chan Outcome, 1)
	handler := NewMux(session, testToken, done)

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/save", testToken, map[string]string{"mode": "save"}))
	if recorder.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", recorder.Code)
	}
	select {
	case <-done:
		t.Fatal("conflict should not complete the save")
	default:
	}

	recorder = httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/save", testToken, map[string]string{"mode": "beside"}))
	if recorder.Code != http.StatusOK {
		t.Fatalf("beside status = %d", recorder.Code)
	}
	outcome := <-done
	if !outcome.Result.SaveBeside {
		t.Fatal("beside should set SaveBeside")
	}
}

func TestMux_ServesIndexWithToken(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	handler := NewMux(session, testToken, make(chan Outcome, 1))
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/?token="+testToken, nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d", recorder.Code)
	}
	if ct := recorder.Header().Get("Content-Type"); ct != "text/html; charset=utf-8" {
		t.Fatalf("content-type = %q", ct)
	}
	if !bytes.Contains(recorder.Body.Bytes(), []byte("CodingBooth Configuration")) {
		t.Fatal("index.html was not served")
	}
}
