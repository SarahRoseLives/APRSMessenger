import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/contact_tile.dart';

class HomeScreen extends StatefulWidget {
  final String callsign;

  const HomeScreen({super.key, required this.callsign});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late List<RecentContact> recents;
  int? selectedIndex;
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    recents = [
      RecentContact(
        callsign: 'KC4XYZ',
        lastMessage: 'See you at the next net!',
        time: '10:02 AM',
        unread: true,
        messages: [
          ChatMessage(fromMe: false, text: "Hello!", time: "9:55 AM"),
          ChatMessage(fromMe: true, text: "Hi KC4XYZ!", time: "9:56 AM"),
          ChatMessage(fromMe: false, text: "See you at the next net!", time: "10:02 AM"),
        ],
      ),
      RecentContact(
        callsign: 'NOCALL',
        lastMessage: 'Praesent euismod nisl id ex scelerisque...',
        time: 'Yesterday',
        unread: false,
        messages: [
          ChatMessage(fromMe: false, text: "How's it going?", time: "Yesterday"),
          ChatMessage(fromMe: true, text: "Doing well, you?", time: "Yesterday"),
          ChatMessage(fromMe: false, text: "Praesent euismod nisl id ex scelerisque...", time: "Yesterday"),
        ],
      ),
      RecentContact(
        callsign: 'K5ABC',
        lastMessage: 'Thanks for the info!',
        time: '2 days ago',
        unread: false,
        messages: [
          ChatMessage(fromMe: true, text: "Let me know if you need anything else.", time: "2 days ago"),
          ChatMessage(fromMe: false, text: "Thanks for the info!", time: "2 days ago"),
        ],
      ),
    ];
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || selectedIndex == null) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          elevation: 1,
          titleSpacing: 24,
          title: Row(
            children: [
              Icon(Icons.message_rounded, size: 28, color: theme.colorScheme.primary),
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
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_none_outlined, color: Colors.teal.shade700),
                    onPressed: () {},
                  ),
                  Positioned(
                    right: 6,
                    top: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: const Center(
                        child: Text('2', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
                        child: Row(
                          children: [
                            Icon(Icons.history, color: theme.colorScheme.primary, size: 22),
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
                                  Icon(Icons.message_rounded, color: theme.colorScheme.primary.withOpacity(0.4), size: 56),
                                  const SizedBox(height: 24),
                                  Text(
                                    "Welcome, ${widget.callsign}!",
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
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                  color: theme.colorScheme.primary.withOpacity(0.05),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: theme.colorScheme.primary.withOpacity(0.13),
                                      foregroundColor: theme.colorScheme.primary,
                                      child: Text(recents[selectedIndex!].callsign.substring(0, 1)),
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
                                        color: theme.colorScheme.primary.withOpacity(0.6),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                  itemCount: recents[selectedIndex!].messages.length,
                                  itemBuilder: (context, i) {
                                    final msg = recents[selectedIndex!].messages[i];
                                    return ChatBubble(message: msg);
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _chatController,
                                        decoration: InputDecoration(
                                          hintText: "Type a message...",
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(48),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey.shade100,
                                          contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 10),
                                        ),
                                        onSubmitted: (_) => _sendMessage(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    CircleAvatar(
                                      backgroundColor: theme.colorScheme.primary,
                                      child: IconButton(
                                        icon: const Icon(Icons.send, color: Colors.white),
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
