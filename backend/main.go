package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"aprsmessenger-gateway/internal/aprs"
	"aprsmessenger-gateway/internal/db"
	"aprsmessenger-gateway/internal/ws"
)

func main() {
	// Ensure data directory exists
	dataDir := filepath.Join(".", "data")
	_ = os.MkdirAll(dataDir, 0755)

	// Open DB connection
	dbPath := filepath.Join(dataDir, "users.db")
	err := db.Init(dbPath)
	if err != nil {
		log.Fatalf("Failed to init DB: %v", err)
	}
	defer db.Close()

	// Start the global APRS Manager. It now handles both listening and sending.
	aprs.GetAPRSManager().Start()

	http.HandleFunc("/ws", ws.HandleWebSocket)

	log.Println("Server started on :8585")
	log.Fatal(http.ListenAndServe(":8585", nil))
}