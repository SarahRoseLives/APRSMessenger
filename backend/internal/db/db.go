package db

import (
	"database/sql"
	"errors"
	"strings"
	"sync"

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