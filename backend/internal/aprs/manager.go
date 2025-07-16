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

    // Print the raw packet being sent (including for ACKs)
    log.Printf("[APRS RAW PACKET] %s", packet)

    am.connMu.RLock()
    defer am.connMu.RUnlock()

    if am.conn == nil {
        return fmt.Errorf("APRS connection is not active")
    }

    log.Printf("[APRS SEND] Sending: %s", packet)
    return am.conn.SendRawPacket("%s", packet)
}

// --- Begin: Message Delivery State & Deduplication ---

// For deduplication and delivery state (shared with ws package)
type deliveryState struct {
    mu        sync.Mutex
    lastMsgId map[string]map[string]string // myCallsign -> contact -> last received messageId
    retries   map[string]map[string]map[string]int // myCallsign -> contact -> msgId -> retry count
}

var globalDeliveryState = &deliveryState{
    lastMsgId: make(map[string]map[string]string),
    retries:   make(map[string]map[string]map[string]int),
}

func (ds *deliveryState) updateLastReceived(myCall, contact, msgId string) {
    ds.mu.Lock()
    defer ds.mu.Unlock()
    if ds.lastMsgId[myCall] == nil {
        ds.lastMsgId[myCall] = make(map[string]string)
    }
    ds.lastMsgId[myCall][contact] = msgId
}

func (ds *deliveryState) getLastReceived(myCall, contact string) string {
    ds.mu.Lock()
    defer ds.mu.Unlock()
    if ds.lastMsgId[myCall] == nil {
        return ""
    }
    return ds.lastMsgId[myCall][contact]
}

func (ds *deliveryState) incRetry(myCall, contact, msgId string) int {
    ds.mu.Lock()
    defer ds.mu.Unlock()
    if ds.retries[myCall] == nil {
        ds.retries[myCall] = make(map[string]map[string]int)
    }
    if ds.retries[myCall][contact] == nil {
        ds.retries[myCall][contact] = make(map[string]int)
    }
    ds.retries[myCall][contact][msgId]++
    return ds.retries[myCall][contact][msgId]
}

// --- End: Message Delivery State & Deduplication ---

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
                baseSrc := baseCallsign(toUpperNoSpace(msg.Source))

                // Get all user callsigns (base and full) from DB
                userSet, err := db.UserCallsignSet()
                if err != nil {
                    log.Printf("[APRS] Unable to load user callsign set: %v", err)
                    continue
                }

                // Does the intended recipient match a user (by base or full callsign)?
                if _, ok := userSet[baseDest]; ok {
                    // --- NEW: Message ID (MsgNo) and REPLY-ACK Handling ---
                    isDuplicate := false
                    retryCount := 0
                    msgId := msg.MsgNo
                    ackId := msg.AckMsgNo
                    myCallsign := baseDest
                    contactCallsign := baseSrc

                    // Check for duplicate (already processed msgId from this contact)
                    if msgId != "" {
                        lastReceived := globalDeliveryState.getLastReceived(myCallsign, contactCallsign)
                        if lastReceived == msgId {
                            // Duplicate!
                            isDuplicate = true
                            retryCount = globalDeliveryState.incRetry(myCallsign, contactCallsign, msgId)
                        } else {
                            globalDeliveryState.updateLastReceived(myCallsign, contactCallsign, msgId)
                        }
                    }

                    // Store message to history (even duplicates for audit)
                    if err := db.StoreMessage(msg.Addressee, msg.Source, msg.MessageText); err != nil {
                        log.Printf("[APRS] Failed to store message for %s: %v", msg.Addressee, err)
                    }

                    session := GetSessionsManager().GetSession(baseDest)
                    if session != nil {
                        // Only log if we are actually forwarding to a client (online)
                        log.Printf("[APRS RAW] %s", line)

                        if isDuplicate && msgId != "" {
                            // Send special WebSocket notification for retry
                            notif := map[string]interface{}{
                                "type":               "message_retry_received",
                                "contact_groupingId": contactCallsign,
                                "messageId":          msgId,
                            }
                            session.SendAll(notif)
                        } else {
                            // Standard message delivery
                            payload := map[string]interface{}{
                                "aprs_msg":   true,
                                "from":       msg.Source,
                                "to":         msg.Addressee,
                                "message":    msg.MessageText,
                                "messageId":  msgId,
                                "ackId":      ackId,
                                "created_at": time.Now().UTC().Format(time.RFC3339),
                                "retryCount": retryCount,
                                // route and other fields can be added as needed
                            }
                            session.SendAll(payload)

                            // Also: send "message_status_update" if this is replying to our sent message (REPLY-ACK)
                            if ackId != "" {
                                statusUpdate := map[string]interface{}{
                                    "type":               "message_status_update",
                                    "contact_groupingId": contactCallsign,
                                    "messageId":          ackId,
                                    "status":             "delivered",
                                }
                                session.SendAll(statusUpdate)
                            }
                        }

                        // Always send APRS ack packet for compatibility if we got a message with a msgId
                        if msgId != "" {
                            ackPayload := fmt.Sprintf("ack%s", msgId)
                            // Print the raw ACK packet for visibility (redundant, but for clarity here)
                            log.Printf("[APRS RAW PACKET] %s", fmt.Sprintf("%s>%s::%s:%s",
                                msg.Addressee, "APRS,K8SDR*,qAC,K8SDR-10", fmt.Sprintf("%-9s", strings.ToUpper(msg.Source)), ackPayload))
                            am.SendMessage(msg.Addressee, msg.Source, ackPayload)
                        }
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