package ws

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"

	"github.com/gorilla/websocket"
	"golang.org/x/crypto/bcrypt"

	"aprsmessenger-gateway/internal/aprs"
	"aprsmessenger-gateway/internal/db"
	"aprsmessenger-gateway/internal/models"
)

// Websocket upgrader
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// --- Message Types ---

type WSRequest struct {
	Action   string `json:"action"`
	Callsign string `json:"callsign,omitempty"`
	Passcode string `json:"passcode,omitempty"`
	Password string `json:"password,omitempty"`
}

type WSResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

// --- Handler ---

func HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade failed:", err)
		return
	}
	defer conn.Close()

	log.Printf("WebSocket connection from %s", r.RemoteAddr)

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			log.Println("WebSocket read failed:", err)
			break
		}

		var req WSRequest
		if err := json.Unmarshal(msg, &req); err != nil {
			sendResponse(conn, false, "Invalid JSON")
			log.Printf("Invalid JSON from %s: %s", r.RemoteAddr, string(msg))
			continue
		}

		log.Printf("Received action: %s from callsign: %s", req.Action, req.Callsign)

		switch req.Action {
		case "create_account":
			handleCreateAccount(conn, req)
		case "login":
			handleLogin(conn, req)
		default:
			sendResponse(conn, false, "Unknown action")
			log.Printf("Unknown action: %s", req.Action)
		}
	}
}

func handleCreateAccount(conn *websocket.Conn, req WSRequest) {
	callsign := cleanCallsign(req.Callsign)
	if !validCallsign(callsign) {
		sendResponse(conn, false, "Invalid callsign")
		log.Printf("Invalid callsign during registration: %s", callsign)
		return
	}
	if req.Password == "" || req.Passcode == "" {
		sendResponse(conn, false, "Missing password or passcode")
		log.Printf("Missing password or passcode for callsign: %s", callsign)
		return
	}
	expectedPasscode := aprsPass(callsign)
	if req.Passcode != expectedPasscode {
		sendResponse(conn, false, "Incorrect passcode for callsign")
		log.Printf("Incorrect passcode for callsign: %s", callsign)
		return
	}
	// Check if user exists
	user, _ := db.GetUserByCallsign(callsign)
	if user != nil {
		sendResponse(conn, false, "Callsign already registered")
		log.Printf("Attempt to re-register existing callsign: %s", callsign)
		return
	}
	pwHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		sendResponse(conn, false, "Password encryption failed")
		log.Printf("Password encryption failed for callsign: %s", callsign)
		return
	}
	newUser := &models.User{
		Callsign:     callsign,
		PasswordHash: string(pwHash),
		Passcode:     req.Passcode,
	}
	if err := db.CreateUser(newUser); err != nil {
		sendResponse(conn, false, "Failed to create user")
		log.Printf("Failed to create user: %s", err)
		return
	}
	sendResponse(conn, true, "")
	log.Printf("Account created for callsign: %s", callsign)
}

func handleLogin(conn *websocket.Conn, req WSRequest) {
	callsign := cleanCallsign(req.Callsign)
	if !validCallsign(callsign) {
		sendResponse(conn, false, "Invalid callsign")
		log.Printf("Invalid callsign for login: %s", callsign)
		return
	}
	user, err := db.GetUserByCallsign(callsign)
	if err != nil || user == nil {
		sendResponse(conn, false, "Callsign not found")
		log.Printf("Callsign not found for login: %s", callsign)
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		sendResponse(conn, false, "Incorrect password")
		log.Printf("Incorrect password for callsign: %s", callsign)
		return
	}

	// Use sessions manager to ensure user session; attach websocket
	session := aprs.GetSessionsManager().EnsureSession(callsign)
	session.AttachWebSocket(conn)

	sendResponse(conn, true, "")
	log.Printf("Login success: %s", callsign)
}

func sendResponse(conn *websocket.Conn, success bool, errMsg string) {
	resp := WSResponse{Success: success}
	if !success {
		resp.Error = errMsg
	}
	conn.WriteJSON(resp)
}

// --- Utility functions ---

// Remove dash and everything after, upper case, max 10 chars
func cleanCallsign(callsign string) string {
	if idx := strings.Index(callsign, "-"); idx != -1 {
		callsign = callsign[:idx]
	}
	return strings.ToUpper(callsign)[:min(10, len(callsign))]
}

func validCallsign(callsign string) bool {
	// 1-10 chars, uppercase letters/numbers only after cleaning
	re := regexp.MustCompile(`^[A-Z0-9]{1,10}$`)
	return re.MatchString(callsign)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// Use our own aprspass for registration
func aprsPass(callsign string) string {
	callsign = strings.ToUpper(callsign)
	hash := uint16(0x73e2)
	chars := []byte(callsign)
	for i := 0; i < len(chars); i += 2 {
		hash ^= uint16(chars[i]) << 8
		if i+1 < len(chars) {
			hash ^= uint16(chars[i+1])
		}
	}
	return fmt.Sprintf("%d", hash&0x7fff)
}