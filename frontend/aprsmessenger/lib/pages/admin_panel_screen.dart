import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';

class AdminPanelScreen extends StatefulWidget {
  final String callsign;
  const AdminPanelScreen({super.key, required this.callsign});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late WebSocketService _socketService;
  StreamSubscription? _streamSubscription;

  final TextEditingController _broadcastController = TextEditingController();
  bool _isSendingBroadcast = false;

  bool _isLoading = true;
  String? _error;
  List<dynamic> _users = [];
  Map<String, dynamic> _stats = {};
  int _userCount = 0;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure the provider is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _socketService = Provider.of<WebSocketService>(context, listen: false);
      _streamSubscription = _socketService.messages.listen(_onMessage);
      _fetchStats();
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _broadcastController.dispose();
    super.dispose();
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw);
      if (msg is Map && msg['type'] == 'admin_stats_update') {
        if (msg['success'] == true) {
          if (!mounted) return;
          setState(() {
            _users = msg['users'] ?? [];
            _stats = msg['stats'] ?? {};
            _userCount = msg['userCount'] ?? 0;
            _isLoading = false;
            _error = null;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _error = msg['error'] ?? "Failed to load admin data.";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Ignore parse errors for other message types
    }
  }

  void _fetchStats() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _socketService.requestAdminStats();
  }

  void _sendBroadcast() {
    final message = _broadcastController.text.trim();
    if (message.isEmpty) return;

    setState(() => _isSendingBroadcast = true);
    _socketService.sendAdminBroadcast(message);

    // Give feedback. A more robust solution would await a success response.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _isSendingBroadcast = false);
        _broadcastController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Broadcast sent!"), backgroundColor: Colors.green),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("APRS Admin Panel"),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text("Error: $_error",
                            style: const TextStyle(color: Colors.red)))
                    : RefreshIndicator(
                        onRefresh: () async => _fetchStats(),
                        child: ListView(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.admin_panel_settings,
                                    color: Colors.red.shade700, size: 40),
                                const SizedBox(width: 16),
                                Flexible(
                                  child: Text(
                                    "Administrator Dashboard",
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Broadcast Card
                            Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Broadcast System Message",
                                        style: theme.textTheme.titleMedium),
                                    const Divider(),
                                    const Text(
                                        "Send a message to all registered users. This will appear at the top of their message list and cannot be replied to."),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: _broadcastController,
                                      decoration: const InputDecoration(
                                        labelText: 'Message',
                                        hintText:
                                            'Enter your announcement here...',
                                        border: OutlineInputBorder(),
                                      ),
                                      maxLines: 3,
                                      maxLength: 200,
                                      enabled: !_isSendingBroadcast,
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      icon: _isSendingBroadcast
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : const Icon(Icons.campaign_outlined),
                                      label: Text(_isSendingBroadcast
                                          ? "Sending..."
                                          : "Send to All Users"),
                                      onPressed:
                                          _isSendingBroadcast ? null : _sendBroadcast,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade600,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            // Stats Card
                            Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Gateway Statistics",
                                        style: theme.textTheme.titleMedium),
                                    const Divider(),
                                    ListTile(
                                      leading: const Icon(Icons.people),
                                      title: const Text("Total Registered Users"),
                                      trailing: Text(_userCount.toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.message),
                                      title: const Text(
                                          "Total Messages Processed"),
                                      trailing: Text(
                                          (_stats['total_messages'] ?? 0)
                                              .toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.refresh),
                                          label: const Text("Refresh"),
                                          onPressed: _fetchStats,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            // User List Card
                            Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Registered Users ($_userCount)",
                                        style: theme.textTheme.titleMedium),
                                    const Divider(),
                                    SizedBox(
                                      height: 300, // Constrain height
                                      child: _users.isEmpty
                                          ? const Center(
                                              child: Text("No users found."))
                                          : ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: _users.length,
                                              itemBuilder: (context, index) {
                                                final user = _users[index];
                                                return ListTile(
                                                  leading: const Icon(Icons
                                                      .person_outline),
                                                  title: Text(
                                                      user['callsign'] ??
                                                          'N/A'),
                                                  subtitle:
                                                      Text("ID: ${user['id']}"),
                                                );
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}