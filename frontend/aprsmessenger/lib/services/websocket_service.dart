import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SocketStatus { disconnected, connecting, connected, error }

class WebSocketService with ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;

  /// This is the stream the UI will listen to. It only contains APRS messages.
  final StreamController<dynamic> _messageStreamController =
      StreamController<dynamic>.broadcast();

  /// The public stream of messages for the UI.
  Stream<dynamic> get messages => _messageStreamController.stream;

  /// Public cache to hold all received messages, preventing loss before UI listens.
  final List<dynamic> messageCache = [];

  SocketStatus _status = SocketStatus.disconnected;
  SocketStatus get status => _status;

  String? _connectionError;
  String? get connectionError => _connectionError;

  String? _callsign;
  String? get callsign => _callsign;

  String? sessionToken; // For web to show QR code

  /// Connects using secure WebSocket (wss) ONLY.
  Future<bool> connect(
    String callsign,
    String password, {
    String? passcode, // For registration
  }) async {
    if (_status == SocketStatus.connected || _status == SocketStatus.connecting) {
      return _status == SocketStatus.connected;
    }
    _updateStatus(SocketStatus.connecting);
    _callsign = callsign.toUpperCase();

    final loginCompleter = Completer<Map<String, dynamic>>();

    try {
      final uri = Uri.parse('ws://localhost:8585/ws');
//      final uri = Uri.parse('wss://aprs.chat/ws');
      _channel = WebSocketChannel.connect(uri);

      _socketSubscription = _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            if (!loginCompleter.isCompleted &&
                msg is Map &&
                msg.containsKey('success')) {
              loginCompleter.complete(Map<String, dynamic>.from(msg));
            } else {
              messageCache.add(data);
              _messageStreamController.add(data);
            }
          } catch (e) {
            debugPrint("WebSocket message parse error: $e");
            if (!loginCompleter.isCompleted) {
              loginCompleter.completeError("Invalid message format from server.");
            }
          }
        },
        onError: (error) {
          if (!loginCompleter.isCompleted) {
            loginCompleter.completeError(error);
          }
          _handleError("WebSocket connection error: $error");
        },
        onDone: () {
          _updateStatus(SocketStatus.disconnected);
        },
        cancelOnError: true,
      );

      final payload = {
        "action": passcode != null ? "create_account" : "login",
        "callsign": _callsign,
        "password": password,
        if (passcode != null) "passcode": passcode,
      };
      _sendJson(payload);

      final loginMsg = await loginCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw 'Login attempt timed out.';
        },
      );

      if (loginMsg['success'] == true) {
        _updateStatus(SocketStatus.connected);
        sessionToken = loginMsg['session_token'];
        return true;
      } else {
        _handleError(loginMsg['error'] ?? "Authentication failed.");
        return false;
      }
    } catch (e) {
      debugPrint("WebSocket connect error: $e");
      _handleError("Failed to connect using wss.");
      return false;
    }
  }

  /// Connects using a session token from the web QR code (secure socket ONLY).
  Future<bool> connectWithToken(String token) async {
    if (_status == SocketStatus.connected || _status == SocketStatus.connecting) {
      return _status == SocketStatus.connected;
    }
    _updateStatus(SocketStatus.connecting);

    final loginCompleter = Completer<Map<String, dynamic>>();

    try {
      final uri = Uri.parse('wss://aprs.chat/ws');
      _channel = WebSocketChannel.connect(uri);

      _socketSubscription = _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            if (!loginCompleter.isCompleted &&
                msg is Map &&
                msg.containsKey('success')) {
              loginCompleter.complete(Map<String, dynamic>.from(msg));
            } else {
              messageCache.add(data);
              _messageStreamController.add(data);
            }
          } catch (e) {
            if (!loginCompleter.isCompleted) {
              loginCompleter.completeError("Invalid message format from server.");
            }
          }
        },
        onError: (error) {
          if (!loginCompleter.isCompleted) {
            loginCompleter.completeError(error);
          }
          _handleError("WebSocket connection error: $error");
        },
        onDone: () => _updateStatus(SocketStatus.disconnected),
        cancelOnError: true,
      );

      final payload = {
        "action": "login_with_token",
        "token": token,
      };
      _sendJson(payload);

      final loginMsg = await loginCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw 'Login attempt timed out.',
      );

      if (loginMsg['success'] == true) {
        _callsign = (loginMsg['callsign'] as String?).toString().toUpperCase();
        _updateStatus(SocketStatus.connected);
        return true;
      } else {
        _handleError(loginMsg['error'] ?? "Token login failed.");
        return false;
      }
    } catch (e) {
      debugPrint("WebSocket connect error: $e");
      _handleError("Failed to connect using wss.");
      return false;
    }
  }

  /// Sends a message to a specific callsign.
  void sendMessage({
    required String toCallsign,
    required String message,
    String? fromCallsign,
  }) {
    if (_status != SocketStatus.connected) return;
    final payload = {
      "action": "send_message",
      "to_callsign": toCallsign,
      "message": message,
      if (fromCallsign != null) "from_callsign": fromCallsign,
    };
    _sendJson(payload);
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_channel?.sink != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void _updateStatus(SocketStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    _connectionError = null;
    notifyListeners();
  }

  void _handleError(String error) {
    _status = SocketStatus.error;
    _connectionError = error;
    notifyListeners();
    disconnect(); // Disconnect and clean up on error.
  }

  /// Closes the connection and cleans up resources.
  void disconnect() {
    _socketSubscription?.cancel();
    _channel?.sink.close();
    _status = SocketStatus.disconnected;
    _callsign = null;
    sessionToken = null; // Clear token on disconnect
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _messageStreamController.close();
    super.dispose();
  }
}