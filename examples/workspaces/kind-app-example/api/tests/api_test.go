package tests

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

var baseURL string

func TestMain(m *testing.M) {
	baseURL = os.Getenv("API_URL")
	if baseURL == "" {
		baseURL = "http://localhost:8080"
	}

	// Wait for API to be ready
	for i := 0; i < 30; i++ {
		resp, err := http.Get(baseURL + "/health")
		if err == nil && resp.StatusCode == 200 {
			break
		}
		time.Sleep(time.Second)
	}

	os.Exit(m.Run())
}

type Task struct {
	ID          int       `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Completed   bool      `json:"completed"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

func TestCreateTask(t *testing.T) {
	payload := map[string]string{
		"title":       "Test Task",
		"description": "Test Description",
	}
	body, _ := json.Marshal(payload)

	resp, err := http.Post(baseURL+"/api/tasks", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatalf("Failed to create task: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		t.Errorf("Expected status 201, got %d", resp.StatusCode)
	}

	var task Task
	if err := json.NewDecoder(resp.Body).Decode(&task); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if task.Title != "Test Task" {
		t.Errorf("Expected title 'Test Task', got '%s'", task.Title)
	}
}

func TestGetTasks(t *testing.T) {
	resp, err := http.Get(baseURL + "/api/tasks")
	if err != nil {
		t.Fatalf("Failed to get tasks: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}

	var tasks []Task
	if err := json.NewDecoder(resp.Body).Decode(&tasks); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if len(tasks) == 0 {
		t.Error("Expected at least one task")
	}
}

func TestGetTask(t *testing.T) {
	// First create a task
	payload := map[string]string{"title": "Get Test Task", "description": "Test"}
	body, _ := json.Marshal(payload)
	createResp, _ := http.Post(baseURL+"/api/tasks", "application/json", bytes.NewReader(body))
	var created Task
	json.NewDecoder(createResp.Body).Decode(&created)
	createResp.Body.Close()

	// Then get it
	resp, err := http.Get(fmt.Sprintf("%s/api/tasks/%d", baseURL, created.ID))
	if err != nil {
		t.Fatalf("Failed to get task: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}

	var task Task
	json.NewDecoder(resp.Body).Decode(&task)
	if task.ID != created.ID {
		t.Errorf("Expected ID %d, got %d", created.ID, task.ID)
	}
}

func TestUpdateTask(t *testing.T) {
	// Create a task
	payload := map[string]string{"title": "Update Test Task", "description": "Test"}
	body, _ := json.Marshal(payload)
	createResp, _ := http.Post(baseURL+"/api/tasks", "application/json", bytes.NewReader(body))
	var created Task
	json.NewDecoder(createResp.Body).Decode(&created)
	createResp.Body.Close()

	// Update it
	updatePayload := map[string]interface{}{"completed": true}
	updateBody, _ := json.Marshal(updatePayload)

	req, _ := http.NewRequest(http.MethodPut, fmt.Sprintf("%s/api/tasks/%d", baseURL, created.ID), bytes.NewReader(updateBody))
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("Failed to update task: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}

	var updated Task
	json.NewDecoder(resp.Body).Decode(&updated)
	if !updated.Completed {
		t.Error("Expected completed to be true")
	}
}

func TestDeleteTask(t *testing.T) {
	// Create a task
	payload := map[string]string{"title": "Delete Test Task", "description": "Test"}
	body, _ := json.Marshal(payload)
	createResp, _ := http.Post(baseURL+"/api/tasks", "application/json", bytes.NewReader(body))
	var created Task
	json.NewDecoder(createResp.Body).Decode(&created)
	createResp.Body.Close()

	// Delete it
	req, _ := http.NewRequest(http.MethodDelete, fmt.Sprintf("%s/api/tasks/%d", baseURL, created.ID), nil)
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("Failed to delete task: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		t.Errorf("Expected status 204, got %d", resp.StatusCode)
	}

	// Verify it's gone
	getResp, _ := http.Get(fmt.Sprintf("%s/api/tasks/%d", baseURL, created.ID))
	if getResp.StatusCode != http.StatusNotFound {
		t.Errorf("Expected status 404, got %d", getResp.StatusCode)
	}
	getResp.Body.Close()
}

func TestExportCSV(t *testing.T) {
	resp, err := http.Get(baseURL + "/api/export?format=csv")
	if err != nil {
		t.Fatalf("Failed to export CSV: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType != "text/csv" {
		t.Errorf("Expected Content-Type text/csv, got %s", contentType)
	}
}

func TestExportJSON(t *testing.T) {
	resp, err := http.Get(baseURL + "/api/export?format=json")
	if err != nil {
		t.Fatalf("Failed to export JSON: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType != "application/json" {
		t.Errorf("Expected Content-Type application/json, got %s", contentType)
	}
}

func TestWebSocketBroadcast(t *testing.T) {
	wsURL := "ws" + baseURL[4:] + "/ws"

	// Connect to WebSocket
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Failed to connect to WebSocket: %v", err)
	}
	defer conn.Close()

	// Channel to receive messages
	messages := make(chan []byte, 1)
	go func() {
		_, msg, err := conn.ReadMessage()
		if err == nil {
			messages <- msg
		}
	}()

	// Create a task (should trigger broadcast)
	payload := map[string]string{"title": "WebSocket Test Task", "description": "Test"}
	body, _ := json.Marshal(payload)
	resp, err := http.Post(baseURL+"/api/tasks", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatalf("Failed to create task: %v", err)
	}
	resp.Body.Close()

	// Wait for WebSocket message
	select {
	case msg := <-messages:
		var event struct {
			Type string `json:"type"`
			Task Task   `json:"task"`
		}
		if err := json.Unmarshal(msg, &event); err != nil {
			t.Fatalf("Failed to unmarshal WebSocket message: %v", err)
		}
		if event.Type != "task_created" {
			t.Errorf("Expected event type 'task_created', got '%s'", event.Type)
		}
	case <-time.After(5 * time.Second):
		t.Error("Timeout waiting for WebSocket message")
	}
}
