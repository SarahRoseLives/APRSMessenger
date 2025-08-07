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
        if (!mounted) return;
        if (msg['success'] == true) {
          setState(() {
            _users = msg['users'] ?? [];
            _stats = msg['stats'] ?? {};
            _userCount = msg['userCount'] ?? 0;
            _isLoading = false;
            _error = null;
          });
        } else {
          setState(() {
            _error = msg['error'] ?? "Failed to load admin data.";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Ignore parse errors
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text("Error: $_error",
                      style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: () async => _fetchStats(),
                  child: ListView(
                    padding: const EdgeInsets.all(12.0),
                    children: [
                      Row(
                        children: [
                          Icon(Icons.admin_panel_settings,
                              color: Colors.red.shade700, size: 32),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              "Admin Dashboard",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Broadcast Card
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Broadcast System Message",
                                  style: theme.textTheme.titleMedium),
                              const Divider(),
                              TextField(
                                controller: _broadcastController,
                                decoration: const InputDecoration(
                                  labelText: 'Message',
                                  hintText: 'Enter announcement...',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 2,
                                maxLength: 200,
                                enabled: !_isSendingBroadcast,
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                icon: _isSendingBroadcast
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.campaign_outlined),
                                label: Text(_isSendingBroadcast
                                    ? "Sending..."
                                    : "Send Broadcast"),
                                onPressed:
                                    _isSendingBroadcast ? null : _sendBroadcast,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Gateway Statistics",
                                  style: theme.textTheme.titleMedium),
                              const Divider(),
                              ListTile(
                                leading: const Icon(Icons.people_outline),
                                title: const Text("Registered Users"),
                                trailing: Text(_userCount.toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                              ListTile(
                                leading: const Icon(Icons.forum_outlined),
                                title: const Text("Messages Processed"),
                                trailing: Text(
                                    (_stats['total_messages'] ?? 0).toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text("Refresh"),
                                onPressed: _fetchStats,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Registered Users ($_userCount)",
                                  style: theme.textTheme.titleMedium),
                              const Divider(),
                              // Use a constrained box to prevent the ListView from taking infinite height inside another ListView
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 400),
                                child: _users.isEmpty
                                    ? const Center(
                                        child: Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: Text("No users found.")))
                                    : ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: _users.length,
                                        itemBuilder: (context, index) {
                                          final user = _users[index];
                                          return ListTile(
                                            dense: true,
                                            leading: const Icon(Icons.person),
                                            title: Text(
                                                user['callsign'] ?? 'N/A'),
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
                    ],
                  ),
                ),
    );
  }
}