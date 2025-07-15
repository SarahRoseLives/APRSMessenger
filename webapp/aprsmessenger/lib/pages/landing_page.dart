import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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

  WebSocketChannel? _channel;

  @override
  void dispose() {
    // Do NOT close the channel here! It will be passed to HomeScreen and closed there.
    _callsignController.dispose();
    _passcodeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // Only open the WebSocket and send data, pass the open channel to HomeScreen.
  void _connectAndSend(Map<String, dynamic> data, void Function(WebSocketChannel channel) onConnected) {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://localhost:8080/ws'),
    );
    _channel!.sink.add(jsonEncode(data));
    onConnected(_channel!);
  }

  void _login() {
    setState(() {
      isLoading = true;
      errorMsg = null;
    });
    final callsign = _callsignController.text.trim().toUpperCase();
    final password = _passwordController.text;
    if (callsign.isEmpty || password.isEmpty) {
      setState(() {
        errorMsg = "Fill in all fields";
        isLoading = false;
      });
      return;
    }
    _connectAndSend({
      "action": "login",
      "callsign": callsign,
      "password": password,
    }, (channel) {
      setState(() => isLoading = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(callsign: callsign, channel: channel)),
      );
    });
  }

  void _register() {
    setState(() {
      isLoading = true;
      errorMsg = null;
    });
    final callsign = _callsignController.text.trim().toUpperCase();
    final passcode = _passcodeController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (callsign.isEmpty || passcode.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() {
        errorMsg = "Fill in all fields";
        isLoading = false;
      });
      return;
    }
    if (password != confirm) {
      setState(() {
        errorMsg = "Passwords do not match";
        isLoading = false;
      });
      return;
    }
    _connectAndSend({
      "action": "create_account",
      "callsign": callsign,
      "passcode": passcode,
      "password": password,
    }, (channel) {
      setState(() => isLoading = false);
      // After registration, immediately login using the same open channel.
      _connectAndSend({
        "action": "login",
        "callsign": callsign,
        "password": password,
      }, (loginChannel) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(callsign: callsign, channel: loginChannel)),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Card(
          elevation: 3,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 42),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.message_rounded, size: 54, color: theme.colorScheme.primary),
                  const SizedBox(height: 18),
                  Text(
                    "APRS Messenger",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ToggleButtons(
                    isSelected: [!isRegister, isRegister],
                    onPressed: (i) {
                      setState(() {
                        isRegister = i == 1;
                        errorMsg = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    selectedColor: Colors.white,
                    fillColor: theme.colorScheme.primary,
                    color: theme.colorScheme.primary,
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text("Login"),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text("Register"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isRegister ? "Create a new account" : "Login with your callsign to continue",
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 18),
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
                        helperText: "Obtain your APRS passcode for your callsign.",
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
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isLoading
                          ? null
                          : isRegister
                              ? _register
                              : _login,
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(isRegister ? "Register" : "Login",
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}