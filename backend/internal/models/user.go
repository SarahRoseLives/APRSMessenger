package models

type User struct {
	ID           int
	Callsign     string
	PasswordHash string
	Passcode     string
}