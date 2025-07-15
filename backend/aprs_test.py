import socket

HOST = "rotate.aprs.net"
PORT = 10152
CALLSIGN = "K8SDR-10"
PASSCODE = "14750"

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((HOST, PORT))
    login_line = f"user {CALLSIGN} pass {PASSCODE} vers python-aprs-test 1.0\r\n"
    s.sendall(login_line.encode("utf-8"))

    print(f"Connected to {HOST}:{PORT} as {CALLSIGN}, printing full feed:")
    try:
        # Add errors="replace" to handle invalid bytes gracefully
        with s.makefile("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                print(line.rstrip())
    except KeyboardInterrupt:
        print("\nDisconnected.")
    finally:
        s.close()

if __name__ == "__main__":
    main()