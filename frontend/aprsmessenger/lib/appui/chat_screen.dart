import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import '../services/websocket_service.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  final RecentContact contact;

  const ChatScreen({
    super.key,
    required this.contact,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription _streamSubscription;
  late WebSocketService _socketService;
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.contact.messages);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _socketService = Provider.of<WebSocketService>(context, listen: false);
    _streamSubscription = _socketService.messages.listen(_onNewMessage);
  }

  void _onNewMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw);
      if (msg["aprs_msg"] == true) {
        final from = (msg["from"] as String).toUpperCase();
        final to = (msg["to"] as String).toUpperCase();
        final contactCallsign = widget.contact.callsign;

        final userBaseCallsign = _socketService.callsign!.split('-').first;
        final fromBaseCallsign = from.split('-').first;
        final toBaseCallsign = to.split('-').first;

        final isFromMe = fromBaseCallsign == userBaseCallsign;
        final isToMe = toBaseCallsign == userBaseCallsign;

        final isFromContact = (from == contactCallsign);
        final isToContact = (to == contactCallsign);

        if ((isFromContact && isToMe) || (isFromMe && isToContact)) {
          if (_messages.any((m) => m.text == msg["message"] && m.fromMe == isFromMe)) {
            return; // Avoid duplicates
          }
          setState(() {
            _messages.add(ChatMessage(
              fromMe: isFromMe,
              text: msg["message"] ?? "",
              time: _formatTime(msg["created_at"]),
            ));
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    _socketService.sendMessage(
        toCallsign: widget.contact.callsign,
        message: text,
        fromCallsign: widget.contact.ownCallsign);

    final sentMessage = ChatMessage(fromMe: true, text: text, time: _currentTime());
    setState(() {
      _messages.add(sentMessage);
      widget.contact.messages.add(sentMessage); // Update shared contact object
      widget.contact.copyWith(lastMessage: text);
    });
    _chatController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _currentTime() {
    final now = TimeOfDay.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return _currentTime();
    final dt = DateTime.tryParse(isoTime);
    if (dt == null) return _currentTime();
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _streamSubscription.cancel();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- BUILD METHOD (UNCHANGED) ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contact.callsign),
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              itemCount: _messages.length,
              itemBuilder: (context, i) => ChatBubble(message: _messages[i]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            color: Colors.white,
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
    );
  }
}