package db

import (
	"testing"
	"path/filepath"
	"database/sql"
	_ "github.com/mattn/go-sqlite3"
)

func setupTestDB(t *testing.T) *sql.DB {
	// Create a temporary database for testing
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test.db")
	
	testDB, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("Failed to open test database: %v", err)
	}
	
	// Create tables
	_, err = testDB.Exec(`
		CREATE TABLE IF NOT EXISTS messages (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			to_callsign TEXT NOT NULL,
			from_callsign TEXT NOT NULL,
			message TEXT NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			is_delivered BOOLEAN NOT NULL DEFAULT 0
		);
	`)
	if err != nil {
		t.Fatalf("Failed to create test tables: %v", err)
	}
	
	return testDB
}

func storeTestMessage(testDB *sql.DB, to, from, msg string) error {
	_, err := testDB.Exec(
		"INSERT INTO messages (to_callsign, from_callsign, message) VALUES (?, ?, ?)",
		to, from, msg,
	)
	return err
}

func getTestConversationBetween(testDB *sql.DB, callsign1, callsign2 string) ([]*Message, error) {
	const query = `
		SELECT id, to_callsign, from_callsign, message, created_at, is_delivered
		FROM messages
		WHERE 
			(from_callsign = ? AND to_callsign = ?) OR 
			(from_callsign = ? AND to_callsign = ?)
		ORDER BY created_at ASC
	`
	rows, err := testDB.Query(query, callsign1, callsign2, callsign2, callsign1)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*Message
	for rows.Next() {
		var m Message
		var created string
		if err := rows.Scan(&m.ID, &m.ToCallsign, &m.FromCallsign, &m.Message, &created, &m.IsDelivered); err != nil {
			return nil, err
		}
		messages = append(messages, &m)
	}
	return messages, nil
}

func listTestMessagesForUser(testDB *sql.DB, callsign string) ([]*Message, error) {
	const query = `
		SELECT id, to_callsign, from_callsign, message, created_at, is_delivered
		FROM messages
		WHERE
			(from_callsign = ? OR from_callsign LIKE ? || '-%') OR
			(to_callsign = ? OR to_callsign LIKE ? || '-%')
		ORDER BY created_at ASC
	`
	rows, err := testDB.Query(query, callsign, callsign, callsign, callsign)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*Message
	for rows.Next() {
		var m Message
		var created string
		if err := rows.Scan(&m.ID, &m.ToCallsign, &m.FromCallsign, &m.Message, &created, &m.IsDelivered); err != nil {
			return nil, err
		}
		messages = append(messages, &m)
	}
	return messages, nil
}

func TestSSIDMessageGrouping(t *testing.T) {
	testDB := setupTestDB(t)
	defer testDB.Close()
	
	// Store some test messages with different SSIDs
	testMessages := []struct {
		to, from, message string
	}{
		{"K8SDR-10", "W1ABC", "Hello from W1ABC"},
		{"W1ABC", "K8SDR-10", "Hi back from K8SDR-10"},
		{"K8SDR-5", "W1ABC", "Another message to different SSID"},
		{"W1ABC", "K8SDR-5", "Response from K8SDR-5"},
		{"K8SDR", "W2DEF", "Message to base callsign"},
		{"W2DEF", "K8SDR", "Response to base callsign"},
	}
	
	for _, msg := range testMessages {
		err := storeTestMessage(testDB, msg.to, msg.from, msg.message)
		if err != nil {
			t.Fatalf("Failed to store message: %v", err)
		}
	}
	
	// Test GetConversationBetween with SSIDs
	conv1, err := getTestConversationBetween(testDB, "K8SDR-10", "W1ABC")
	if err != nil {
		t.Fatalf("Failed to get conversation: %v", err)
	}
	
	if len(conv1) != 2 {
		t.Errorf("Expected 2 messages in K8SDR-10<->W1ABC conversation, got %d", len(conv1))
	}
	
	// Test message grouping logic
	messages, err := listTestMessagesForUser(testDB, "K8SDR-10")
	if err != nil {
		t.Fatalf("Failed to list messages: %v", err)
	}
	
	// Should find messages where K8SDR-10 is sender or recipient
	if len(messages) != 2 {
		t.Errorf("Expected 2 messages for K8SDR-10, got %d", len(messages))
	}
}

func TestListAllMessagesForUser(t *testing.T) {
	testDB := setupTestDB(t)
	defer testDB.Close()
	
	// Store test messages
	testMessages := []struct {
		to, from, message string
	}{
		{"K8SDR-10", "W1ABC", "Message to K8SDR-10"},
		{"K8SDR-5", "W1ABC", "Message to K8SDR-5"},  
		{"K8SDR", "W1ABC", "Message to base K8SDR"},
		{"W1ABC", "K8SDR-10", "Reply from K8SDR-10"},
		{"W2DEF", "W1ABC", "Unrelated message"},
	}
	
	for _, msg := range testMessages {
		err := storeTestMessage(testDB, msg.to, msg.from, msg.message)
		if err != nil {
			t.Fatalf("Failed to store message: %v", err)
		}
	}
	
	// Get all messages for K8SDR (base callsign)
	messages, err := listTestMessagesForUser(testDB, "K8SDR")
	if err != nil {
		t.Fatalf("Failed to list messages: %v", err)
	}
	
	// Should include messages to K8SDR, K8SDR-10, K8SDR-5, and messages from K8SDR-10
	// Expected: 4 messages (3 incoming to various K8SDR SSIDs + 1 outgoing from K8SDR-10)
	if len(messages) != 4 {
		t.Errorf("Expected 4 messages for K8SDR, got %d", len(messages))
		for i, msg := range messages {
			t.Logf("Message %d: %s -> %s: %s", i, msg.FromCallsign, msg.ToCallsign, msg.Message)
		}
	}
	
	// Verify SSIDs are preserved
	foundSSIDs := make(map[string]bool)
	for _, msg := range messages {
		if msg.ToCallsign == "K8SDR-10" || msg.FromCallsign == "K8SDR-10" {
			foundSSIDs["K8SDR-10"] = true
		}
		if msg.ToCallsign == "K8SDR-5" || msg.FromCallsign == "K8SDR-5" {
			foundSSIDs["K8SDR-5"] = true
		}
		if msg.ToCallsign == "K8SDR" || msg.FromCallsign == "K8SDR" {
			foundSSIDs["K8SDR"] = true
		}
	}
	
	if !foundSSIDs["K8SDR-10"] {
		t.Error("Expected to find messages involving K8SDR-10")
	}
	if !foundSSIDs["K8SDR-5"] {
		t.Error("Expected to find messages involving K8SDR-5") 
	}
	if !foundSSIDs["K8SDR"] {
		t.Error("Expected to find messages involving K8SDR")
	}
}