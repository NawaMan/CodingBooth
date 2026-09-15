// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"crypto/subtle"
	"encoding/json"
	"io"
	"net/http"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/tui"
)

const (
	tokenHeader          = "X-Booth-Config-Token"
	overwriteConfirmWord = "overwrite"
)

// Outcome is sent on the done channel when the user saves or quits.
type Outcome struct {
	Result *tui.ConfigResult
}

type fieldPayload struct {
	Key   string   `json:"key"`
	Value string   `json:"value"`
	Bool  *bool    `json:"bool"`
	List  []string `json:"list"`
}

type keyPayload struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

type savePayload struct {
	Mode          string `json:"mode"`
	OverwriteWord string `json:"overwriteWord"`
}

// NewMux serves the config Web UI and JSON API. Every route requires token.
// Save and cancel send on done; the caller shuts the server down.
func NewMux(session *Session, token string, done chan<- Outcome) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/" && request.URL.Path != "/index.html" {
			http.NotFound(writer, request)
			return
		}
		if !tokenOK(request, token) {
			http.Error(writer, "missing or invalid config token", http.StatusUnauthorized)
			return
		}
		body, err := staticFS.ReadFile("static/index.html")
		if err != nil {
			http.Error(writer, "config UI is missing from this binary", http.StatusInternalServerError)
			return
		}
		writer.Header().Set("Content-Type", "text/html; charset=utf-8")
		writer.Header().Set("Cache-Control", "no-store")
		_, _ = writer.Write(body)
	})
	mux.HandleFunc("/api/catalog", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(writer, session.Catalog())
	})
	mux.HandleFunc("/api/fields", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(writer, tui.FieldTable())
	})
	mux.HandleFunc("/api/state", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(writer, session.CurrentState())
	})
	mux.HandleFunc("/api/toggle", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var payload keyPayload
		if err := readJSON(request, &payload); err != nil || payload.Key == "" {
			http.Error(writer, "key is required", http.StatusBadRequest)
			return
		}
		if err := session.Toggle(payload.Key); err != nil {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(writer, session.CurrentState())
	})
	mux.HandleFunc("/api/field", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var payload fieldPayload
		if err := readJSON(request, &payload); err != nil || payload.Key == "" {
			http.Error(writer, "key is required", http.StatusBadRequest)
			return
		}
		kind := fieldKindFor(payload.Key)
		switch kind {
		case "bool":
			value := false
			if payload.Bool != nil {
				value = *payload.Bool
			}
			session.SetBoolField(payload.Key, value)
		case "list":
			session.SetListField(payload.Key, payload.List)
		default:
			session.SetStringField(payload.Key, payload.Value)
		}
		writeJSON(writer, session.CurrentState())
	})
	mux.HandleFunc("/api/param", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var payload keyPayload
		if err := readJSON(request, &payload); err != nil || payload.Key == "" {
			http.Error(writer, "key is required", http.StatusBadRequest)
			return
		}
		session.SetParam(payload.Key, payload.Value)
		writeJSON(writer, session.CurrentState())
	})
	mux.HandleFunc("/api/save", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var payload savePayload
		_ = readJSON(request, &payload)
		state := session.CurrentState()
		if len(state.Drifted) > 0 {
			mode := payload.Mode
			if mode == "" {
				mode = "save"
			}
			switch mode {
			case "beside":
				result := session.Result(true)
				writeJSON(writer, map[string]any{"ok": true, "beside": true})
				sendOutcome(done, Outcome{Result: result})
				return
			case "overwrite":
				if payload.OverwriteWord != overwriteConfirmWord {
					writeConflict(writer, state.Drifted,
						"type \""+overwriteConfirmWord+"\" to replace hand-written files, or keep them and write .new beside them")
					return
				}
			default:
				writeConflict(writer, state.Drifted,
					"these files are hand-written; keep them (write .new) or type overwrite to replace")
				return
			}
		}
		result := session.Result(false)
		writeJSON(writer, map[string]any{"ok": true})
		sendOutcome(done, Outcome{Result: result})
	})
	mux.HandleFunc("/api/cancel", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(writer, map[string]any{"ok": true})
		sendOutcome(done, Outcome{Result: &tui.ConfigResult{Confirmed: false}})
	})

	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if strings.HasPrefix(request.URL.Path, "/api/") && !tokenOK(request, token) {
			http.Error(writer, "missing or invalid config token", http.StatusUnauthorized)
			return
		}
		mux.ServeHTTP(writer, request)
	})
}

func fieldKindFor(key string) string {
	for _, field := range tui.FieldTable() {
		if field.Key == key {
			return field.Kind
		}
	}
	return "string"
}

func tokenOK(request *http.Request, token string) bool {
	candidates := []string{
		request.Header.Get(tokenHeader),
		request.URL.Query().Get("token"),
	}
	if cookie, err := request.Cookie("booth_config_token"); err == nil {
		candidates = append(candidates, cookie.Value)
	}
	want := []byte(token)
	for _, got := range candidates {
		if got == "" {
			continue
		}
		if subtle.ConstantTimeCompare(want, []byte(got)) == 1 {
			return true
		}
	}
	return false
}

func readJSON(request *http.Request, dest any) error {
	defer request.Body.Close()
	body, err := io.ReadAll(io.LimitReader(request.Body, 1<<20))
	if err != nil {
		return err
	}
	if len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, dest)
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	writer.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(writer).Encode(value)
}

func writeConflict(writer http.ResponseWriter, drifted []string, message string) {
	writer.Header().Set("Content-Type", "application/json")
	writer.Header().Set("Cache-Control", "no-store")
	writer.WriteHeader(http.StatusConflict)
	_ = json.NewEncoder(writer).Encode(map[string]any{
		"error":   "hand-written",
		"drifted": drifted,
		"message": message,
	})
}

func sendOutcome(done chan<- Outcome, outcome Outcome) {
	select {
	case done <- outcome:
	default:
	}
}
