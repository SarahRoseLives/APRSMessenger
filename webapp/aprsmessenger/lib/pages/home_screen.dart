import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/websocket_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/contact_tile.dart';
import 'admin_panel_screen.dart';

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

  bool _gotLoginResponse = false;
  String? _loginError;

  bool get isAdmin {
    final callsign = _socketService.callsign ?? '';
    return ['k8sdr', 'ad8nt'].contains(callsign.toLowerCase());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_streamSubscription == null) {
      _socketService = Provider.of<WebSocketService>(context);
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
        final fromMe = from == (_socketService.callsign ?? '').toUpperCase();
        final contactCallsign = fromMe ? to : from;

        int idx = recents.indexWhere((c) => c.callsign == contactCallsign);
        if (idx == -1) {
          recents.add(RecentContact(
            callsign: contactCallsign,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: !fromMe && !isHistory,
            messages: [
              ChatMessage(
                  fromMe: fromMe, text: text, time: _formatTime(createdAt)),
            ],
          ));
          idx = recents.length - 1;
        } else {
          recents[idx].messages.add(ChatMessage(
            fromMe: fromMe,
            text: text,
            time: _formatTime(createdAt),
          ));
          recents[idx] = recents[idx].copyWith(
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: (!fromMe && !isHistory) || recents[idx].unread,
          );
        }
        // If not viewing this contact, set unread
        if (selectedIndex != idx && !fromMe && !isHistory) {
          recents[idx] = recents[idx].copyWith(unread: true);
        }
        setState(() {});
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
    super.dispose();
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || selectedIndex == null) return;
    final contact = recents[selectedIndex!];
    // The backend expects "to_callsign" as the key.
    _socketService.sendMessage(toCallsign: contact.callsign, message: text);
    setState(() {
      recents[selectedIndex!].messages.add(
        ChatMessage(
          fromMe: true,
          text: text,
          time: _currentTime(),
        ),
      );
      recents[selectedIndex!] = recents[selectedIndex!].copyWith(
        lastMessage: text,
        time: "Now",
        unread: false,
      );
      _chatController.clear();
    });
  }

  String _currentTime() {
    final now = TimeOfDay.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return _currentTime();
    try {
      final dt = DateTime.tryParse(isoTime);
      if (dt == null) return _currentTime();
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
          title: const Text("APRS Messenger"),
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
                "APRS Messenger",
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
              padding: const EdgeInsets.only(right: 24),
              child: Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_none_outlined,
                        color: Colors.teal.shade700),
                    onPressed: () {},
                  ),
                  if (recents.any((c) => c.unread))
                    Positioned(
                      right: 6,
                      top: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Center(
                          child: Text(
                            '${recents.where((c) => c.unread).length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
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
                              selected: selected,
                              onTap: () {
                                setState(() {
                                  selectedIndex = i;
                                  recents[i] = c.copyWith(unread: false);
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                // Chat Panel
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
                                    "Select a recent contact on the left to view your message history and start chatting.",
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
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16, horizontal: 16),
                                  itemCount:
                                      recents[selectedIndex!].messages.length,
                                  itemBuilder: (context, i) {
                                    final msg = recents[selectedIndex!]
                                        .messages[i];
                                    return ChatBubble(message: msg);
                                  },
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 0, 18, 18),
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