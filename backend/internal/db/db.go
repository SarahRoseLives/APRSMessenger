package db

import (
	"database/sql"
	"errors"
	"strings"
	"sync"
	"time"

	"aprsmessenger-gateway/internal/models"

	_ "github.com/mattn/go-sqlite3"
)

var (
	db   *sql.DB
	once sync.Once
)

func Init(path string) error {
	var err error
	once.Do(func() {
		db, err = sql.Open("sqlite3", path)
		if err != nil {
			return
		}
		_, err = db.Exec(`
			CREATE TABLE IF NOT EXISTS users (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				callsign TEXT UNIQUE NOT NULL,
				password_hash TEXT NOT NULL,
				passcode TEXT NOT NULL
			);
			CREATE TABLE IF NOT EXISTS messages (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				to_callsign TEXT NOT NULL,
				from_callsign TEXT NOT NULL,
				message TEXT NOT NULL,
				created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
				is_delivered BOOLEAN NOT NULL DEFAULT 0
			);
		`)
	})
	return err
}

func Close() {
	if db != nil {
		db.Close()
	}
}

func CreateUser(user *models.User) error {
	_, err := db.Exec(
		"INSERT INTO users (callsign, password_hash, passcode) VALUES (?, ?, ?)",
		user.Callsign, user.PasswordHash, user.Passcode,
	)
	return err
}

func GetUserByCallsign(callsign string) (*models.User, error) {
	row := db.QueryRow("SELECT id, callsign, password_hash, passcode FROM users WHERE callsign = ?", callsign)
	user := &models.User{}
	err := row.Scan(&user.ID, &user.Callsign, &user.PasswordHash, &user.Passcode)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return user, err
}

// LoadAllUsers returns all users from the users table.
func LoadAllUsers() ([]*models.User, error) {
	rows, err := db.Query("SELECT id, callsign, password_hash, passcode FROM users")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []*models.User
	for rows.Next() {
		user := &models.User{}
		if err := rows.Scan(&user.ID, &user.Callsign, &user.PasswordHash, &user.Passcode); err != nil {
			return nil, err
		}
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return users, nil
}

// UserCallsignSet returns a set of all callsigns in the users table (uppercased, base callsign and full callsign)
func UserCallsignSet() (map[string]struct{}, error) {
	users, err := LoadAllUsers()
	if err != nil {
		return nil, err
	}
	set := make(map[string]struct{})
	for _, u := range users {
		// Add both full callsign and base callsign (without SSID)
		full := strings.ToUpper(strings.TrimSpace(u.Callsign))
		set[full] = struct{}{}
		base := full
		if idx := strings.Index(base, "-"); idx != -1 {
			base = base[:idx]
			set[base] = struct{}{}
		}
	}
	return set, nil
}

// Message DB Layer

type Message struct {
	ID          int
	ToCallsign  string
	FromCallsign string
	Message     string
	CreatedAt   time.Time
	IsDelivered bool
}

// StoreMessage inserts a message into the DB (for later delivery/history).
func StoreMessage(to, from, msg string) error {
	_, err := db.Exec(
		"INSERT INTO messages (to_callsign, from_callsign, message) VALUES (?, ?, ?)",
		to, from, msg,
	)
	return err
}

// *** ADD THIS NEW FUNCTION ***
// ListAllMessagesForUser returns all messages where the user is either the sender or the recipient.
func ListAllMessagesForUser(callsign string) ([]*Message, error) {
	const query = `
		SELECT id, to_callsign, from_callsign, message, created_at, is_delivered
		FROM messages
		WHERE
			(from_callsign = ? OR from_callsign LIKE ? || '-%') OR
			(to_callsign = ? OR to_callsign LIKE ? || '-%')
		ORDER BY created_at ASC
	`
	rows, err := db.Query(query, callsign, callsign, callsign, callsign)
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
		m.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", created)
		messages = append(messages, &m)
	}
	return messages, nil
}
// ****************************

// GetConversationBetween returns all messages between two callsigns, ordered by created_at.
// This function is SSID-aware - it will match exact SSIDs when provided, or any SSID for base callsigns.
func GetConversationBetween(callsign1, callsign2 string) ([]*Message, error) {
	const query = `
		SELECT id, to_callsign, from_callsign, message, created_at, is_delivered
		FROM messages
		WHERE 
			(from_callsign = ? AND to_callsign = ?) OR 
			(from_callsign = ? AND to_callsign = ?)
		ORDER BY created_at ASC
	`
	rows, err := db.Query(query, callsign1, callsign2, callsign2, callsign1)
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
		m.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", created)
		messages = append(messages, &m)
	}
	return messages, nil
}

// GroupMessagesByPairs returns a map of conversation pairs to their message lists for a given user.
// The map key is formatted as "CALL1<->CALL2" where CALL1 is alphabetically first.
func GroupMessagesByPairs(userCallsign string) (map[string][]*Message, error) {
	messages, err := ListAllMessagesForUser(userCallsign)
	if err != nil {
		return nil, err
	}

	conversations := make(map[string][]*Message)
	
	for _, msg := range messages {
		var otherCallsign string
		if msg.FromCallsign == userCallsign || strings.HasPrefix(msg.FromCallsign, userCallsign+"-") {
			// This is a message sent by the user
			otherCallsign = msg.ToCallsign
		} else {
			// This is a message received by the user
			otherCallsign = msg.FromCallsign
		}

		// Create a consistent key for the conversation pair
		var key string
		if userCallsign < otherCallsign {
			key = userCallsign + "<->" + otherCallsign
		} else {
			key = otherCallsign + "<->" + userCallsign
		}

		conversations[key] = append(conversations[key], msg)
	}

	return conversations, nil
}

// ListUndeliveredMessages returns all undelivered messages for a callsign, ordered oldest first.
func ListUndeliveredMessages(callsign string) ([]*Message, error) {
	// The user's callsign is a base callsign (e.g., "K8SDR"), but messages in the DB
	// may be addressed to a specific SSID (e.g., "K8SDR-9"). This query finds all
	// messages for the base callsign, with or without an SSID.
	const query = `
		SELECT id, to_callsign, from_callsign, message, created_at, is_delivered
		FROM messages
		WHERE (to_callsign = ? OR to_callsign LIKE ? || '-%') AND is_delivered = 0
		ORDER BY created_at ASC`

	rows, err := db.Query(query, callsign, callsign) // Pass callsign twice for both placeholders
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
		m.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", created)
		messages = append(messages, &m)
	}
	return messages, nil
}

// MarkMessagesDelivered marks a list of message IDs as delivered.
func MarkMessagesDelivered(ids []int) error {
	if len(ids) == 0 {
		return nil
	}
	query := "UPDATE messages SET is_delivered = 1 WHERE id IN (?" + strings.Repeat(",?", len(ids)-1) + ")"
	args := make([]interface{}, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	_, err := db.Exec(query, args...)
	return err
}