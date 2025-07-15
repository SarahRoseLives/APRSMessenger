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
      body: Padding(
        padding: const EdgeInsets.all(8.0), // Reduced padding for mobile
        child: ListView(
          padding: const EdgeInsets.all(8.0), // Reduced padding for mobile
          children: [
            Row(
              children: [
                Icon(Icons.admin_panel_settings, color: Colors.red.shade700, size: 32),
                const SizedBox(width: 12),
                Text(
                  "Admin Dashboard",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Logged In Users", style: theme.textTheme.titleMedium),
                    const Divider(),
                    const ListTile(leading: Icon(Icons.person), title: Text("k8sdr"), subtitle: Text("Active")),
                    const ListTile(leading: Icon(Icons.person), title: Text("ad8nt"), subtitle: Text("Active")),
                    const ListTile(leading: Icon(Icons.person), title: Text("n0call"), subtitle: Text("Idle")),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text("Refresh"),
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("System Usage", style: theme.textTheme.titleMedium),
                    const Divider(),
                    const ListTile(leading: Icon(Icons.memory), title: Text("CPU Load"), trailing: Text("4.2%")),
                    const ListTile(leading: Icon(Icons.storage), title: Text("Memory"), trailing: Text("732MB / 2GB")),
                    const ListTile(leading: Icon(Icons.ssid_chart), title: Text("Network"), trailing: Text("34.2 kB/s")),
                  ],
                ),
              ),
            ),
             const SizedBox(height: 12),
             Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Server Controls", style: theme.textTheme.titleMedium),
                    const Divider(),
                     Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.restart_alt),
                          label: const Text("Restart"),
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                        ),
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
          ],
        ),
      ),
    );
  }
}