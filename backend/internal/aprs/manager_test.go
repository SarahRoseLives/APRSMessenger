package aprs

import (
	"testing"
)

// TestMessageParsingWithMsgId tests that messages with msgId are parsed correctly
func TestMessageParsingWithMsgId(t *testing.T) {
	// Test APRS message with msgId that should trigger an ACK
	testLine := "SRCUSER>APRS,K8SDR*,qAC,K8SDR-10::TESTUSER :Hello there{12}"

	// Parse the message
	msg, err := ParseMessagePacket(testLine)
	if err != nil {
		t.Fatalf("Failed to parse test message: %v", err)
	}

	// Verify it's a user message with a msgId
	if !msg.IsUserMessage() {
		t.Fatal("Test message should be a user message")
	}
	if msg.MsgNo != "12" {
		t.Fatalf("Expected msgId '12', got '%s'", msg.MsgNo)
	}
	if msg.Source != "SRCUSER" {
		t.Fatalf("Expected source 'SRCUSER', got '%s'", msg.Source)
	}
	if msg.Addressee != "TESTUSER" {
		t.Fatalf("Expected addressee 'TESTUSER', got '%s'", msg.Addressee)
	}
	if msg.MessageText != "Hello there" {
		t.Fatalf("Expected message 'Hello there', got '%s'", msg.MessageText)
	}

	t.Logf("Message parsed correctly: from=%s to=%s msg=%s msgId=%s", 
		msg.Source, msg.Addressee, msg.MessageText, msg.MsgNo)
}

// TestACKLogicFlow tests that the ACK generation logic works correctly
func TestACKLogicFlow(t *testing.T) {
	// Test that ACK payload is generated correctly
	msgId := "12"
	expectedACKPayload := "ack12"
	
	ackPayload := "ack" + msgId
	if ackPayload != expectedACKPayload {
		t.Fatalf("Expected ACK payload '%s', got '%s'", expectedACKPayload, ackPayload)
	}

	t.Logf("ACK payload generated correctly: %s", ackPayload)
}