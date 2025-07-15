package aprs

import (
	"log"
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

// AttachWebSocket attaches a websocket client to this session, registering with global APRS manager
func (s *Session) AttachWebSocket(ws *websocket.Conn) {
	s.wsMu.Lock()
	s.wsClients[ws] = struct{}{}
	s.wsMu.Unlock()
	log.Printf("[APRS] WebSocket attached to session %s", s.Callsign)
	go s.keepAliveWS(ws)

	// Register callback with global APRS manager
	GetAPRSManager().RegisterUser(s.Callsign, func(from, to, msg string) {
		// Save to DB before deliver
		if err := db.StoreMessage(to, from, msg); err != nil {
			log.Printf("[APRS] Failed to store message for %s: %v", to, err)
		}
		s.broadcastWSMessage(from, to, msg)
	})
	// On attach, send any undelivered messages from DB
	go s.deliverUndeliveredHistory(ws)
}

// keepAliveWS sends pings and removes ws client on disconnect.
func (s *Session) keepAliveWS(ws *websocket.Conn) {
	defer func() {
		s.wsMu.Lock()
		delete(s.wsClients, ws)
		s.wsMu.Unlock()
		log.Printf("[APRS] WebSocket detached from session %s", s.Callsign)
	}()
	for {
		time.Sleep(5 * time.Second)
		if err := ws.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(time.Second)); err != nil {
			break
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

// deliverUndeliveredHistory sends any undelivered messages from DB to the websocket, and marks them delivered.
func (s *Session) deliverUndeliveredHistory(ws *websocket.Conn) {
	messages, err := db.ListUndeliveredMessages(s.Callsign)
	if err != nil {
		log.Printf("[APRS] Failed to fetch undelivered messages for %s: %v", s.Callsign, err)
		return
	}
	if len(messages) == 0 {
		return
	}
	var ids []int
	for _, m := range messages {
		resp := map[string]interface{}{
			"aprs_msg": true,
			"from":     m.FromCallsign,
			"to":       m.ToCallsign,
			"message":  m.Message,
			"history":  true,
			"created_at": m.CreatedAt.Format(time.RFC3339),
		}
		_ = ws.WriteJSON(resp)
		ids = append(ids, m.ID)
	}
	_ = db.MarkMessagesDelivered(ids)
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