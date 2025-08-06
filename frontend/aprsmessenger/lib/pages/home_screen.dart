import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/websocket_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/contact_tile.dart';
import '../widgets/message_route_map.dart';
import 'admin_panel_screen.dart';
// Import your landing page. Replace with actual import if needed.
import 'landing_page.dart'; // <-- Make sure this is the correct path

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late WebSocketService _socketService;
  StreamSubscription? _streamSubscription;

  List<RecentContact> recents = [];
  int? selectedIndex;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  bool _gotLoginResponse = false;
  String? _loginError;

  bool get isAdmin {
    final callsign = _socketService.callsign?.split('-').first ?? '';
    return ['k8sdr', 'ad8nt'].contains(callsign.toLowerCase());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_streamSubscription == null) {
      _socketService = Provider.of<WebSocketService>(context);

      // Process all messages from the cache that arrived before this screen was ready.
      for (final raw in _socketService.messageCache) {
        _onNewMessage(raw);
      }

      _streamSubscription = _socketService.messages.listen(_onNewMessage);
      _socketService.addListener(_handleConnectionChange);
    }
  }

  void _handleConnectionChange() {
    if (_socketService.status == SocketStatus.error ||
        _socketService.status == SocketStatus.disconnected) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  void _showQrCode() {
    final token = _socketService.sessionToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session token not available.")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Login on Mobile App"),
        content: SizedBox(
          width: 250,
          height: 250,
          child: Center(
            child: QrImageView(
              data: token,
              version: QrVersions.auto,
              size: 220.0,
              gapless: false,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Theme.of(context).colorScheme.primary,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  /// LOGOUT BUTTON HANDLER
  void _logout() {
    _socketService.disconnect();
    // Replace with your actual landing page route.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LandingPage()), // Replace LandingPage with your landing page widget
      (route) => false,
    );
  }

  void _onNewMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw);

      // First response from server is login response, handle error if any
      if (!_gotLoginResponse) {
        _gotLoginResponse = true;
        if (msg is Map &&
            msg.containsKey('success') &&
            msg['success'] != true) {
          setState(() {
            _loginError = msg['error'] ?? "Login failed";
          });
        }
        return;
      }

      if (msg["aprs_msg"] == true) {
        final from = (msg["from"] as String).toUpperCase();
        final to = (msg["to"] as String).toUpperCase();
        final isHistory = msg["history"] == true;
        final text = msg["message"] ?? "";
        final createdAt = msg["created_at"];
        final routeHops = msg['route'] != null && msg['route'] is List
            ? (msg['route'] as List)
                .map((hop) => RouteHop.fromJson(hop))
                .toList()
            : null;

        final userBaseCallsign =
            (_socketService.callsign ?? '').toUpperCase().split('-').first;
        if (userBaseCallsign.isEmpty) return;
        final fromBaseCallsign = from.split('-').first;
        final fromMe = fromBaseCallsign == userBaseCallsign;

        final contactCallsign = fromMe ? to : from;
        final ownCallsignForChat = fromMe ? from : to;
        final groupingKey = contactCallsign.split('-').first;

        // Extract messageId for ChatMessage
        final messageId = msg['messageId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

        int idx = recents.indexWhere((c) => c.groupingId == groupingKey);
        if (idx == -1) {
          recents.add(RecentContact(
            groupingId: groupingKey,
            callsign: contactCallsign,
            ownCallsign: ownCallsignForChat,
            lastMessage: text,
            time: _formatTime(createdAt),
            messages: [
              ChatMessage(
                  messageId: messageId,
                  fromMe: fromMe,
                  text: text,
                  time: _displayTime(createdAt)),
            ],
            unread: !fromMe && !isHistory,
            route: routeHops,
          ));
          idx = recents.length - 1;
        } else {
          recents[idx].messages.add(ChatMessage(
                messageId: messageId,
                fromMe: fromMe,
                text: text,
                time: _displayTime(createdAt),
              ));
          recents[idx] = recents[idx].copyWith(
            callsign: contactCallsign,
            ownCallsign: ownCallsignForChat,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: (!fromMe && !isHistory) || recents[idx].unread,
            route: routeHops ?? recents[idx].route,
          );
        }
        // If the message is for the currently selected chat and not from history, we should scroll.
        final bool shouldScroll = selectedIndex == idx && !isHistory;

        // If not viewing this contact, set unread
        if (selectedIndex != idx && !fromMe && !isHistory) {
          recents[idx] = recents[idx].copyWith(unread: true);
        }

        // Sort by time
        recents.sort((a, b) => b.time.compareTo(a.time));

        setState(() {});

        if (shouldScroll) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _socketService.removeListener(_handleConnectionChange);
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || selectedIndex == null) return;
    final contact = recents[selectedIndex!];

    final tempMessageId = DateTime.now().millisecondsSinceEpoch.toString();

    _socketService.sendMessage(
        toCallsign: contact.callsign,
        message: text,
        fromCallsign: contact.ownCallsign);
    setState(() {
      recents[selectedIndex!].messages.add(
            ChatMessage(
              messageId: tempMessageId,
              fromMe: true,
              text: text,
              time: _currentTime(),
            ),
          );
      recents[selectedIndex!] = recents[selectedIndex!].copyWith(
        lastMessage: text,
        time: DateTime.now().toIso8601String(),
        unread: false,
      );
      recents.sort((a, b) => b.time.compareTo(a.time));
      _chatController.clear();
    });
    _scrollToBottom();
  }

  void _showNewMessageDialog() {
    final callsignController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("New Message"),
          content: TextField(
            controller: callsignController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: "Recipient Callsign",
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (value) {
              Navigator.of(context).pop();
              _startChatWithCallsign(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startChatWithCallsign(callsignController.text);
              },
              child: const Text("Message"),
            ),
          ],
        );
      },
    );
  }

  void _startChatWithCallsign(String callsignRaw) {
    final String callsign = callsignRaw.trim().toUpperCase();
    if (callsign.isEmpty) return;

    final String groupingKey = callsign.split('-').first;
    final int existingIndex =
        recents.indexWhere((c) => c.groupingId == groupingKey);

    if (existingIndex != -1) {
      setState(() {
        selectedIndex = existingIndex;
        if (recents[existingIndex].unread) {
          recents[existingIndex] =
              recents[existingIndex].copyWith(unread: false);
        }
      });
    } else {
      final newContact = RecentContact(
        groupingId: groupingKey,
        callsign: callsign,
        ownCallsign: _socketService.callsign!,
        lastMessage: "No messages yet.",
        time: DateTime.now().toIso8601String(),
        unread: false,
        messages: [],
        route: null,
      );

      setState(() {
        recents.add(newContact);
        recents.sort((a, b) => b.time.compareTo(a.time));
        selectedIndex = recents.indexWhere((c) => c.groupingId == groupingKey);
      });
    }
    _scrollToBottom();
  }

  String _currentTime() {
    final now = TimeOfDay.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return DateTime.now().toIso8601String();
    return isoTime;
  }

  String _displayTime(String? isoTime) {
    if (isoTime == null) return _currentTime();
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      if (dt.day == now.day &&
          dt.month == now.month &&
          dt.year == now.year) {
        return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      }
      return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return _currentTime();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If login error, show error message and a back button
    if (_loginError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("APRS.Chat"),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loginError!,
                style: const TextStyle(
                    color: Colors.red,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("Back"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          elevation: 1,
          titleSpacing: 24,
          title: Row(
            children: [
              Icon(Icons.message_rounded,
                  size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                "APRS.Chat",
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 21,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.white,
          actions: [
            if (isAdmin)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined,
                      size: 20),
                  label: const Text("Admin Panel"),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AdminPanelScreen(
                            callsign: _socketService.callsign!),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                tooltip: "Login on Mobile",
                icon: Icon(Icons.qr_code,
                    color: Colors.teal.shade700, size: 28),
                onPressed: _showQrCode,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: IconButton(
                tooltip: "Logout",
                icon: Icon(Icons.logout, color: Colors.grey.shade700, size: 28),
                onPressed: _logout,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
            child: Row(
              children: [
                // Recents Panel
                Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 18, horizontal: 22),
                        child: Row(
                          children: [
                            Icon(Icons.history,
                                color: theme.colorScheme.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              "Recents",
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.add_comment_outlined,
                                  color: theme.colorScheme.primary),
                              tooltip: "New Message",
                              onPressed: _showNewMessageDialog,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          itemCount: recents.length,
                          itemBuilder: (context, i) {
                            final c = recents[i];
                            final selected = selectedIndex == i;
                            return ContactTile(
                              contact: c,
                              displayTime: _displayTime(c.time),
                              selected: selected,
                              onTap: () {
                                setState(() {
                                  selectedIndex = i;
                                  recents[i] = c.copyWith(unread: false);
                                });
                                _scrollToBottom();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                // Chat and Map Panel
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(2, 2),
                        ),
                      ],
                    ),
                    child: selectedIndex == null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(48.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.message_rounded,
                                      color: theme.colorScheme.primary
                                          .withOpacity(0.4),
                                      size: 56),
                                  const SizedBox(height: 24),
                                  Text(
                                    "Welcome, ${_socketService.callsign ?? ''}!",
                                    style: TextStyle(
                                      fontSize: 23,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    "Select a recent contact on the left to view your message history, or click the '+' icon to start a new chat.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Chat Header Bar
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 20),
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(18)),
                                  color: theme.colorScheme.primary
                                      .withOpacity(0.05),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: theme
                                          .colorScheme.primary
                                          .withOpacity(0.13),
                                      foregroundColor:
                                          theme.colorScheme.primary,
                                      child: Text(
                                        recents[selectedIndex!]
                                            .callsign
                                            .substring(0, 1),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      recents[selectedIndex!].callsign,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "History",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.6),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              // Chat Messages
                              Expanded(
                                child: ListView.builder(
                                  controller:
                                      _chatScrollController,
                                  reverse: true,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16, horizontal: 16),
                                  itemCount:
                                      recents[selectedIndex!].messages.length,
                                  itemBuilder: (context, i) {
                                    final index = recents[selectedIndex!]
                                            .messages
                                            .length -
                                        1 -
                                        i;
                                    final msg =
                                        recents[selectedIndex!].messages[index];
                                    return ChatBubble(message: msg);
                                  },
                                ),
                              ),
                              // Message Entry Box
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 0, 18, 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _chatController,
                                        decoration: InputDecoration(
                                          hintText: "Type a message...",
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(48),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey.shade100,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: 10),
                                        ),
                                        onSubmitted: (_) => _sendMessage(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    CircleAvatar(
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      child: IconButton(
                                        icon: const Icon(Icons.send,
                                            color: Colors.white),
                                        onPressed: _sendMessage,
                                        tooltip: 'Send',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Map Widget BELOW the chat/input
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                                child: SizedBox(
                                  height:
                                      200,
                                  child: MessageRouteMap(
                                    route:
                                        recents[selectedIndex!].route ?? [],
                                    contact: recents[selectedIndex!].callsign,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}