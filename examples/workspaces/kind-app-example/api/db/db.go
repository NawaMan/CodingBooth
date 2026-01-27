package db

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"time"

	_ "github.com/lib/pq"
)

var DB *sql.DB

func Init() error {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://todouser:todopass@localhost:5432/tododb?sslmode=disable"
	}

	var err error
	// Retry connection with backoff
	for i := 0; i < 30; i++ {
		DB, err = sql.Open("postgres", dbURL)
		if err != nil {
			log.Printf("Failed to open database: %v, retrying...", err)
			time.Sleep(time.Second * 2)
			continue
		}

		err = DB.Ping()
		if err == nil {
			break
		}
		log.Printf("Failed to ping database: %v, retrying...", err)
		time.Sleep(time.Second * 2)
	}

	if err != nil {
		return fmt.Errorf("failed to connect to database after retries: %v", err)
	}

	log.Println("Connected to database")
	return nil
}

func Close() {
	if DB != nil {
		DB.Close()
	}
}
