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

// Edits read back from disk save normally, except that their comments cannot be
// carried: the first save names them, and only a deliberate second one writes.
func TestMux_LostCommentsConflictUntilConfirmed(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	session.lostComments = []string{".booth/config.toml:3  # team port"}
	done := make(chan Outcome, 1)
	handler := NewMux(session, testToken, done)

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/save", testToken, map[string]string{"mode": "save"}))
	if recorder.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", recorder.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil || body["error"] != "comments" {
		t.Fatalf("want a comments conflict, got %s", recorder.Body.String())
	}
	select {
	case <-done:
		t.Fatal("conflict should not complete the save")
	default:
	}

	recorder = httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/save", testToken, map[string]string{"mode": "drop-comments"}))
	if recorder.Code != http.StatusOK {
		t.Fatalf("drop-comments status = %d", recorder.Code)
	}
	outcome := <-done
	if !outcome.Result.Confirmed || outcome.Result.SaveBeside {
		t.Fatalf("confirming should save in place: %+v", outcome.Result)
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

// The three hand-written choices: apply keeps a backup, overwrite needs the word
// and keeps none.
func TestMux_HandWrittenApplyAndOverwrite(t *testing.T) {
	save := func(body map[string]string) (*httptest.ResponseRecorder, chan Outcome) {
		session := NewSession(sessionRegistry(), nil, "", []string{"Boothfile"})
		done := make(chan Outcome, 1)
		recorder := httptest.NewRecorder()
		NewMux(session, testToken, done).ServeHTTP(recorder, testRequest(http.MethodPost, "/api/save", testToken, body))
		return recorder, done
	}

	recorder, done := save(map[string]string{"mode": "apply"})
	if recorder.Code != http.StatusOK {
		t.Fatalf("apply status = %d", recorder.Code)
	}
	if outcome := <-done; outcome.Result.SaveBeside || outcome.Result.NoBackup {
		t.Fatal("apply should replace with a backup")
	}

	recorder, _ = save(map[string]string{"mode": "overwrite", "overwriteWord": "overwrit"})
	if recorder.Code != http.StatusConflict {
		t.Fatalf("a half-typed word should conflict, status = %d", recorder.Code)
	}

	recorder, done = save(map[string]string{"mode": "overwrite", "overwriteWord": overwriteConfirmWord})
	if recorder.Code != http.StatusOK {
		t.Fatalf("overwrite status = %d", recorder.Code)
	}
	if outcome := <-done; !outcome.Result.NoBackup {
		t.Fatal("overwrite should keep no backup")
	}
}

// Edits made outside booth config are asked about once: accept keeps them (and
// refreshes the fingerprint when one is set); cancel ends the session to review.
func TestMux_AdoptedAnswer(t *testing.T) {
	session := NewSession(sessionRegistry(), nil, "", nil)
	refreshed := false
	session.adopted = []string{"config.toml"}
	session.refreshFingerprint = func() error { refreshed = true; return nil }
	done := make(chan Outcome, 1)
	handler := NewMux(session, testToken, done)

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/adopted", testToken, map[string]bool{"accept": true}))
	if recorder.Code != http.StatusOK || !refreshed {
		t.Fatalf("accept: status = %d, refreshed = %v", recorder.Code, refreshed)
	}
	if len(session.CurrentState().Adopted) != 0 {
		t.Fatal("an answered question should not be asked again")
	}
	select {
	case <-done:
		t.Fatal("accepting should not end the session")
	default:
	}

	session.adopted = []string{"config.toml"}
	recorder = httptest.NewRecorder()
	handler.ServeHTTP(recorder, testRequest(http.MethodPost, "/api/adopted", testToken, map[string]bool{"accept": false}))
	outcome := <-done
	if outcome.Result.Confirmed || !outcome.Result.Review {
		t.Fatalf("cancel should end the session for review: %+v", outcome.Result)
	}
}
