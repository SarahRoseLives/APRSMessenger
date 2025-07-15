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

// ... (Code is identical until handleSendMessage) ...

func handleSendMessage(conn *websocket.Conn, fromCallsign string, req WSRequest) {
	toCallsign := strings.ToUpper(strings.TrimSpace(req.ToCallsign))
	if toCallsign == "" {
		sendResponse(conn, false, "Invalid recipient callsign")
		return
	}
	if req.Message == "" {
		sendResponse(conn, false, "Message cannot be empty")
		return
	}

	// *** THIS IS THE FIX ***
	// The call now correctly passes all three required arguments:
	// fromCallsign (string), toCallsign (string), and req.Message (string).
	log.Printf("[WS] Queuing message from %s to %s", fromCallsign, toCallsign)
	err := aprs.GetAPRSManager().SendMessage(fromCallsign, toCallsign, req.Message)

	if err != nil {
		sendResponse(conn, false, "Failed to send message: "+err.Error())
		log.Printf("[APRS] Error sending message from %s: %v", fromCallsign, err)
	} else {
		// *** ADD THIS BLOCK ***
		// Store the sent message in the database for history.
		// The `to_callsign` is the recipient, and the `from_callsign` is our user.
		if storeErr := db.StoreMessage(toCallsign, fromCallsign, req.Message); storeErr != nil {
			// Log the error, but don't fail the operation since the message was sent.
			log.Printf("[DB] Failed to store sent message for history from %s: %v", fromCallsign, storeErr)
		}
		// **********************
		sendResponse(conn, true, "")
	}
}

// ... (The rest of the file is unchanged) ...
// (Full file content is provided below for completeness)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type WSRequest struct {
	Action     string `json:"action"`
	Callsign   string `json:"callsign,omitempty"`
	Password   string `json:"password,omitempty"`
	Passcode   string `json:"passcode,omitempty"`
	ToCallsign string `json:"to_callsign,omitempty"`
	Message    string `json:"message,omitempty"`
}

type WSResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

func HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade failed:", err)
		return
	}
	defer conn.Close()
	log.Printf("WebSocket connection from %s", r.RemoteAddr)

	var user *models.User
	var originalCallsign string
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			log.Println("WebSocket read failed during auth:", err)
			return
		}

		var req WSRequest
		if err := json.Unmarshal(msg, &req); err != nil {
			sendResponse(conn, false, "Invalid JSON")
			continue
		}

		switch req.Action {
		case "create_account":
			handleCreateAccount(conn, req)
		case "login":
			originalCallsign = strings.ToUpper(strings.TrimSpace(req.Callsign))
			user, err = attemptLogin(req)
			if err != nil {
				sendResponse(conn, false, err.Error())
				log.Printf("Login failed for %s: %v", req.Callsign, err)
			} else {
				sendResponse(conn, true, "")
				log.Printf("Login success: %s (session for %s)", user.Callsign, originalCallsign)
				goto authenticated
			}
		default:
			sendResponse(conn, false, "Authentication required. Please 'login' or 'create_account'.")
		}
	}

authenticated:
	session := aprs.GetSessionsManager().EnsureSession(originalCallsign)
	session.AttachWebSocket(conn)
	defer session.DetachWebSocket(conn)

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			log.Printf("WebSocket read failed for user %s: %v", originalCallsign, err)
			break
		}

		var req WSRequest
		if err := json.Unmarshal(msg, &req); err != nil {
			sendResponse(conn, false, "Invalid JSON")
			continue
		}

		switch req.Action {
		case "send_message":
			handleSendMessage(conn, originalCallsign, req)
		default:
			sendResponse(conn, false, "Unknown action.")
		}
	}
}

func attemptLogin(req WSRequest) (*models.User, error) {
	callsign := cleanCallsign(req.Callsign)
	if !validCallsign(callsign) {
		return nil, fmt.Errorf("invalid callsign")
	}
	user, err := db.GetUserByCallsign(callsign)
	if err != nil || user == nil {
		return nil, fmt.Errorf("callsign not found")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return nil, fmt.Errorf("incorrect password")
	}
	return user, nil
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

func sendResponse(conn *websocket.Conn, success bool, errMsg string) {
	resp := WSResponse{Success: success}
	if !success {
		resp.Error = errMsg
	}
	_ = conn.WriteJSON(resp)
}

func cleanCallsign(callsign string) string {
	if idx := strings.Index(callsign, "-"); idx != -1 {
		callsign = callsign[:idx]
	}
	cs := strings.ToUpper(callsign)
	if len(cs) > 10 {
		return cs[:10]
	}
	return cs
}

func validCallsign(callsign string) bool {
	re := regexp.MustCompile(`^[A-Z0-9]{1,10}$`)
	return re.MatchString(callsign)
}

func aprsPass(callsign string) string {
	callsign = strings.ToUpper(strings.Split(callsign, "-")[0])
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