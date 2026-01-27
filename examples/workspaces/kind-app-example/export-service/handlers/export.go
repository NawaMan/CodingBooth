package handlers

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"
)

type Task struct {
	ID          int       `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Completed   bool      `json:"completed"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type ExportRequest struct {
	Tasks  []Task `json:"tasks"`
	Format string `json:"format"`
}

func ExportHandler(w http.ResponseWriter, r *http.Request) {
	var req ExportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	format := req.Format
	if format == "" {
		format = "json"
	}

	switch format {
	case "csv":
		exportCSV(w, req.Tasks)
	case "json":
		exportJSON(w, req.Tasks)
	default:
		http.Error(w, "Invalid format. Use 'csv' or 'json'", http.StatusBadRequest)
	}
}

func exportCSV(w http.ResponseWriter, tasks []Task) {
	w.Header().Set("Content-Type", "text/csv")
	w.Header().Set("Content-Disposition", "attachment; filename=tasks.csv")

	writer := csv.NewWriter(w)
	defer writer.Flush()

	// Write header
	writer.Write([]string{"ID", "Title", "Description", "Completed", "Created At", "Updated At"})

	// Write data
	for _, task := range tasks {
		writer.Write([]string{
			strconv.Itoa(task.ID),
			task.Title,
			task.Description,
			strconv.FormatBool(task.Completed),
			task.CreatedAt.Format(time.RFC3339),
			task.UpdatedAt.Format(time.RFC3339),
		})
	}
}

func exportJSON(w http.ResponseWriter, tasks []Task) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Disposition", "attachment; filename=tasks.json")

	output := struct {
		ExportedAt time.Time `json:"exported_at"`
		Count      int       `json:"count"`
		Tasks      []Task    `json:"tasks"`
	}{
		ExportedAt: time.Now(),
		Count:      len(tasks),
		Tasks:      tasks,
	}

	if err := json.NewEncoder(w).Encode(output); err != nil {
		http.Error(w, fmt.Sprintf("Error encoding JSON: %v", err), http.StatusInternalServerError)
	}
}
