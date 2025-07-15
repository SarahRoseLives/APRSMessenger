// services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SocketStatus { disconnected, connecting, connected, error }

class WebSocketService with ChangeNotifier {
  WebSocketChannel? _channel;
  Stream<dynamic>? _broadcastStream;
  // This top-level subscription is no longer needed
  // StreamSubscription? _streamSubscription;

  SocketStatus _status = SocketStatus.disconnected;
  SocketStatus get status => _status;

  String? _connectionError;
  String? get connectionError => _connectionError;

  String? _callsign;
  String? get callsign => _callsign;

  Stream<dynamic> get messages => _broadcastStream ?? const Stream.empty();

  Future<bool> connect(
    String callsign,
    String password, {
    String? passcode, // For registration
  }) async {
    _updateStatus(SocketStatus.connecting);
    _callsign = callsign.toUpperCase();

    try {
      final uri = Uri.parse('ws://192.168.1.240:8080/ws');
      _channel = WebSocketChannel.connect(uri);
      _broadcastStream = _channel!.stream.asBroadcastStream();

      final responseCompleter = Completer<bool>();

      // FIX: Use a temporary, self-cancelling subscription for authentication
      StreamSubscription? authSubscription;
      authSubscription = _broadcastStream!.listen(
        (raw) {
          // This listener only cares about the first 'success' message
          try {
            final msg = jsonDecode(raw);
            if (msg is Map && msg.containsKey('success')) {
              if (msg['success'] == true) {
                _updateStatus(SocketStatus.connected);
                if (!responseCompleter.isCompleted) responseCompleter.complete(true);
              } else {
                _handleError(msg['error'] ?? "Authentication failed.");
                if (!responseCompleter.isCompleted) responseCompleter.complete(false);
              }
              // Once we get the auth response, we cancel this temporary listener
              // so it doesn't swallow any other messages (like history).
              authSubscription?.cancel();
            }
          } catch (e) {
             // It's possible for a non-auth message to arrive first. Ignore parse errors here.
          }
        },
        onError: (err) {
          _handleError("Connection error: $err");
          if (!responseCompleter.isCompleted) responseCompleter.complete(false);
          authSubscription?.cancel();
        },
        onDone: () {
          _updateStatus(SocketStatus.disconnected);
          if (!responseCompleter.isCompleted) {
            _handleError("Connection closed before authentication.");
            responseCompleter.complete(false);
          }
        },
      );

      // Send the appropriate action (register or login)
      if (passcode != null) {
        // This is a registration attempt
        _sendJson({
          "action": "create_account",
          "callsign": _callsign,
          "passcode": passcode,
          "password": password,
        });
      } else {
        // This is a login attempt
        _sendJson({
          "action": "login",
          "callsign": _callsign,
          "password": password,
        });
      }

      return await responseCompleter.future;
    } catch (e) {
      _handleError("Failed to connect: $e");
      return false;
    }
  }

  void sendMessage({required String toCallsign, required String message}) {
    if (_status != SocketStatus.connected) return;
    _sendJson({
      "action": "send_message",
      "to_callsign": toCallsign,
      "message": message,
    });
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
    notifyListeners(); // Notify UI of error before disconnecting
    disconnect();
  }

  void disconnect() {
    _channel?.sink.close();
    _status = SocketStatus.disconnected;
    _callsign = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}