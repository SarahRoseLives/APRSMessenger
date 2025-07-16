package ws

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"aprsmessenger-gateway/internal/aprs"
	"aprsmessenger-gateway/internal/db"
	"aprsmessenger-gateway/internal/models"

	"github.com/gorilla/websocket"
	"golang.org/x/crypto/bcrypt"
)

// --- BEGIN MESSAGE STATE TRACKING STRUCTS ---

// MessageState holds the state for a message in a conversation.
type MessageState struct {
	LastSentMsgId     string         // The last message ID sent (by us)
	LastReceivedMsgId string         // The last message ID received (from their side)
	SentMsgRetryCount map[string]int // messageId -> retry count (for received duplicates)
	Mutex             sync.Mutex
}

// ConversationState tracks state for each user/conversation.
var conversationStates = struct {
	sync.RWMutex
	m map[string]map[string]*MessageState // myCallsign -> otherCallsign -> *MessageState
}{m: make(map[string]map[string]*MessageState)}

// Utility for getting message state for a conversation.
func getOrCreateMessageState(myCall, otherCall string) *MessageState {
	conversationStates.Lock()
	defer conversationStates.Unlock()
	if conversationStates.m[myCall] == nil {
		conversationStates.m[myCall] = make(map[string]*MessageState)
	}
	if conversationStates.m[myCall][otherCall] == nil {
		conversationStates.m[myCall][otherCall] = &MessageState{
			SentMsgRetryCount: make(map[string]int),
		}
	}
	return conversationStates.m[myCall][otherCall]
}

// Utility for generating the next message ID (rolling 2 digits, 00-99).
func nextMessageId(last string) string {
	if last == "" {
		return "01"
	}
	var n int
	fmt.Sscanf(last, "%02d", &n)
	n = (n + 1) % 100
	return fmt.Sprintf("%02d", n)
}

// --- END MESSAGE STATE TRACKING STRUCTS ---

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// WSRequest defines the structure for all incoming websocket actions.
type WSRequest struct {
	Action       string `json:"action"`
	Callsign     string `json:"callsign,omitempty"`
	Password     string `json:"password,omitempty"`
	Passcode     string `json:"passcode,omitempty"`
	Token        string `json:"token,omitempty"` // For QR code login
	ToCallsign   string `json:"to_callsign,omitempty"`
	Message      string `json:"message,omitempty"`
	FromCallsign string `json:"from_callsign,omitempty"`
}

// WSResponse is a flexible map for sending responses back to the client.
type WSResponse map[string]interface{}

// sendSuccessResponse sends a structured success message to the client.
func sendSuccessResponse(conn *websocket.Conn, data WSResponse) {
	response := WSResponse{"success": true}
	if data != nil {
		for k, v := range data {
			response[k] = v
		}
	}
	_ = conn.WriteJSON(response)
}

// sendErrorResponse sends a structured error message to the client.
func sendErrorResponse(conn *websocket.Conn, errMsg string) {
	response := WSResponse{"success": false, "error": errMsg}
	_ = conn.WriteJSON(response)
}

// HandleWebSocket is the main entry point for websocket connections.
func HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade failed:", err)
		return
	}
	defer conn.Close()
	log.Printf("WebSocket connection from %s", r.RemoteAddr)

	var user *models.User
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure, websocket.CloseNoStatusReceived) {
				log.Printf("WebSocket unexpected close during auth: %v", err)
			}
			return
		}

		var req WSRequest
		if err := json.Unmarshal(msg, &req); err != nil {
			sendErrorResponse(conn, "Invalid JSON")
			continue
		}

		switch req.Action {
		case "create_account":
			handleCreateAccount(conn, req)
		case "login":
			var token string
			user, token, err = attemptLogin(req)
			if err != nil {
				sendErrorResponse(conn, err.Error())
				log.Printf("Login failed for %s: %v", req.Callsign, err)
			} else {
				sendSuccessResponse(conn, WSResponse{"session_token": token})
				log.Printf("Login success: %s", user.Callsign)
				goto authenticated
			}
		case "login_with_token":
			user, err = handleTokenLogin(req)
			if err != nil {
				sendErrorResponse(conn, err.Error())
				log.Printf("Token login failed: %v", err)
			} else {
				sendSuccessResponse(conn, WSResponse{"callsign": user.Callsign})
				log.Printf("Token login success for %s", user.Callsign)
				goto authenticated
			}
		default:
			sendErrorResponse(conn, "Authentication required. Please 'login' or 'create_account'.")
		}
	}

authenticated:
	// Once authenticated, attach the websocket to the user's session.
	baseUserCallsign := getBaseCallsign(user.Callsign)
	session := aprs.GetSessionsManager().EnsureSession(baseUserCallsign)
	session.AttachWebSocket(conn)
	defer session.DetachWebSocket(conn)

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket unexpected close for user %s: %v", user.Callsign, err)
			}
			break
		}

		var req WSRequest
		if err := json.Unmarshal(msg, &req); err != nil {
			sendErrorResponse(conn, "Invalid JSON")
			continue
		}

		switch req.Action {
		case "send_message":
			fromCallsign := user.Callsign
			if req.FromCallsign != "" {
				fromCallsign = req.FromCallsign
			}
			handleSendMessage(conn, fromCallsign, baseUserCallsign, req)
		default:
			sendErrorResponse(conn, "Unknown action.")
		}
	}
}

// handleSendMessage sends the message to APRS-IS and broadcasts it to other connected clients.
func handleSendMessage(conn *websocket.Conn, fromCallsign, baseUserCallsign string, req WSRequest) {
	toCallsign := strings.ToUpper(strings.TrimSpace(req.ToCallsign))
	if toCallsign == "" {
		sendErrorResponse(conn, "Invalid recipient callsign")
		return
	}
	if req.Message == "" {
		sendErrorResponse(conn, "Message cannot be empty")
		return
	}

	// Stateful message ID and REPLY-ACK tracking
	state := getOrCreateMessageState(baseUserCallsign, toCallsign)
	state.Mutex.Lock()
	nextMsgId := nextMessageId(state.LastSentMsgId)
	lastReceivedId := state.LastReceivedMsgId
	state.LastSentMsgId = nextMsgId
	state.Mutex.Unlock()

	// Compose APRS payload: MSG{MM}AA (text with {msgId}ackId)
	aprsPayload := req.Message
	if lastReceivedId != "" {
		aprsPayload = fmt.Sprintf("%s{%s}%s", req.Message, nextMsgId, lastReceivedId)
	} else {
		aprsPayload = fmt.Sprintf("%s{%s}", req.Message, nextMsgId)
	}

	log.Printf("[WS] Queuing message from %s to %s with id %s, REPLY-ACK=%s", fromCallsign, toCallsign, nextMsgId, lastReceivedId)
	err := aprs.GetAPRSManager().SendMessage(fromCallsign, toCallsign, aprsPayload)

	if err != nil {
		sendErrorResponse(conn, "Failed to send message: "+err.Error())
		log.Printf("[APRS] Error sending message from %s: %v", fromCallsign, err)
	} else {
		// Store the sent message for history.
		if storeErr := db.StoreMessage(toCallsign, fromCallsign, aprsPayload); storeErr != nil {
			log.Printf("[DB] Failed to store sent message for history from %s: %v", fromCallsign, storeErr)
		}

		// Echo back to sender: status=sending (immediately after sending to network)
		echo := map[string]interface{}{
			"type":               "message_status_update",
			"contact_groupingId": toCallsign,
			"messageId":          nextMsgId,
			"status":             "sent", // Could be "sending" if you want an intermediate step
			"retryCount":         0,
			"time":               time.Now().Format(time.RFC3339),
		}
		_ = conn.WriteJSON(echo)

		// Broadcast the sent message to the user's other clients for synchronization.
		if session := aprs.GetSessionsManager().GetSession(baseUserCallsign); session != nil {
			echoRoute := []string{"APRS", "K8SDR-10"}
			session.BroadcastMessage(fromCallsign, toCallsign, aprsPayload, echoRoute, conn)
		}
	}
}

// handleTokenLogin validates a session token and returns the associated user.
func handleTokenLogin(req WSRequest) (*models.User, error) {
	if req.Token == "" {
		return nil, fmt.Errorf("token is missing")
	}

	callsign, err := aprs.GetSessionsManager().ValidateAndUseToken(req.Token)
	if err != nil {
		return nil, err // e.g., "invalid or expired token"
	}

	user, err := db.GetUserByCallsign(callsign)
	if err != nil || user == nil {
		return nil, fmt.Errorf("server error: could not find user for valid token")
	}

	return user, nil
}

// attemptLogin validates user credentials and returns the user model and a new session token on success.
func attemptLogin(req WSRequest) (*models.User, string, error) {
	callsign := cleanCallsign(req.Callsign)
	if !validCallsign(callsign) {
		return nil, "", fmt.Errorf("invalid callsign format")
	}
	user, err := db.GetUserByCallsign(callsign)
	if err != nil || user == nil {
		return nil, "", fmt.Errorf("callsign not found or server error")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return nil, "", fmt.Errorf("incorrect password")
	}

	// Login successful, generate a single-use session token for QR code login.
	token, err := aprs.GetSessionsManager().GenerateSessionToken(user.Callsign)
	if err != nil {
		log.Printf("[AUTH] Failed to generate session token for %s: %v", user.Callsign, err)
		return nil, "", fmt.Errorf("could not create session token")
	}

	return user, token, nil
}

func handleCreateAccount(conn *websocket.Conn, req WSRequest) {
	callsign := cleanCallsign(req.Callsign)
	if !validCallsign(callsign) {
		sendErrorResponse(conn, "Invalid callsign format")
		return
	}
	if req.Password == "" || req.Passcode == "" {
		sendErrorResponse(conn, "Missing password or passcode")
		return
	}
	expectedPasscode := aprs.GeneratePasscode(getBaseCallsign(callsign))
	if req.Passcode != fmt.Sprintf("%d", expectedPasscode) {
		sendErrorResponse(conn, "Incorrect APRS-IS passcode for callsign")
		return
	}
	user, _ := db.GetUserByCallsign(callsign)
	if user != nil {
		sendErrorResponse(conn, "Callsign already registered")
		return
	}
	pwHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		sendErrorResponse(conn, "Server error: could not hash password")
		return
	}
	newUser := &models.User{
		Callsign:     callsign,
		PasswordHash: string(pwHash),
		Passcode:     req.Passcode,
	}
	if err := db.CreateUser(newUser); err != nil {
		sendErrorResponse(conn, "Server error: could not create user")
		return
	}
	sendSuccessResponse(conn, nil)
	log.Printf("Account created for callsign: %s", callsign)
}

func cleanCallsign(callsign string) string {
	return strings.ToUpper(strings.TrimSpace(callsign))
}

func getBaseCallsign(callsign string) string {
	if idx := strings.Index(callsign, "-"); idx != -1 {
		return callsign[:idx]
	}
	return callsign
}

func validCallsign(callsign string) bool {
	// A simple regex for callsign with optional SSID
	re := regexp.MustCompile(`^[A-Z0-9]{1,6}(-[0-9]{1,2})?$`)
	return re.MatchString(callsign)
}