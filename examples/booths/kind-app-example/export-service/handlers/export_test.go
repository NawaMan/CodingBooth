package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestExportCSV(t *testing.T) {
	tasks := []Task{
		{ID: 1, Title: "Test Task 1", Description: "Description 1", Completed: false, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{ID: 2, Title: "Test Task 2", Description: "Description 2", Completed: true, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}

	req := ExportRequest{Tasks: tasks, Format: "csv"}
	body, _ := json.Marshal(req)

	r := httptest.NewRequest(http.MethodPost, "/export", bytes.NewReader(body))
	w := httptest.NewRecorder()

	ExportHandler(w, r)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	contentType := w.Header().Get("Content-Type")
	if contentType != "text/csv" {
		t.Errorf("Expected Content-Type text/csv, got %s", contentType)
	}

	result := w.Body.String()
	if !strings.Contains(result, "Test Task 1") {
		t.Error("CSV should contain task title")
	}
	if !strings.Contains(result, "ID,Title,Description,Completed") {
		t.Error("CSV should contain header row")
	}
}

func TestExportJSON(t *testing.T) {
	tasks := []Task{
		{ID: 1, Title: "Test Task 1", Description: "Description 1", Completed: false, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}

	req := ExportRequest{Tasks: tasks, Format: "json"}
	body, _ := json.Marshal(req)

	r := httptest.NewRequest(http.MethodPost, "/export", bytes.NewReader(body))
	w := httptest.NewRecorder()

	ExportHandler(w, r)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	contentType := w.Header().Get("Content-Type")
	if contentType != "application/json" {
		t.Errorf("Expected Content-Type application/json, got %s", contentType)
	}

	var result struct {
		Count int    `json:"count"`
		Tasks []Task `json:"tasks"`
	}
	if err := json.NewDecoder(w.Body).Decode(&result); err != nil {
		t.Errorf("Failed to decode JSON response: %v", err)
	}

	if result.Count != 1 {
		t.Errorf("Expected count 1, got %d", result.Count)
	}
}

func TestEmptyExport(t *testing.T) {
	req := ExportRequest{Tasks: []Task{}, Format: "json"}
	body, _ := json.Marshal(req)

	r := httptest.NewRequest(http.MethodPost, "/export", bytes.NewReader(body))
	w := httptest.NewRecorder()

	ExportHandler(w, r)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var result struct {
		Count int `json:"count"`
	}
	json.NewDecoder(w.Body).Decode(&result)

	if result.Count != 0 {
		t.Errorf("Expected count 0, got %d", result.Count)
	}
}
