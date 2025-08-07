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
	LastSentMsgId     string // The last message ID sent (by us)
	LastReceivedMsgId string // The last message ID received (from their side)
	SentMsgRetryCount map[string]int   // messageId -> retry count (for received duplicates)
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
	Action          string `json:"action"`
	Callsign        string `json:"callsign,omitempty"`
	Password        string `json:"password,omitempty"`
	Passcode        string `json:"passcode,omitempty"`
	Token           string `json:"token,omitempty"` // For QR code login
	ToCallsign      string `json:"to_callsign,omitempty"`
	Message         string `json:"message,omitempty"`
	FromCallsign    string `json:"from_callsign,omitempty"`
	CallsignToBlock string `json:"callsign_to_block,omitempty"`
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

// isUserAdmin checks if a given callsign is in the hardcoded admin list.
func isUserAdmin(callsign string) bool {
	baseCallsign := getBaseCallsign(callsign)
	// In a real app, this would be a database role check.
	adminCallsigns := map[string]struct{}{
		"K8SDR": {},
		"AD8NT": {},
	}
	_, isAdmin := adminCallsigns[baseCallsign]
	return isAdmin
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
		case "delete_conversation":
			handleDeleteConversation(conn, user.Callsign, req)
		case "block_callsign":
			handleBlockCallsign(conn, user.ID, req)
		case "request_data_export":
			handleRequestDataExport(conn, user.Callsign)
		case "delete_account":
			handleDeleteAccount(conn, user, req)
		case "get_admin_stats":
			handleGetAdminStats(conn, user)
		case "admin_broadcast":
			handleAdminBroadcast(conn, user, req)
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

func handleDeleteConversation(conn *websocket.Conn, userCallsign string, req WSRequest) {
	contactCallsign := cleanCallsign(req.ToCallsign)
	if contactCallsign == "" {
		sendErrorResponse(conn, "Invalid contact callsign provided for deletion.")
		return
	}
	err := db.DeleteConversation(userCallsign, contactCallsign)
	if err != nil {
		log.Printf("[DB] Error deleting conversation for %s with %s: %v", userCallsign, contactCallsign, err)
		sendErrorResponse(conn, "Failed to delete conversation.")
	} else {
		log.Printf("[WS] Deleted conversation for %s with %s", userCallsign, contactCallsign)
		_ = conn.WriteJSON(WSResponse{"type": "conversation_deleted", "contact": getBaseCallsign(contactCallsign)})
	}
}

func handleBlockCallsign(conn *websocket.Conn, userID int, req WSRequest) {
	callsignToBlock := cleanCallsign(req.CallsignToBlock)
	if !validCallsign(callsignToBlock) {
		sendErrorResponse(conn, "Invalid callsign format for blocking.")
		return
	}
	err := db.BlockCallsign(userID, callsignToBlock)
	if err != nil {
		log.Printf("[DB] Error blocking callsign for user %d: %v", userID, err)
		sendErrorResponse(conn, "Failed to block callsign.")
	} else {
		log.Printf("[WS] User %d blocked %s", userID, callsignToBlock)
		_ = conn.WriteJSON(WSResponse{"type": "callsign_blocked", "contact": getBaseCallsign(callsignToBlock)})
	}
}

func handleRequestDataExport(conn *websocket.Conn, callsign string) {
	data, err := db.ExportDataForUser(callsign)
	if err != nil {
		log.Printf("[WS] Failed to export data for %s: %v", callsign, err)
		sendErrorResponse(conn, "Failed to export data.")
		return
	}
	_ = conn.WriteJSON(WSResponse{"type": "data_export", "data": data})
}

func handleDeleteAccount(conn *websocket.Conn, user *models.User, req WSRequest) {
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		sendErrorResponse(conn, "Incorrect password. Account not deleted.")
		return
	}
	if err := db.DeleteUserAndData(user.ID); err != nil {
		log.Printf("[DB] Failed to delete account for user %d: %v", user.ID, err)
		sendErrorResponse(conn, "Failed to delete account.")
		return
	}
	log.Printf("[WS] DELETED ACCOUNT for user %s (ID: %d)", user.Callsign, user.ID)
	_ = conn.WriteJSON(WSResponse{"type": "account_deleted", "success": true})
}

// handleGetAdminStats gathers and sends admin-level statistics to the client.
func handleGetAdminStats(conn *websocket.Conn, user *models.User) {
	if !isUserAdmin(user.Callsign) {
		sendErrorResponse(conn, "Access denied.")
		return
	}

	users, err := db.LoadAllUsers()
	if err != nil {
		log.Printf("[WS ADMIN] Failed to load users: %v", err)
		sendErrorResponse(conn, "Failed to retrieve user list.")
		return
	}

	stats, err := db.GetMessageStats()
	if err != nil {
		log.Printf("[WS ADMIN] Failed to get message stats: %v", err)
		sendErrorResponse(conn, "Failed to retrieve message statistics.")
		return
	}

	// Don't send password hashes to the client, even the admin.
	clientUsers := make([]map[string]interface{}, len(users))
	for i, u := range users {
		clientUsers[i] = map[string]interface{}{
			"id":       u.ID,
			"callsign": u.Callsign,
		}
	}

	response := WSResponse{
		"type":      "admin_stats_update",
		"success":   true,
		"users":     clientUsers,
		"stats":     stats,
		"userCount": len(users),
	}
	_ = conn.WriteJSON(response)
}

// handleAdminBroadcast sends a system-wide message from an admin.
func handleAdminBroadcast(conn *websocket.Conn, user *models.User, req WSRequest) {
	if !isUserAdmin(user.Callsign) {
		sendErrorResponse(conn, "Access denied.")
		return
	}
	if req.Message == "" {
		sendErrorResponse(conn, "Broadcast message cannot be empty.")
		return
	}

	log.Printf("[WS ADMIN] User %s sending broadcast: %s", user.Callsign, req.Message)

	// Step 1: Store the message for every user for their history
	allUsers, err := db.LoadAllUsers()
	if err != nil {
		log.Printf("[DB] Failed to load all users for broadcast: %v", err)
		sendErrorResponse(conn, "Failed to load user list for broadcast.")
		return
	}

	for _, u := range allUsers {
		// Store with a special "from" callsign. The `to_callsign` is the actual user.
		err := db.StoreMessage(u.Callsign, "ADMIN", req.Message)
		if err != nil {
			log.Printf("[DB] Failed to store broadcast message for user %s: %v", u.Callsign, err)
			// Don't stop the whole broadcast for one user
		}
	}

	// Step 2: Broadcast to all currently connected clients
	payload := WSResponse{
		"aprs_msg":   true,
		"from":       "ADMIN",
		"to":         "BROADCAST", // Special 'to' field for clients
		"message":    req.Message,
		"created_at": time.Now().UTC().Format(time.RFC3339),
		"route":      []aprs.RouteHop{}, // Empty route
	}
	aprs.GetSessionsManager().BroadcastToAll(payload)

	// Step 3: Send confirmation to the admin who sent it
	sendSuccessResponse(conn, WSResponse{"message": "Broadcast sent to all users."})
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