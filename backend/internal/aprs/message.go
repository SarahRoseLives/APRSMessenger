package aprs

import (
	"regexp"
	"strings"
)

// MessagePacket represents a parsed APRS message packet.
type MessagePacket struct {
	// Common
	Format       string // "message", "bulletin", "group-bulletin", "announcement", "telemetry"
	Source       string
	Path         []string // The digipeater path
	Addressee    string
	MessageText  string
	MsgNo        string // Message number or ID
	AckMsgNo     string // Optional reply-ack message number
	Response     string // "ack" or "rej" if this is an ack/rej response
	BulletinID   string
	GroupID      string
	Announcement string
	Telemetry    map[string]string // If this is a telemetry config message
	Raw          string
}

// ParseMessagePacket parses the body of an APRS message info field (after the header) into a MessagePacket.
// The "line" parameter should be the full APRS-IS frame (SRC>DST,PATH:info).
// If you pass "" as line, source will not be filled.
func ParseMessagePacket(line string) (*MessagePacket, error) {
	packet := &MessagePacket{
		Telemetry: make(map[string]string),
		Raw:       line,
	}

	// Split header/info
	headerIdx := strings.Index(line, ":")
	if headerIdx < 0 {
		return nil, ErrNotAMessagePacket
	}
	header := ""
	if headerIdx > 0 {
		header = line[:headerIdx]
	}
	info := line[headerIdx+1:]

	// Get the source callsign and path, if present
	if strings.Contains(header, ">") {
		parts := strings.SplitN(header, ">", 2)
		packet.Source = parts[0]
		// The path is the part after '>', e.g. "APRS,K8SDR*,qAC,K8SDR-10"
		pathStr := parts[1]
		packet.Path = strings.Split(pathStr, ",")
	}

	// 0. User message: :TARGET   :message or :TARGET   :message{NN}
	userMsgRe := regexp.MustCompile(`^:([A-Za-z0-9 \-]{9}):(.*)$`)
	if m := userMsgRe.FindStringSubmatch(info); m != nil {
		packet.Addressee = strings.TrimRight(m[1], " ")
		body := strings.TrimSpace(m[2])
		// Try to extract trailing {NN} (classic format)
		msgWithIdRe := regexp.MustCompile(`^(.*)\{([A-Za-z0-9]{2,5})}$`)
		if m2 := msgWithIdRe.FindStringSubmatch(body); m2 != nil {
			packet.Format = "message"
			packet.MessageText = strings.TrimSpace(m2[1])
			packet.MsgNo = m2[2]
			return packet, nil
		}
		// Otherwise, regular message
		packet.Format = "message"
		packet.MessageText = body
		return packet, nil
	}

	// 1. Bulletin (BLNn[group]): ^BLN([0-9])([a-z0-9_ \-]{5}):(.{0,67})
	bulletinRe := regexp.MustCompile(`^BLN([0-9])([a-z0-9_ \-]{5}):(.{0,67})`)
	if m := bulletinRe.FindStringSubmatch(info); m != nil {
		packet.BulletinID = m[1]
		packet.GroupID = strings.TrimRight(m[2], " ")
		packet.MessageText = strings.TrimSpace(m[3])
		if packet.GroupID == "" {
			packet.Format = "bulletin"
		} else {
			packet.Format = "group-bulletin"
		}
		return packet, nil
	}

	// 2. Announcement (BLNA[group]): ^BLN([A-Z])([a-zA-Z0-9_ \-]{5}):(.{0,67})
	announceRe := regexp.MustCompile(`^BLN([A-Z])([a-zA-Z0-9_ \-]{5}):(.{0,67})`)
	if m := announceRe.FindStringSubmatch(info); m != nil {
		packet.Announcement = m[1]
		packet.GroupID = strings.TrimRight(m[2], " ")
		packet.MessageText = strings.TrimSpace(m[3])
		packet.Format = "announcement"
		return packet, nil
	}

	// 3. Addressee: ^([a-zA-Z0-9_ \-]{9}):(.*)$
	addrRe := regexp.MustCompile(`^([a-zA-Z0-9_ \-]{9}):(.*)$`)
	if m := addrRe.FindStringSubmatch(info); m != nil {
		packet.Addressee = strings.TrimRight(m[1], " ")
		body := m[2]

		// 3a. Telemetry config messages (PARM, UNIT, EQNS, BITS)
		if tcfg, telemetryType := parseTelemetryConfig(body); telemetryType != "" {
			packet.Format = "telemetry"
			packet.Telemetry = tcfg
			packet.MessageText = body
			return packet, nil
		}

		// 3b. NEW replay-ack: ^(ack|rej)([A-Za-z0-9]{2})}([A-Za-z0-9]{2})?$
		newAckRe := regexp.MustCompile(`^(ack|rej)([A-Za-z0-9]{2})}([A-Za-z0-9]{2})?$`)
		if m2 := newAckRe.FindStringSubmatch(body); m2 != nil {
			packet.Format = "message"
			packet.Response = m2[1]
			packet.MsgNo = m2[2]
			packet.AckMsgNo = m2[3] // may be empty
			return packet, nil
		}

		// 3c. Standard ack/rej: ^(ack|rej)([A-Za-z0-9]{1,5})$
		stdAckRe := regexp.MustCompile(`^(ack|rej)([A-Za-z0-9]{1,5})$`)
		if m2 := stdAckRe.FindStringSubmatch(body); m2 != nil {
			packet.Format = "message"
			packet.Response = m2[1]
			packet.MsgNo = m2[2]
			return packet, nil
		}

		// 3d. New message format: text{MM}AA
		newMsgRe := regexp.MustCompile(`^(.*)\{([A-Za-z0-9]{2})}([A-Za-z0-9]{2})?$`)
		if m2 := newMsgRe.FindStringSubmatch(body); m2 != nil {
			packet.Format = "message"
			packet.MessageText = strings.TrimSpace(m2[1])
			packet.MsgNo = m2[2]
			packet.AckMsgNo = m2[3] // may be empty
			return packet, nil
		}

		// 3e. Old message format: text{msgNo}
		oldMsgRe := regexp.MustCompile(`^(.*)\{([A-Za-z0-9]{1,5})$`)
		if m2 := oldMsgRe.FindStringSubmatch(body); m2 != nil {
			packet.Format = "message"
			packet.MessageText = strings.TrimSpace(m2[1])
			packet.MsgNo = m2[2]
			return packet, nil
		}

		// 3f. Regular message (no message number)
		packet.Format = "message"
		packet.MessageText = strings.TrimSpace(body)
		return packet, nil
	}

	// Not a recognized packet
	return nil, ErrNotAMessagePacket
}

// parseTelemetryConfig parses telemetry config lines (PARM/UNIT/EQNS/BITS) and returns a map if found.
func parseTelemetryConfig(body string) (map[string]string, string) {
	// APRS Telemetry config lines (examples):
	// :N3MIM:PARM.Battery,BTemp,AirTemp,Pres,Altude,Camra,Chute,Sun,10m,ATV
	// :N3MIM:UNIT.Volts,deg.F,deg.F,Mbar,Kfeet,Clik,OPEN!,on,on,high
	// :N3MIM:EQNS.0,2.6,0,0,.53,-32,3,4.39,49,-32,3,18,1,2,3
	// :N3MIM:BITS.10110101,PROJECT TITLE...
	if strings.HasPrefix(body, "PARM.") {
		return map[string]string{"PARM": strings.TrimPrefix(body, "PARM.")}, "PARM"
	}
	if strings.HasPrefix(body, "UNIT.") {
		return map[string]string{"UNIT": strings.TrimPrefix(body, "UNIT.")}, "UNIT"
	}
	if strings.HasPrefix(body, "EQNS.") {
		return map[string]string{"EQNS": strings.TrimPrefix(body, "EQNS.")}, "EQNS"
	}
	if strings.HasPrefix(body, "BITS.") {
		return map[string]string{"BITS": strings.TrimPrefix(body, "BITS.")}, "BITS"
	}
	return nil, ""
}

// IsUserMessage returns true if this message is a user-to-user message (not bulletin, announcement, or telemetry).
func (m *MessagePacket) IsUserMessage() bool {
	return m.Format == "message" && m.Addressee != "" && !strings.HasPrefix(m.Addressee, "BLN")
}

// ErrNotAMessagePacket is returned if the packet is not a recognized APRS message packet.
var ErrNotAMessagePacket = &ParseError{"not a recognized APRS message packet"}

// ParseError represents a parse error for APRS message packets.
type ParseError struct{ msg string }

func (e *ParseError) Error() string { return e.msg }