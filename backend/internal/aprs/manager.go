package aprs

import (
	"fmt"
	"log"
	"net"
	"strings"
	"sync"
	"time"
)

// APRSManager manages APRS-IS connections and message callbacks.
type APRSManager struct {
	conn      net.Conn // Use the standard library's net.Conn
	connMu    sync.RWMutex
	stopCh    chan struct{}
	callbacks map[string]func(from, to, msg string)
	users     map[string]struct{}
	setMu     sync.RWMutex
}

// ... (GetAPRSManager, NewAPRSManager, and Start are unchanged) ...

// SendMessage formats and sends an APRS message on behalf of a user.
func (am *APRSManager) SendMessage(fromCallsign, recipientCallsign, message string) error {
	// APRS message payload is limited to 67 characters
	if len(message) > 67 {
		message = message[:67]
	}

	// Recipient must be 9 chars, space-padded on the right.
	paddedRecipient := fmt.Sprintf("%-9s", strings.ToUpper(recipientCallsign))

	// *** THIS IS THE FIX ***
	// Format the packet so the user is the source, and the gateway is in the path.
	// Format: USER>APRS,TCPIP,GATEWAY*::RECIPIENT  :message text
	packet := fmt.Sprintf("%s>APRS,TCPIP,K8SDR-10*::%s:%s\r\n", fromCallsign, paddedRecipient, message)

	am.connMu.RLock()
	defer am.connMu.RUnlock()

	if am.conn == nil {
		return fmt.Errorf("APRS connection is not active")
	}

	log.Printf("[APRS SEND] Sending: %s", strings.TrimSpace(packet))
	_, err := am.conn.Write([]byte(packet))
	return err
}

// ... (The rest of the file is unchanged) ...
// (Full file content is provided below for completeness)

var (
	globalAPRSManager     *APRSManager
	globalAPRSManagerOnce = false
)

func GetAPRSManager() *APRSManager {
	if !globalAPRSManagerOnce {
		globalAPRSManager = NewAPRSManager()
		globalAPRSManagerOnce = true
	}
	return globalAPRSManager
}

func NewAPRSManager() *APRSManager {
	return &APRSManager{
		callbacks: make(map[string]func(from, to, msg string)),
		users:     make(map[string]struct{}),
		stopCh:    make(chan struct{}),
	}
}

func (am *APRSManager) Start() {
	go am.run()
}

func (am *APRSManager) run() {
	for {
		log.Printf("[APRS] Connecting to APRS-IS as K8SDR-10")
		conn, linesCh, err := ConnectAndLogin("rotate.aprs.net:10152", "K8SDR-10", "14750", "b/K8SDR*") // Listen for messages to any K8SDR-xx user
		if err != nil {
			log.Printf("[APRS] Connect/Login failed: %v. Retrying in 10s.", err)
			time.Sleep(10 * time.Second)
			continue
		}

		am.connMu.Lock()
		am.conn = conn
		am.connMu.Unlock()

		log.Printf("[APRS] Connected and authenticated as K8SDR-10, listening for messages.")

		for line := range linesCh {
			if strings.HasPrefix(line, "#") {
				continue
			}

			msg, perr := ParseMessagePacket(line)
			if perr == nil && msg.IsUserMessage() {
				fullDest := toUpperNoSpace(msg.Addressee)
				baseDest := baseCallsign(fullDest)
				
				am.setMu.RLock()
				// First try exact SSID match, then fallback to base callsign
				cb, ok := am.callbacks[fullDest]
				if !ok {
					cb, ok = am.callbacks[baseDest]
				}
				am.setMu.RUnlock()

				if ok {
					log.Printf("[APRS DISPATCH] %s -> %s: %s", msg.Source, msg.Addressee, msg.MessageText)
					go cb(msg.Source, msg.Addressee, msg.MessageText)
				}
			}
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

func (am *APRSManager) RegisterUser(callsign string, cb func(from, to, msg string)) {
	am.setMu.Lock()
	defer am.setMu.Unlock()
	cleanCallsign := toUpperNoSpace(callsign)
	am.users[cleanCallsign] = struct{}{}
	am.callbacks[cleanCallsign] = cb
	log.Printf("[APRS Manager] Registered callback for %s", cleanCallsign)
}

func (am *APRSManager) UnregisterUser(callsign string) {
	am.setMu.Lock()
	defer am.setMu.Unlock()
	cleanCallsign := toUpperNoSpace(callsign)
	delete(am.users, cleanCallsign)
	delete(am.callbacks, cleanCallsign)
	log.Printf("[APRS Manager] Unregistered callback for %s", cleanCallsign)
}

func baseCallsign(cs string) string {
	if idx := strings.Index(cs, "-"); idx != -1 {
		return cs[:idx]
	}
	return cs
}

func toUpperNoSpace(cs string) string {
	return strings.ToUpper(strings.TrimSpace(cs))
}