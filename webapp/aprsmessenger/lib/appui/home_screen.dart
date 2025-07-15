// appui/home_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/websocket_service.dart';
import '../widgets/contact_tile.dart';
import 'admin_panel_screen.dart';
import 'chat_screen.dart';
import 'landing_page.dart'; // Import the landing page

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late WebSocketService _socketService;
  StreamSubscription? _streamSubscription;
  List<RecentContact> recents = [];

  bool get isAdmin {
    final callsign = _socketService.callsign ?? '';
    return ['k8sdr', 'ad8nt'].contains(callsign.toLowerCase());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensures we only subscribe once
    if (_streamSubscription == null) {
      _socketService = Provider.of<WebSocketService>(context);
      _streamSubscription = _socketService.messages.listen(_onNewMessage);

      // Listen for connection errors that might happen after login
      _socketService.addListener(_handleConnectionChange);
    }
  }

  void _handleConnectionChange() {
    if (_socketService.status == SocketStatus.error || _socketService.status == SocketStatus.disconnected) {
      // Navigate back to login if connection is lost
      if (mounted) {
        // FIX: Navigate back to the LandingPage correctly
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LandingPage()),
          (route) => false,
        );
      }
    }
  }

  // _onNewMessage and _formatTime methods remain the same as the previous fix...
  void _onNewMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw);
      if (msg["aprs_msg"] == true) {
        final from = (msg["from"] as String).toUpperCase();
        final to = (msg["to"] as String).toUpperCase();
        final text = msg["message"] ?? "";
        final createdAt = msg["created_at"];
        final isHistory = msg["history"] == true;
        final fromMe = from == _socketService.callsign;
        final contactCallsign = fromMe ? to : from;

        int idx = recents.indexWhere((c) => c.callsign == contactCallsign);

        if (idx == -1) {
          recents.add(RecentContact(
            callsign: contactCallsign,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: !fromMe && !isHistory,
            messages: [ChatMessage(fromMe: fromMe, text: text, time: _formatTime(createdAt))],
          ));
        } else {
          final contact = recents[idx];
          // Prevent adding duplicate history messages
          if (contact.messages.any((m) => m.text == text && m.time == _formatTime(createdAt))) {
             return;
          }
          contact.messages.add(ChatMessage(fromMe: fromMe, text: text, time: _formatTime(createdAt)));
          recents[idx] = contact.copyWith(
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: (!fromMe && !isHistory) || contact.unread,
          );
        }
        setState(() {});
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return "";
    final dt = DateTime.tryParse(isoTime);
    if (dt == null) return "";
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }
    return "${dt.month}/${dt.day}";
  }


  @override
  void dispose() {
    _streamSubscription?.cancel();
    _socketService.removeListener(_handleConnectionChange);
    // The service itself will be disposed when the provider is removed from the tree
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<WebSocketService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("APRS Messenger"),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: "Admin Panel",
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AdminPanelScreen(callsign: socketService.callsign!)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "Logout",
              onPressed: () {
                socketService.disconnect();
                // FIX: The listener will now handle navigation correctly,
                // but we can be explicit here for immediate feedback.
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LandingPage()),
                    (route) => false
                );
              },
            ),
          ),
        ],
      ),
      // The body of the scaffold remains the same as the previous fix...
      body: ListView.builder(
        itemCount: recents.length,
        itemBuilder: (context, i) {
          final contact = recents[i];
          return ContactTile(
            contact: contact,
            selected: false,
            onTap: () async {
              setState(() => recents[i] = contact.copyWith(unread: false));
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: socketService,
                    child: ChatScreen(
                      contact: contact,
                    ),
                  ),
                ),
              );
              setState(() {}); // Refresh state when returning
            },
          );
        },
      ),
    );
  }
}