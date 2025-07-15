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

	// Start global persistent APRS session (as K8SDR-AM) for all users
	aprs.GetAPRSManager().Start()

	http.HandleFunc("/ws", ws.HandleWebSocket)

	log.Println("Server started on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}