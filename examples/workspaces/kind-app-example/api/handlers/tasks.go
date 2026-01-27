package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/todo-app/api/db"
	"github.com/todo-app/api/models"
)

func GetTasks(w http.ResponseWriter, r *http.Request) {
	rows, err := db.DB.Query(`
		SELECT id, title, description, completed, created_at, updated_at 
		FROM tasks 
		ORDER BY created_at DESC
	`)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error fetching tasks: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	tasks := []models.Task{}
	for rows.Next() {
		var task models.Task
		err := rows.Scan(&task.ID, &task.Title, &task.Description, &task.Completed, &task.CreatedAt, &task.UpdatedAt)
		if err != nil {
			http.Error(w, fmt.Sprintf("Error scanning task: %v", err), http.StatusInternalServerError)
			return
		}
		tasks = append(tasks, task)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tasks)
}

func GetTask(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	taskID, err := strconv.Atoi(id)
	if err != nil {
		http.Error(w, "Invalid task ID", http.StatusBadRequest)
		return
	}

	var task models.Task
	err = db.DB.QueryRow(`
		SELECT id, title, description, completed, created_at, updated_at 
		FROM tasks WHERE id = $1
	`, taskID).Scan(&task.ID, &task.Title, &task.Description, &task.Completed, &task.CreatedAt, &task.UpdatedAt)

	if err != nil {
		http.Error(w, "Task not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(task)
}

func CreateTask(w http.ResponseWriter, r *http.Request) {
	var req models.CreateTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Title == "" {
		http.Error(w, "Title is required", http.StatusBadRequest)
		return
	}

	var task models.Task
	err := db.DB.QueryRow(`
		INSERT INTO tasks (title, description, completed, created_at, updated_at)
		VALUES ($1, $2, false, NOW(), NOW())
		RETURNING id, title, description, completed, created_at, updated_at
	`, req.Title, req.Description).Scan(&task.ID, &task.Title, &task.Description, &task.Completed, &task.CreatedAt, &task.UpdatedAt)

	if err != nil {
		http.Error(w, fmt.Sprintf("Error creating task: %v", err), http.StatusInternalServerError)
		return
	}

	// Broadcast to WebSocket clients
	BroadcastTaskEvent("task_created", task)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(task)
}

func UpdateTask(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	taskID, err := strconv.Atoi(id)
	if err != nil {
		http.Error(w, "Invalid task ID", http.StatusBadRequest)
		return
	}

	var req models.UpdateTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Get existing task
	var task models.Task
	err = db.DB.QueryRow(`SELECT id, title, description, completed, created_at FROM tasks WHERE id = $1`, taskID).
		Scan(&task.ID, &task.Title, &task.Description, &task.Completed, &task.CreatedAt)
	if err != nil {
		http.Error(w, "Task not found", http.StatusNotFound)
		return
	}

	// Apply updates
	if req.Title != nil {
		task.Title = *req.Title
	}
	if req.Description != nil {
		task.Description = *req.Description
	}
	if req.Completed != nil {
		task.Completed = *req.Completed
	}

	err = db.DB.QueryRow(`
		UPDATE tasks 
		SET title = $1, description = $2, completed = $3, updated_at = NOW()
		WHERE id = $4
		RETURNING updated_at
	`, task.Title, task.Description, task.Completed, taskID).Scan(&task.UpdatedAt)

	if err != nil {
		http.Error(w, fmt.Sprintf("Error updating task: %v", err), http.StatusInternalServerError)
		return
	}

	// Broadcast to WebSocket clients
	BroadcastTaskEvent("task_updated", task)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(task)
}

func DeleteTask(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	taskID, err := strconv.Atoi(id)
	if err != nil {
		http.Error(w, "Invalid task ID", http.StatusBadRequest)
		return
	}

	// Get task before deletion for broadcast
	var task models.Task
	err = db.DB.QueryRow(`SELECT id, title, description, completed, created_at, updated_at FROM tasks WHERE id = $1`, taskID).
		Scan(&task.ID, &task.Title, &task.Description, &task.Completed, &task.CreatedAt, &task.UpdatedAt)
	if err != nil {
		http.Error(w, "Task not found", http.StatusNotFound)
		return
	}

	_, err = db.DB.Exec(`DELETE FROM tasks WHERE id = $1`, taskID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error deleting task: %v", err), http.StatusInternalServerError)
		return
	}

	// Broadcast to WebSocket clients
	BroadcastTaskEvent("task_deleted", task)

	w.WriteHeader(http.StatusNoContent)
}

func ExportTasks(w http.ResponseWriter, r *http.Request) {
	format := r.URL.Query().Get("format")
	if format == "" {
		format = "json"
	}

	// Get all tasks
	rows, err := db.DB.Query(`
		SELECT id, title, description, completed, created_at, updated_at 
		FROM tasks 
		ORDER BY created_at DESC
	`)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error fetching tasks: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	tasks := []models.Task{}
	for rows.Next() {
		var task models.Task
		err := rows.Scan(&task.ID, &task.Title, &task.Description, &task.Completed, &task.CreatedAt, &task.UpdatedAt)
		if err != nil {
			http.Error(w, fmt.Sprintf("Error scanning task: %v", err), http.StatusInternalServerError)
			return
		}
		tasks = append(tasks, task)
	}

	// Call export service
	exportServiceURL := os.Getenv("EXPORT_SERVICE_URL")
	if exportServiceURL == "" {
		exportServiceURL = "http://localhost:8081"
	}

	exportReq := struct {
		Tasks  []models.Task `json:"tasks"`
		Format string        `json:"format"`
	}{
		Tasks:  tasks,
		Format: format,
	}

	body, err := json.Marshal(exportReq)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error marshaling export request: %v", err), http.StatusInternalServerError)
		return
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Post(exportServiceURL+"/export", "application/json", bytes.NewReader(body))
	if err != nil {
		http.Error(w, fmt.Sprintf("Error calling export service: %v", err), http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	// Copy headers
	for key, values := range resp.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}
