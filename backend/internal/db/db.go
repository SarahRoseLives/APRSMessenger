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
		db, err = sql.Open("sqlite3", path+"?_foreign_keys=on") // Enable foreign keys for CASCADE
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
			CREATE TABLE IF NOT EXISTS blocked_users (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				user_id INTEGER NOT NULL,
				blocked_callsign TEXT NOT NULL,
				created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
				FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
				UNIQUE(user_id, blocked_callsign)
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
	ID           int       `json:"id"`
	ToCallsign   string    `json:"to_callsign"`
	FromCallsign string    `json:"from_callsign"`
	Message      string    `json:"message"`
	CreatedAt    time.Time `json:"created_at"`
	IsDelivered  bool      `json:"is_delivered"`
}

// StoreMessage inserts a message into the DB (for later delivery/history).
func StoreMessage(to, from, msg string) error {
	_, err := db.Exec(
		"INSERT INTO messages (to_callsign, from_callsign, message) VALUES (?, ?, ?)",
		to, from, msg,
	)
	return err
}

// ListAllMessagesForUser returns all messages where the user (with any SSID) is either the sender or the recipient.
func ListAllMessagesForUser(callsign string) ([]*Message, error) {
	baseCallsign := strings.Split(callsign, "-")[0]
	const query = `
		SELECT id, to_callsign, from_callsign, message, created_at, is_delivered
		FROM messages
		WHERE
			(from_callsign = ? OR from_callsign LIKE ? || '-%') OR
			(to_callsign = ? OR to_callsign LIKE ? || '-%')
		ORDER BY created_at ASC
	`
	rows, err := db.Query(query, baseCallsign, baseCallsign, baseCallsign, baseCallsign)
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

// BlockCallsign adds a callsign to a user's block list.
func BlockCallsign(userID int, blockedCallsign string) error {
	baseBlocked := strings.Split(strings.ToUpper(blockedCallsign), "-")[0]
	_, err := db.Exec(
		"INSERT OR IGNORE INTO blocked_users (user_id, blocked_callsign) VALUES (?, ?)",
		userID, baseBlocked,
	)
	return err
}

// IsBlocked checks if a `fromCallsign` is blocked by `userID`.
func IsBlocked(userID int, fromCallsign string) (bool, error) {
	var exists bool
	baseFrom := strings.Split(strings.ToUpper(fromCallsign), "-")[0]
	err := db.QueryRow(
		"SELECT EXISTS(SELECT 1 FROM blocked_users WHERE user_id = ? AND blocked_callsign = ?)",
		userID, baseFrom,
	).Scan(&exists)
	return exists, err
}

// DeleteConversation removes all messages between a user and a contact.
func DeleteConversation(userCallsign string, contactCallsign string) error {
	baseUser := strings.Split(strings.ToUpper(userCallsign), "-")[0]
	baseContact := strings.Split(strings.ToUpper(contactCallsign), "-")[0]
	query := `
		DELETE FROM messages
		WHERE
			(
				(from_callsign LIKE ? || '%' AND to_callsign LIKE ? || '%') OR
				(from_callsign LIKE ? || '%' AND to_callsign LIKE ? || '%')
			)
	`
	_, err := db.Exec(query, baseUser, baseContact, baseContact, baseUser)
	return err
}

// ExportDataForUser retrieves all data associated with a user for export.
func ExportDataForUser(callsign string) (map[string]interface{}, error) {
	user, err := GetUserByCallsign(callsign)
	if err != nil || user == nil {
		return nil, errors.New("user not found")
	}

	messages, err := ListAllMessagesForUser(user.Callsign)
	if err != nil {
		return nil, err
	}

	userInfo := map[string]interface{}{
		"id":       user.ID,
		"callsign": user.Callsign,
	}

	return map[string]interface{}{
		"user_info": userInfo,
		"messages":  messages,
	}, nil
}

// DeleteUserAndData removes a user and all their associated data.
func DeleteUserAndData(userID int) error {
	// Foreign key with ON DELETE CASCADE will handle rows in blocked_users.
	// We still need to manually delete messages.
	user, err := GetUserByID(userID) // You'll need to create this helper function
	if err != nil {
		return err
	}

	baseUser := strings.Split(strings.ToUpper(user.Callsign), "-")[0]
	_, err = db.Exec(`DELETE FROM messages WHERE from_callsign LIKE ? || '%' OR to_callsign LIKE ? || '%'`, baseUser, baseUser)
	if err != nil {
		return err
	}

	// Now delete the user, which will cascade to blocked_users
	_, err = db.Exec("DELETE FROM users WHERE id = ?", userID)
	return err
}

// GetUserByID is a helper to get user details by ID.
func GetUserByID(id int) (*models.User, error) {
	row := db.QueryRow("SELECT id, callsign, password_hash, passcode FROM users WHERE id = ?", id)
	user := &models.User{}
	err := row.Scan(&user.ID, &user.Callsign, &user.PasswordHash, &user.Passcode)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return user, err
}