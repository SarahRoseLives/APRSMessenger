import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/websocket_service.dart';
import '../widgets/contact_tile.dart';
import '../widgets/message_route_map.dart'; // Import for RouteHop
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

      // --- MODIFICATION START ---
      // Process all messages from the cache that arrived before this screen was ready.
      for (final raw in _socketService.messageCache) {
        _onNewMessage(raw);
      }
      // --- MODIFICATION END ---

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

        final routeHops = msg['route'] != null && msg['route'] is List
            ? (msg['route'] as List)
                .map((hop) => RouteHop.fromJson(hop))
                .toList()
            : null;

        final userBaseCallsign = _socketService.callsign!.split('-').first;
        final fromBaseCallsign = from.split('-').first;
        final fromMe = fromBaseCallsign == userBaseCallsign;

        final otherPartyCallsign = fromMe ? to : from;
        final ownCallsignForChat = fromMe ? from : to;
        final groupingKey = otherPartyCallsign.split('-').first;

        // --- FIX: Ensure messageId is always present ---
        final messageId = msg['messageId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

        final newMessage = ChatMessage(
          messageId: messageId,
          fromMe: fromMe,
          text: text,
          time: _formatTime(createdAt),
        );

        final idx = recents.indexWhere((c) => c.groupingId == groupingKey);

        if (idx == -1) {
          // Contact group does not exist, create a new one.
          recents.add(RecentContact(
            groupingId: groupingKey,
            callsign: otherPartyCallsign,
            ownCallsign: ownCallsignForChat,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: !fromMe && !isHistory,
            messages: [newMessage],
            route: routeHops,
          ));
        } else {
          // Contact group exists, update it immutably.
          final contact = recents[idx];

          // --- MODIFICATION START ---
          // **DE-DUPLICATION**: Check if we already have this message.
          if (contact.messages.any((m) =>
              m.messageId == newMessage.messageId)) {
            return; // Skip duplicate message based on messageId
          }
          // --- MODIFICATION END ---

          final updatedMessages = List<ChatMessage>.from(contact.messages)
            ..add(newMessage);

          // Sort messages by time to ensure they are in order
          updatedMessages
              .sort((a, b) => (a.time ?? "").compareTo(b.time ?? ""));

          recents[idx] = contact.copyWith(
            callsign: otherPartyCallsign, // Update to the latest full callsign
            ownCallsign:
                ownCallsignForChat, // Update our own callsign used in chat
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: (!fromMe && !isHistory) || contact.unread,
            messages: updatedMessages,
            route: routeHops ?? contact.route,
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

  void _showNewMessageDialog() {
    final callsignController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("New Message"),
          content: TextField(
            controller: callsignController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: "Enter callsign",
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final String callsign =
                    callsignController.text.trim().toUpperCase();
                if (callsign.isEmpty) return;

                Navigator.of(context).pop(); // Dismiss dialog
                _navigateToChat(callsign);
              },
              child: const Text("Message"),
            ),
          ],
        );
      },
    );
  }

  void _navigateToChat(String callsign) {
    final String groupingKey = callsign.split('-').first;
    final int existingIndex =
        recents.indexWhere((c) => c.groupingId == groupingKey);

    RecentContact contact;

    if (existingIndex != -1) {
      // Chat already exists, use that one.
      contact = recents[existingIndex];
      // Mark as read when navigating.
      if (contact.unread) {
        setState(() => recents[existingIndex] = contact.copyWith(unread: false));
      }
    } else {
      // Create a new, temporary contact object to start the conversation.
      // This object won't be added to the main 'recents' list. The ChatScreen
      // will use it, and when the first message is sent, the websocket echo
      // will cause the real contact to be created and added to the list.
      contact = RecentContact(
        groupingId: groupingKey,
        callsign: callsign,
        ownCallsign: _socketService.callsign!,
        lastMessage: "",
        time: DateTime.now().toIso8601String(),
        unread: false,
        messages: [],
        route: null,
      );
    }

    // Navigate to ChatScreen with the determined contact info
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: _socketService,
          child: ChatScreen(
            contact: contact,
          ),
        ),
      ),
    );
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
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
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
        title: const Text("APRS.Chat"),
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
              // Use the _navigateToChat method to handle navigation and state updates
              _navigateToChat(contact.callsign);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewMessageDialog,
        tooltip: 'New Message',
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }
}