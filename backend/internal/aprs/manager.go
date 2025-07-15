package aprs

import (
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"aprsmessenger-gateway/internal/db"
)

import aprsis "github.com/dustin/go-aprs/aprsis"

// APRSManager manages APRS-IS connections and message callbacks.
type APRSManager struct {
	conn      *aprsis.APRSIS
	connMu    sync.RWMutex
	stopCh    chan struct{}
	callbacks map[string]func(from, to, msg string, path []string) // Updated callback
	users     map[string]struct{}
	setMu     sync.RWMutex
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
		callbacks: make(map[string]func(from, to, msg string, path []string)), // Updated callback
		users:     make(map[string]struct{}),
		stopCh:    make(chan struct{}),
	}
}

// Start starts the APRSManager's background routines.
func (am *APRSManager) Start() {
	go am.run()
}

// SendMessage formats and sends an APRS message using the manager's connection.
// fromCallsign: the sending user's callsign (e.g. "OURUSER")
// recipientCallsign: the recipient's callsign (e.g. "RXUSER")
// message: the message text
func (am *APRSManager) SendMessage(fromCallsign, recipientCallsign, message string) error {
	// APRS message payload is limited to 67 characters
	if len(message) > 67 {
		message = message[:67]
	}

	// Recipient must be 9 chars, space-padded on the right.
	paddedRecipient := fmt.Sprintf("%-9s", strings.ToUpper(recipientCallsign))

	// Construct path: always use our gateway as the last hop
	// e.g., OURUSER>APRS,K8SDR*,qAC,K8SDR-10::RXUSER   :message
	const viaPath = "APRS,K8SDR*,qAC,K8SDR-10"

	// Format the APRS message packet
	packet := fmt.Sprintf("%s>%s::%s:%s", fromCallsign, viaPath, paddedRecipient, message)

	am.connMu.RLock()
	defer am.connMu.RUnlock()

	if am.conn == nil {
		return fmt.Errorf("APRS connection is not active")
	}

	log.Printf("[APRS SEND] Sending: %s", packet)
	return am.conn.SendRawPacket("%s", packet)
}

// run connects to APRS-IS and processes incoming packets.
func (am *APRSManager) run() {
	for {
		log.Printf("[APRS] Connecting to APRS-IS as K8SDR-10")
		conn, err := aprsis.Dial("tcp", "rotate.aprs.net:10152")
		if err != nil {
			log.Printf("[APRS] Connect failed for K8SDR-10: %v. Retrying in 10s.", err)
			time.Sleep(10 * time.Second)
			continue
		}

		if err := conn.Auth("K8SDR-10", "14750", ""); err != nil {
			log.Printf("[APRS] Auth failed for K8SDR-10: %v. Retrying in 10s.", err)
			conn.Close()
			time.Sleep(10 * time.Second)
			continue
		}

		am.connMu.Lock()
		am.conn = conn
		am.connMu.Unlock()

		log.Printf("[APRS] Connected and authenticated as K8SDR-10, listening for messages to active users")

		for {
			frame, err := conn.Next()
			if err != nil {
				log.Printf("[APRS] Error from APRS-IS: %v. Reconnecting in 10s.", err)
				break
			}
			line := frame.String()

			// Only process user-to-user messages and deliver via session broadcast
			msg, perr := ParseMessagePacket(line)
			if perr == nil && msg.IsUserMessage() {
				// Get base callsign for addressee (strip SSID)
				baseDest := baseCallsign(toUpperNoSpace(msg.Addressee))

				// Get all user callsigns (base and full) from DB
				userSet, err := db.UserCallsignSet()
				if err != nil {
					log.Printf("[APRS] Unable to load user callsign set: %v", err)
					continue
				}
				// Does the intended recipient match a user (by base or full callsign)?
				if _, ok := userSet[baseDest]; ok {
					// Store message to history
					if err := db.StoreMessage(msg.Addressee, msg.Source, msg.MessageText); err != nil {
						log.Printf("[APRS] Failed to store message for %s: %v", msg.Addressee, err)
					}
					// Push to user if online
					session := GetSessionsManager().GetSession(baseDest)
					if session != nil {
						// Only log if we are actually forwarding to a client (online)
						log.Printf("[APRS RAW] %s", line)
						// Pass the path to the broadcast
						session.BroadcastMessage(msg.Source, msg.Addressee, msg.MessageText, msg.Path, nil)
					}
				}
			}
			// Removed legacy callback delivery to avoid double messages
		}

		log.Printf("[APRS] Disconnected. Reconnecting in 10s.")
		am.connMu.Lock()
		if am.conn != nil {
			am.conn.Close()
			am.conn = nil
		}
		am.connMu.Unlock()
		time.Sleep(10 * time.Second)
	}
}

// RegisterUser registers a callback for a user's callsign.
func (am *APRSManager) RegisterUser(callsign string, cb func(from, to, msg string, path []string)) {
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

// baseCallsign strips SSID (-10 etc) from a callsign.
func baseCallsign(cs string) string {
	if idx := strings.Index(cs, "-"); idx != -1 {
		return cs[:idx]
	}
	return cs
}

// toUpperNoSpace returns uppercased callsign, trimmed.
func toUpperNoSpace(cs string) string {
	return strings.ToUpper(strings.TrimSpace(cs))
}