package aprs

import (
	"log"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"aprsmessenger-gateway/internal/db"
)

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
	// If this is the first client, register the user with the APRS listener
	if len(s.wsClients) == 0 {
		log.Printf("[APRS] First WebSocket attached, registering callback for %s", s.Callsign)
		GetAPRSManager().RegisterUser(s.Callsign, func(from, to, msg string) {
			if err := db.StoreMessage(to, from, msg); err != nil {
				log.Printf("[APRS] Failed to store message for %s: %v", to, err)
			}
			s.broadcastWSMessage(from, to, msg)
		})
	}
	s.wsClients[ws] = struct{}{}
	s.wsMu.Unlock()
	log.Printf("[APRS] WebSocket attached to session %s", s.Callsign)

	go s.keepAliveWS(ws)
	// *** REPLACE THE GOROUTINE CALL ***
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

// broadcastWSMessage sends a received APRS message to all attached websockets.
func (s *Session) broadcastWSMessage(from, to, msg string) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()
	if len(s.wsClients) == 0 {
		return
	}
	resp := map[string]interface{}{
		"aprs_msg": true,
		"from":     from,
		"to":       to,
		"message":  msg,
	}
	for ws := range s.wsClients {
		_ = ws.WriteJSON(resp)
	}
}

// *** REPLACE deliverUndeliveredHistory with this new deliverHistory function ***
// deliverHistory sends the full conversation history to the websocket and marks
// any new incoming messages as delivered.
func (s *Session) deliverHistory(ws *websocket.Conn) {
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
			"history":    true,
			"created_at": m.CreatedAt.Format(time.RFC3339),
		}
		if err := ws.WriteJSON(resp); err != nil {
			log.Printf("Error sending history to %s: %v", s.Callsign, err)
			return // Stop trying if connection is bad
		}

		// Check if this message was an undelivered INCOMING message.
		isIncoming := m.ToCallsign == s.Callsign || strings.HasPrefix(m.ToCallsign, s.Callsign+"-")
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
	sessions map[string]*Session
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
		sessions: make(map[string]*Session),
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