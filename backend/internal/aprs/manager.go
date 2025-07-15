package aprs

import (
	"log"
	"strings"
	"sync"
	"time"

	"aprsmessenger-gateway/internal/db"
	aprsis "github.com/dustin/go-aprs/aprsis"
)

// APRSManager manages APRS-IS connections and message callbacks.
type APRSManager struct {
	stopCh      chan struct{}
	callbacks   map[string]func(from, to, msg string)
	users       map[string]struct{}
	callsignSet map[string]struct{}
	setMu       sync.RWMutex
}

var (
	globalAPRSManager     *APRSManager
	globalAPRSManagerOnce = false
)

// GetAPRSManager returns the singleton APRSManager.
func GetAPRSManager() *APRSManager {
	if !globalAPRSManagerOnce {
		globalAPRSManager = NewAPRSManager()
		globalAPRSManagerOnce = true
	}
	return globalAPRSManager
}

// NewAPRSManager creates a new APRSManager instance.
func NewAPRSManager() *APRSManager {
	return &APRSManager{
		callbacks:   make(map[string]func(from, to, msg string)),
		users:       make(map[string]struct{}),
		stopCh:      make(chan struct{}),
		callsignSet: make(map[string]struct{}),
	}
}

// Start starts the APRSManager's background routines.
func (am *APRSManager) Start() {
	go am.refreshCallsignSet()
	go am.run()
}

// refreshCallsignSet periodically refreshes the set of known user callsigns from the DB.
func (am *APRSManager) refreshCallsignSet() {
	for {
		set, err := db.UserCallsignSet()
		if err == nil {
			am.setMu.Lock()
			am.callsignSet = set
			am.setMu.Unlock()
		} else {
			log.Printf("[APRS] Failed to refresh callsign set: %v", err)
		}
		time.Sleep(30 * time.Second)
	}
}

// inCallsignSet returns true if the provided callsign (any SSID) is in the callsign set.
func (am *APRSManager) inCallsignSet(callsign string) bool {
	am.setMu.RLock()
	defer am.setMu.RUnlock()
	// Check both full and base callsign (no SSID)
	if _, ok := am.callsignSet[toUpperNoSpace(callsign)]; ok {
		return true
	}
	base := baseCallsign(toUpperNoSpace(callsign))
	if _, ok := am.callsignSet[base]; ok {
		return true
	}
	return false
}

// baseCallsign strips SSID (-10 etc) from a callsign.
func baseCallsign(cs string) string {
	if idx := index(cs, "-"); idx != -1 {
		return cs[:idx]
	}
	return cs
}

// toUpperNoSpace returns uppercased callsign, trimmed.
func toUpperNoSpace(cs string) string {
	return strings.ToUpper(strings.TrimSpace(cs))
}

// index returns index of substr in str or -1.
func index(str, substr string) int {
	return strings.Index(str, substr)
}

// run connects to APRS-IS and processes incoming packets.
func (am *APRSManager) run() {
	for {
		log.Printf("[APRS] Connecting to APRS-IS as K8SDR-10")
		conn, err := aprsis.Dial("tcp", "rotate.aprs.net:10152")
		if err != nil {
			log.Printf("[APRS] Connect failed for K8SDR-10: %v. Retrying in 10s.", err)
			select {
			case <-am.stopCh:
				return
			case <-time.After(10 * time.Second):
				continue
			}
		}
		if err := conn.Auth("K8SDR-10", "14750", ""); err != nil {
			log.Printf("[APRS] Auth failed for K8SDR-10: %v. Retrying in 10s.", err)
			conn.Close()
			select {
			case <-am.stopCh:
				return
			case <-time.After(10 * time.Second):
				continue
			}
		}

		log.Printf("[APRS] Connected and authenticated as K8SDR-10, listening for messages to active users")

		for {
			frame, err := conn.Next()
			if err != nil {
				log.Printf("[APRS] Error from APRS-IS: %v. Reconnecting in 10s.", err)
				break
			}
			line := frame.String()

			msg, perr := ParseMessagePacket(line)
			if perr == nil && msg.IsUserMessage() {
				// Get the base callsign of the message recipient
				baseDest := baseCallsign(toUpperNoSpace(msg.Addressee))

				am.setMu.RLock()
				cb, ok := am.callbacks[baseDest]
				am.setMu.RUnlock()

				if ok {
					log.Printf("[APRS DISPATCH] %s -> %s: %s", msg.Source, msg.Addressee, msg.MessageText)
					// Execute the callback in a new goroutine to avoid blocking the listener loop.
					// This callback will send the message over the websocket.
					go cb(msg.Source, msg.Addressee, msg.MessageText)
				}
			}
		}
		log.Printf("[APRS] Disconnected global. Reconnecting in 10s.")
		conn.Close()
		select {
		case <-am.stopCh:
			return
		case <-time.After(10 * time.Second):
		}
	}
}

// RegisterUser registers a callback for a user's callsign.
func (am *APRSManager) RegisterUser(callsign string, cb func(from, to, msg string)) {
	am.setMu.Lock()
	defer am.setMu.Unlock()
	cleanCallsign := toUpperNoSpace(callsign)
	am.users[cleanCallsign] = struct{}{}
	am.callbacks[cleanCallsign] = cb
	log.Printf("[APRS Manager] Registered callback for %s", cleanCallsign)
}

// UnregisterUser removes a user's callback registration.
func (am *APRSManager) UnregisterUser(callsign string) {
	am.setMu.Lock()
	defer am.setMu.Unlock()
	cleanCallsign := toUpperNoSpace(callsign)
	delete(am.users, cleanCallsign)
	delete(am.callbacks, cleanCallsign)
	log.Printf("[APRS Manager] Unregistered callback for %s", cleanCallsign)
}