package aprs

import (
	"testing"
)

func TestSSIDHandling(t *testing.T) {
	// Test that callback lookup works with SSIDs
	manager := NewAPRSManager()
	
	// Register callback for K8SDR-10 (with SSID)
	callbackCalled := false
	manager.RegisterUser("K8SDR-10", func(from, to, msg string) {
		callbackCalled = true
		if to != "K8SDR-10" {
			t.Errorf("Expected 'to' to be 'K8SDR-10', got '%s'", to)
		}
	})
	
	// Simulate a message packet to K8SDR-10
	testLine := "W1ABC>APRS,TCPIP*::K8SDR-10 :Hello from W1ABC"
	msg, err := ParseMessagePacket(testLine)
	if err != nil {
		t.Fatalf("Failed to parse message: %v", err)
	}
	
	if !msg.IsUserMessage() {
		t.Fatal("Message should be recognized as user message")
	}
	
	// Simulate the dispatch logic
	fullDest := toUpperNoSpace(msg.Addressee)
	baseDest := baseCallsign(fullDest)
	
	// First try exact SSID match
	cb, ok := manager.callbacks[fullDest]
	if !ok {
		// Fallback to base callsign
		cb, ok = manager.callbacks[baseDest]
	}
	
	if !ok {
		t.Fatal("No callback found for K8SDR-10")
	}
	
	// Call the callback
	cb(msg.Source, msg.Addressee, msg.MessageText)
	
	if !callbackCalled {
		t.Error("Callback was not called")
	}
}

func TestBaseCallsignFunction(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"K8SDR", "K8SDR"},
		{"K8SDR-10", "K8SDR"},
		{"W1ABC-5", "W1ABC"},
		{"AA0XYZ", "AA0XYZ"},
	}
	
	for _, test := range tests {
		result := baseCallsign(test.input)
		if result != test.expected {
			t.Errorf("baseCallsign(%s) = %s, expected %s", test.input, result, test.expected)
		}
	}
}

func TestSSIDFallback(t *testing.T) {
	// Test that messages to SSIDs can fall back to base callsign callbacks
	manager := NewAPRSManager()
	
	// Register callback only for base callsign K8SDR
	callbackCalled := false
	manager.RegisterUser("K8SDR", func(from, to, msg string) {
		callbackCalled = true
	})
	
	// Simulate a message packet to K8SDR-15 (SSID not specifically registered)
	testLine := "W1ABC>APRS,TCPIP*::K8SDR-15 :Hello from W1ABC"
	msg, err := ParseMessagePacket(testLine)
	if err != nil {
		t.Fatalf("Failed to parse message: %v", err)
	}
	
	// Simulate the dispatch logic with fallback
	fullDest := toUpperNoSpace(msg.Addressee)
	baseDest := baseCallsign(fullDest)
	
	// First try exact SSID match
	cb, ok := manager.callbacks[fullDest]
	if !ok {
		// Fallback to base callsign
		cb, ok = manager.callbacks[baseDest]
	}
	
	if !ok {
		t.Fatal("No callback found for K8SDR-15 (should fallback to K8SDR)")
	}
	
	// Call the callback
	cb(msg.Source, msg.Addressee, msg.MessageText)
	
	if !callbackCalled {
		t.Error("Callback was not called")
	}
}