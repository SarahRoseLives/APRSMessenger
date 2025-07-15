package aprs

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"time"
)

// Connects to APRS-IS and returns the connection and a channel for incoming lines (authenticated version).
func ConnectAndLogin(server, loginCallsign, passcode, filter string) (net.Conn, chan string, error) {
	conn, err := net.DialTimeout("tcp", server, 10*time.Second)
	if err != nil {
		return nil, nil, err
	}

	loginLine := fmt.Sprintf("user %s pass %s vers aprsmessenger-gateway 1.0 filter %s\r\n", loginCallsign, passcode, filter)
	_, err = conn.Write([]byte(loginLine))
	if err != nil {
		conn.Close()
		return nil, nil, err
	}

	lines := make(chan string)
	go func() {
		scanner := bufio.NewScanner(conn)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
		close(lines)
	}()
	return conn, lines, nil
}

// Connects to APRS-IS in listen-only (no login required for read-only).
// Returns the connection and a channel for incoming lines.
func ConnectAndListen(server, callsign, filter string) (net.Conn, chan string, error) {
	conn, err := net.DialTimeout("tcp", server, 10*time.Second)
	if err != nil {
		return nil, nil, err
	}

	loginLine := fmt.Sprintf("user %s pass -1 vers aprsmessenger-gateway-listener 1.0 filter %s\r\n", callsign, filter)
	_, err = conn.Write([]byte(loginLine))
	if err != nil {
		conn.Close()
		return nil, nil, err
	}

	lines := make(chan string)
	go func() {
		scanner := bufio.NewScanner(conn)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
		close(lines)
	}()
	return conn, lines, nil
}

// ParseAPRSMessage parses an APRS-IS line for a message.
// Returns from, to, msg, ok.
func ParseAPRSMessage(line string) (from, to, msg string, ok bool) {
	// Ignore comments and blank lines
	if strings.HasPrefix(line, "#") || !strings.Contains(line, ":") {
		return "", "", "", false
	}
	parts := strings.SplitN(line, ":", 2)
	header := parts[0]
	body := parts[1]

	// Header: SRC>DST,PATH
	headerParts := strings.SplitN(header, ">", 2)
	if len(headerParts) < 2 {
		return "", "", "", false
	}
	from = headerParts[0]
	destination := headerParts[1]
	dstParts := strings.SplitN(destination, ",", 2)
	to = dstParts[0]

	// Message body format: ":TOxxxxxxx:message"
	if len(body) > 10 && body[0] == ':' && body[9] == ':' {
		target := strings.TrimSpace(body[1:9]) // always 9 chars, may be space-padded
		msg = strings.TrimSpace(body[10:])
		return from, target, msg, true
	}
	return "", "", "", false
}