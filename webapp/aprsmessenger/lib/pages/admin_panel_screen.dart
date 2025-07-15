import 'package:flutter/material.dart';

class AdminPanelScreen extends StatelessWidget {
  final String callsign;
  const AdminPanelScreen({super.key, required this.callsign});

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
            child: ListView(
              children: [
                Row(
                  children: [
                    Icon(Icons.admin_panel_settings, color: Colors.red.shade700, size: 40),
                    const SizedBox(width: 16),
                    Text(
                      "Administrator Dashboard",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Logged In Users", style: theme.textTheme.titleMedium),
                        const Divider(),
                        const ListTile(
                          leading: Icon(Icons.person),
                          title: Text("k8sdr"),
                          subtitle: Text("Active"),
                        ),
                        const ListTile(
                          leading: Icon(Icons.person),
                          title: Text("ad8nt"),
                          subtitle: Text("Active"),
                        ),
                        const ListTile(
                          leading: Icon(Icons.person),
                          title: Text("n0call"),
                          subtitle: Text("Idle"),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text("Refresh"),
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("System Usage", style: theme.textTheme.titleMedium),
                        const Divider(),
                        Row(
                          children: [
                            Icon(Icons.memory, color: Colors.blueGrey.shade700),
                            const SizedBox(width: 10),
                            const Text("CPU Load:"),
                            const SizedBox(width: 10),
                            Text("4.2%", style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.storage, color: Colors.blueGrey.shade700),
                            const SizedBox(width: 10),
                            const Text("Memory Usage:"),
                            const SizedBox(width: 10),
                            Text("732 MB / 2 GB", style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.ssid_chart, color: Colors.blueGrey.shade700),
                            const SizedBox(width: 10),
                            const Text("Network:"),
                            const SizedBox(width: 10),
                            Text("34.2 kB/s", style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("APRS Message Monitor", style: theme.textTheme.titleMedium),
                        const Divider(),
                        const ListTile(
                          leading: Icon(Icons.message),
                          title: Text("Total Messages (24h)"),
                          trailing: Text("328"),
                        ),
                        const ListTile(
                          leading: Icon(Icons.forum),
                          title: Text("Messages in Queue"),
                          trailing: Text("2"),
                        ),
                        const ListTile(
                          leading: Icon(Icons.cancel, color: Colors.red),
                          title: Text("Failed Deliveries"),
                          trailing: Text("0"),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Server Controls", style: theme.textTheme.titleMedium),
                        const Divider(),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.restart_alt),
                              label: const Text("Restart Service"),
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.settings),
                              label: const Text("Settings"),
                              onPressed: () {},
                            ),
                          ],
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
    );
  }
}