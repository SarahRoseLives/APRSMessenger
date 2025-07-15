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
    final callsign = _socketService.callsign?.split('-').first ?? '';
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
    if (_socketService.status == SocketStatus.error ||
        _socketService.status == SocketStatus.disconnected) {
      // Navigate back to login if connection is lost
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LandingPage()),
          (route) => false,
        );
      }
    }
  }

  void _onNewMessage(dynamic raw) {
    debugPrint("RAW MESSAGE (appui): $raw");

    try {
      final msg = jsonDecode(raw);
      if (msg["aprs_msg"] == true) {
        final from = (msg["from"] as String).toUpperCase();
        final to = (msg["to"] as String).toUpperCase();
        final text = msg["message"] ?? "";
        final createdAt = msg["created_at"];
        final isHistory = msg["history"] == true;

        final userBaseCallsign = _socketService.callsign!.split('-').first;
        final fromBaseCallsign = from.split('-').first;
        final fromMe = fromBaseCallsign == userBaseCallsign;

        final contactCallsign = fromMe ? to : from;
        final ownCallsignForChat = fromMe ? from : to;

        final newMessage = ChatMessage(
          fromMe: fromMe,
          text: text,
          time: _formatTime(createdAt),
        );

        final idx = recents.indexWhere((c) => c.callsign == contactCallsign);

        if (idx == -1) {
          // Contact does not exist, create a new one.
          recents.add(RecentContact(
            callsign: contactCallsign,
            ownCallsign: ownCallsignForChat,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: !fromMe && !isHistory,
            messages: [newMessage],
          ));
        } else {
          // Contact exists, update it immutably.
          final contact = recents[idx];

          final updatedMessages = List<ChatMessage>.from(contact.messages)
            ..add(newMessage);

          // Sort messages by time to ensure they are in order
          updatedMessages.sort((a, b) => (a.time ?? "").compareTo(b.time ?? ""));

          recents[idx] = contact.copyWith(
            ownCallsign: ownCallsignForChat,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: (!fromMe && !isHistory) || contact.unread,
            messages: updatedMessages, // Pass the new immutable list.
          );
        }
        // Sort the recents list to bring the most recent conversations to the top
        recents.sort((a, b) => (b.time).compareTo(a.time));
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint("Error processing message in appui/home_screen: $e");
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return "";
    final dt = DateTime.tryParse(isoTime);
    if (dt == null) return "";
    // Return the full ISO string for accurate sorting. Display formatting is handled in the widget.
    return isoTime;
  }

  String _displayTime(String? isoTime) {
      if (isoTime == null) return "";
      final dt = DateTime.tryParse(isoTime);
      if (dt == null) return "";
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
          return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      }
      return "${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}";
  }


  @override
  void dispose() {
    _streamSubscription?.cancel();
    _socketService.removeListener(_handleConnectionChange);
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
                MaterialPageRoute(
                    builder: (_) => AdminPanelScreen(
                        callsign: socketService.callsign!)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "Logout",
              onPressed: () {
                socketService.disconnect();
                // The listener will handle navigation, but this is immediate.
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => const LandingPage()),
                    (route) => false);
              },
            ),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: recents.length,
        itemBuilder: (context, i) {
          final contact = recents[i];
          return ContactTile(
            contact: contact,
            displayTime: _displayTime(contact.time),
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