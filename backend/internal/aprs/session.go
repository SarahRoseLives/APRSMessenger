package aprs

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"aprsmessenger-gateway/internal/db"

	"github.com/gorilla/websocket"
)

// RouteHop represents a single hop in a message's path for JSON marshalling.
// We are only sending the callsign for now. Lat/Lon are placeholders for future use.
type RouteHop struct {
	Callsign string  `json:"callsign"`
	Lat      float64 `json:"lat,omitempty"`
	Lon      float64 `json:"lon,omitempty"`
}

// Session represents an in-memory structure for a user's websocket and message delivery
type Session struct {
	Callsign string

	wsMu      sync.Mutex
	wsClients map[*websocket.Conn]struct{}
}

// NewSession creates a new session for a user callsign.
func NewSession(callsign string) *Session {
	return &Session{
		Callsign:  callsign,
		wsClients: make(map[*websocket.Conn]struct{}),
	}
}

// AttachWebSocket attaches a websocket client to this session.
// It registers the user with the global APRS manager on the first connection.
func (s *Session) AttachWebSocket(ws *websocket.Conn) {
	s.wsMu.Lock()
	// If this is the first client, register the user with the global APRS listener
	if len(s.wsClients) == 0 {
		log.Printf("[APRS] First WebSocket attached, registering callback for %s", s.Callsign)
		GetAPRSManager().RegisterUser(s.Callsign, func(from, to, msg string, path []string) {
			if err := db.StoreMessage(to, from, msg); err != nil {
				log.Printf("[APRS] Failed to store message for %s: %v", to, err)
			}
			// Broadcast incoming messages to all clients, with no exclusions.
			s.BroadcastMessage(from, to, msg, path, nil)
		})
	}
	s.wsClients[ws] = struct{}{}
	s.wsMu.Unlock()
	log.Printf("[APRS] WebSocket attached to session %s", s.Callsign)

	go s.keepAliveWS(ws)
	go s.deliverHistory(ws)
}

// DetachWebSocket removes a websocket client from the session.
// It unregisters the user from the global APRS manager if it's the last client.
func (s *Session) DetachWebSocket(ws *websocket.Conn) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()

	if _, ok := s.wsClients[ws]; !ok {
		return // Already detached
	}

	delete(s.wsClients, ws)
	log.Printf("[APRS] WebSocket detached from session %s. Remaining clients: %d", s.Callsign, len(s.wsClients))

	if len(s.wsClients) == 0 {
		GetAPRSManager().UnregisterUser(s.Callsign)
		log.Printf("[APRS] Last WebSocket detached, unregistered callback for %s", s.Callsign)
	}
}

// keepAliveWS sends pings and removes the websocket client on disconnect.
func (s *Session) keepAliveWS(ws *websocket.Conn) {
	defer s.DetachWebSocket(ws)
	for {
		time.Sleep(30 * time.Second)
		if err := ws.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(10*time.Second)); err != nil {
			log.Printf("[APRS] Ping failed for %s, closing keep-alive.", s.Callsign)
			return
		}
	}
}

// BroadcastMessage sends a message to all attached websockets, optionally excluding one.
func (s *Session) BroadcastMessage(from, to, msg string, path []string, exclude *websocket.Conn) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()

	if len(s.wsClients) == 0 {
		return
	}

	var routeHops []RouteHop
	// Build the full visual route: [from, ...path, to]
	fullRoute := []string{from}
	if path != nil {
		fullRoute = append(fullRoute, path...)
	}
	fullRoute = append(fullRoute, to)

	// Remove duplicates and clean up path markers (e.g., WIDE2-2*)
	seen := make(map[string]bool)
	uniqueRoute := []string{}
	for _, hop := range fullRoute {
		cleanHop := strings.TrimRight(hop, "*")
		if !seen[cleanHop] {
			seen[cleanHop] = true
			uniqueRoute = append(uniqueRoute, cleanHop)
		}
	}

	for _, hopCallsign := range uniqueRoute {
		// In the future, you could look up coordinates for each hopCallsign here.
		routeHops = append(routeHops, RouteHop{Callsign: hopCallsign})
	}

	resp := map[string]interface{}{
		"aprs_msg":   true,
		"from":       from,
		"to":         to,
		"message":    msg,
		"created_at": time.Now().UTC().Format(time.RFC3339),
		"route":      routeHops,
	}

	for ws := range s.wsClients {
		if ws != exclude {
			_ = ws.WriteJSON(resp)
		}
	}
}

// deliverHistory sends the full conversation history to the websocket and marks
// any new incoming messages as delivered.
func (s *Session) deliverHistory(ws *websocket.Conn) {
	// Use the new function to get all messages for the user.
	messages, err := db.ListAllMessagesForUser(s.Callsign)
	if err != nil {
		log.Printf("[APRS] Failed to fetch full history for %s: %v", s.Callsign, err)
		return
	}
	if len(messages) == 0 {
		return
	}

	log.Printf("[APRS] Delivering %d history messages to %s", len(messages), s.Callsign)
	var undeliveredIDs []int
	for _, m := range messages {
		resp := map[string]interface{}{
			"aprs_msg":   true,
			"from":       m.FromCallsign,
			"to":         m.ToCallsign,
			"message":    m.Message,
			"history":    true, // Mark as history so client can suppress notifications
			"created_at": m.CreatedAt.Format(time.RFC3339),
		}
		if err := ws.WriteJSON(resp); err != nil {
			log.Printf("Error sending history to %s: %v", s.Callsign, err)
			return // Stop trying if connection is bad
		}

		// Check if this message was an undelivered INCOMING message.
		// The base callsign of the recipient must match our session's callsign.
		toBaseCallsign := strings.Split(m.ToCallsign, "-")[0]
		isIncoming := toBaseCallsign == s.Callsign
		if isIncoming && !m.IsDelivered {
			undeliveredIDs = append(undeliveredIDs, m.ID)
		}
	}

	// Mark only the new incoming messages as delivered.
	if len(undeliveredIDs) > 0 {
		_ = db.MarkMessagesDelivered(undeliveredIDs)
		log.Printf("[APRS] Marked %d messages as delivered for %s", len(undeliveredIDs), s.Callsign)
	}
}

// SessionsManager manages all in-memory user sessions.
type SessionsManager struct {
	sync.Mutex
	sessions   map[string]*Session
	tokenMu    sync.Mutex
	tokenStore map[string]string // token -> callsign
}

var (
	sessionsManager     *SessionsManager
	sessionsManagerOnce sync.Once
)

// GetSessionsManager returns the global in-memory sessions manager singleton.
func GetSessionsManager() *SessionsManager {
	sessionsManagerOnce.Do(func() {
		sessionsManager = NewSessionsManager()
	})
	return sessionsManager
}

func NewSessionsManager() *SessionsManager {
	return &SessionsManager{
		sessions:   make(map[string]*Session),
		tokenStore: make(map[string]string),
	}
}

// EnsureSession returns a session for the callsign (creates if needed)
func (sm *SessionsManager) EnsureSession(callsign string) *Session {
	sm.Lock()
	defer sm.Unlock()
	session, exists := sm.sessions[callsign]
	if !exists {
		session = NewSession(callsign)
		sm.sessions[callsign] = session
	}
	return session
}

// GetSession returns a session if it exists
func (sm *SessionsManager) GetSession(callsign string) *Session {
	sm.Lock()
	defer sm.Unlock()
	return sm.sessions[callsign]
}

// GenerateSessionToken creates a new, random token for a user.
// Token remains valid until it is used for login (single-use).
func (sm *SessionsManager) GenerateSessionToken(callsign string) (string, error) {
	b := make([]byte, 16) // 128 bits of randomness
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	token := hex.EncodeToString(b)

	sm.tokenMu.Lock()
	defer sm.tokenMu.Unlock()

	sm.tokenStore[token] = callsign
	log.Printf("[AUTH] Generated session token for %s", callsign)

	// No auto-expiry. Token will be deleted after successful login (see ValidateAndUseToken).

	return token, nil
}

// ValidateAndUseToken checks if a token is valid, returns the associated callsign,
// and immediately deletes the token to make it single-use.
func (sm *SessionsManager) ValidateAndUseToken(token string) (string, error) {
	sm.tokenMu.Lock()
	defer sm.tokenMu.Unlock()

	callsign, ok := sm.tokenStore[token]
	if !ok {
		return "", fmt.Errorf("invalid or expired token")
	}

	// Token is single-use, so delete it immediately.
	delete(sm.tokenStore, token)
	log.Printf("[AUTH] Validated and consumed session token for %s", callsign)

	return callsign, nil
}