import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    if (_streamSubscription == null) {
      _socketService = Provider.of<WebSocketService>(context);
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

      // --- HANDLE SPECIAL (NON-APRS) MESSAGES ---
      if (msg is Map && msg.containsKey('type')) {
        switch (msg['type']) {
          case 'conversation_deleted':
            final contact = msg['contact'];
            setState(() {
              recents.removeWhere((c) => c.groupingId == contact);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Conversation with $contact deleted.")),
            );
            return;
          case 'callsign_blocked':
            final contact = msg['contact'];
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("$contact has been blocked.")),
            );
            return;
          case 'data_export':
            _showDataExportDialog(msg['data']);
            return;
          case 'account_deleted':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Account successfully deleted.")),
            );
            _logout(); // This will navigate to landing page
            return;
        }
      }

      if (msg["aprs_msg"] == true) {
        final from = (msg["from"] as String).toUpperCase();
        final to = (msg["to"] as String).toUpperCase();
        final text = msg["message"] ?? "";
        final createdAt = msg["created_at"];
        final isHistory = msg["history"] == true;
        final bool isAdminMsg = from == 'ADMIN';

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
        final groupingKey =
            isAdminMsg ? 'ADMIN' : otherPartyCallsign.split('-').first;

        final messageId = msg['messageId']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString();

        final newMessage = ChatMessage(
          messageId: messageId,
          fromMe: fromMe,
          text: text,
          time: _formatTime(createdAt),
        );

        final idx = recents.indexWhere((c) => c.groupingId == groupingKey);

        if (idx == -1) {
          recents.add(RecentContact(
            groupingId: groupingKey,
            callsign: isAdminMsg ? 'ADMIN' : otherPartyCallsign,
            ownCallsign: isAdminMsg ? 'ADMIN' : ownCallsignForChat,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: !fromMe && !isHistory,
            messages: [newMessage],
            route: routeHops,
            isAdminMessage: isAdminMsg,
          ));
        } else {
          final contact = recents[idx];

          if (contact.messages.any((m) => m.messageId == newMessage.messageId)) {
            return; // Skip duplicate
          }

          final updatedMessages = List<ChatMessage>.from(contact.messages)
            ..add(newMessage);

          updatedMessages
              .sort((a, b) => (a.time ?? "").compareTo(b.time ?? ""));

          recents[idx] = contact.copyWith(
            callsign: isAdminMsg ? 'ADMIN' : otherPartyCallsign,
            ownCallsign: isAdminMsg ? 'ADMIN' : ownCallsignForChat,
            lastMessage: text,
            time: _formatTime(createdAt),
            unread: (!fromMe && !isHistory) || contact.unread,
            messages: updatedMessages,
            route: routeHops ?? contact.route,
            isAdminMessage: isAdminMsg,
          );
        }
        recents.sort((a, b) {
          if (a.isAdminMessage && !b.isAdminMessage) return -1;
          if (!a.isAdminMessage && b.isAdminMessage) return 1;
          return (b.time).compareTo(a.time);
        });
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint("Error processing message in appui/home_screen: $e");
    }
  }

  void _logout() {
    _socketService.disconnect();
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LandingPage()),
        (route) => false);
  }

  void _showContactMenu(BuildContext context, RecentContact contact) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete Conversation'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showDeleteConversationDialog(contact);
                  }),
              if (!contact.isAdminMessage)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: Text('Block ${contact.groupingId}'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showBlockCallsignDialog(contact);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConversationDialog(RecentContact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Conversation"),
        content: Text(
            "Are you sure you want to delete all messages with ${contact.groupingId}? This cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              // For admin messages, the callsign is "ADMIN". For others, it's the contact's callsign.
              _socketService.deleteConversation(contact.callsign);
              Navigator.of(context).pop();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBlockCallsignDialog(RecentContact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Block Callsign"),
        content: Text(
            "Are you sure you want to block ${contact.groupingId}? You will no longer receive messages from them."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              _socketService.blockCallsign(contact.callsign);
              Navigator.of(context).pop();
            },
            child: const Text("Block", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDataExportDialog(dynamic data) {
    // Pretty-print the JSON.
    final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("Your Data Export"),
              content: SingleChildScrollView(child: SelectableText(prettyJson)),
              actions: [
                TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: prettyJson)),
                    child: const Text("Copy to Clipboard")),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close")),
              ],
            ));
  }

  void _showDeleteAccountDialog() {
    final passwordController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("Delete Account"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      "This action is irreversible and will delete all your messages and account data.\n\nPlease enter your password to confirm.",
                      style: TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Password"),
                  )
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Cancel")),
                TextButton(
                  onPressed: () {
                    final password = passwordController.text;
                    if (password.isNotEmpty) {
                      _socketService.deleteAccount(password);
                      Navigator.of(context).pop();
                    }
                  },
                  child:
                      const Text("DELETE", style: TextStyle(color: Colors.red)),
                ),
              ],
            ));
  }

  void _showNewMessageDialog() {
    final callsignController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                child: const Text("Cancel")),
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
      contact = recents[existingIndex];
      if (contact.unread) {
        setState(() => recents[existingIndex] = contact.copyWith(unread: false));
      }
    } else {
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
                  builder: (_) => ChangeNotifierProvider.value(
                    value: socketService,
                    child: AdminPanelScreen(
                        callsign: socketService.callsign!),
                  ),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'download':
                  socketService.requestDataExport();
                  break;
                case 'delete_account':
                  _showDeleteAccountDialog();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'download',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Download My Data'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete_account',
                child: ListTile(
                  leading: Icon(Icons.delete_forever, color: Colors.red),
                  title: Text('Delete Account',
                      style: TextStyle(color: Colors.red)),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Logout'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: recents.length,
        itemBuilder: (context, i) {
          final contact = recents[i];
          return GestureDetector(
            onLongPress: () => _showContactMenu(context, contact),
            child: ContactTile(
              contact: contact,
              displayTime: _displayTime(contact.time),
              selected:
                  false, // Mobile UI doesn't have a "selected" state in the list
              onTap: () async {
                _navigateToChat(contact.callsign);
              },
            ),
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