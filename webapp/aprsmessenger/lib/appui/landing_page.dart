// appui/landing_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import 'home_screen.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  bool isRegister = false;
  bool isLoading = false;
  String? errorMsg;

  final TextEditingController _callsignController = TextEditingController();
  final TextEditingController _passcodeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _callsignController.dispose();
    _passcodeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _attemptConnection() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
      errorMsg = null;
    });

    final callsign = _callsignController.text.trim().toUpperCase();
    final password = _passwordController.text;

    // Validation
    if (callsign.isEmpty || password.isEmpty) {
      setState(() {
        errorMsg = "Callsign and password are required.";
        isLoading = false;
      });
      return;
    }
    if (isRegister) {
      if (_passcodeController.text.isEmpty || _confirmController.text.isEmpty) {
        setState(() {
          errorMsg = "Please fill in all fields.";
          isLoading = false;
        });
        return;
      }
      if (password != _confirmController.text) {
        setState(() {
          errorMsg = "Passwords do not match.";
          isLoading = false;
        });
        return;
      }
    }

    final socketService = WebSocketService();
    final bool success = await socketService.connect(
      callsign,
      password,
      passcode: isRegister ? _passcodeController.text.trim() : null,
    );

    if (!mounted) return;

    setState(() => isLoading = false);

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: socketService,
            child: const HomeScreen(),
          ),
        ),
      );
    } else {
      setState(() => errorMsg = socketService.connectionError);
      socketService.dispose(); // Clean up if connection failed
    }
  }

  // --- BUILD METHOD (UNCHANGED) ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The existing build method content goes here.
    // Just change the onPressed handlers for the button:
    // onPressed: isLoading ? null : _attemptConnection
    // ... rest of the build method
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.message_rounded, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 18),
              Text(
                "APRS Messenger",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isRegister ? "Create a new account" : "Login to continue",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 17),
              ),
              const SizedBox(height: 24),
              ToggleButtons(
                isSelected: [!isRegister, isRegister],
                onPressed: (i) => setState(() {
                  isRegister = i == 1;
                  errorMsg = null;
                }),
                borderRadius: BorderRadius.circular(10),
                fillColor: theme.colorScheme.primary,
                selectedColor: Colors.white,
                color: theme.colorScheme.primary,
                constraints: const BoxConstraints(minHeight: 40.0),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Login")),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Register")),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _callsignController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: "Callsign",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: Icon(Icons.account_circle_outlined, color: theme.colorScheme.primary),
                ),
                enabled: !isLoading,
              ),
              if (isRegister) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _passcodeController,
                  decoration: InputDecoration(
                    labelText: "Passcode",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: Icon(Icons.confirmation_num, color: theme.colorScheme.primary),
                    helperText: "Your APRS-IS passcode.",
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !isLoading,
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                ),
                obscureText: true,
                enabled: !isLoading,
              ),
              if (isRegister) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: Icon(Icons.lock_person_outlined, color: theme.colorScheme.primary),
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                ),
              ],
              const SizedBox(height: 22),
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    errorMsg!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isLoading ? null : _attemptConnection,
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isRegister ? "Register" : "Login", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}