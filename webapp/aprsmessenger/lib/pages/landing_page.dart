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

    // Use the service to connect
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
      socketService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 800;
          return Row(
            children: [
              // Left: Hero/Blurb Section
              if (isWide)
                Expanded(
                  flex: 3,
                  child: Container(
                    height: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
                    color: theme.colorScheme.primary.withOpacity(0.07),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo/Icon
                        Row(
                          children: [
                            Icon(Icons.message_rounded, size: 54, color: theme.colorScheme.primary),
                            const SizedBox(width: 20),
                            Text(
                              "APRS Messenger",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 38,
                                color: theme.colorScheme.primary,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Text(
                          "Connect the World in Real Time",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface.withOpacity(0.95),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          "APRS Messenger lets you send and receive APRS messages globally, instantly. "
                          "Whether you're a ham operator, a rescue volunteer, or an experimenter, our service brings the power of real-time radio messaging to your fingertips — anywhere, anytime.",
                          style: TextStyle(
                            fontSize: 20,
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Icon(Icons.public, color: theme.colorScheme.primary),
                            const SizedBox(width: 10),
                            Text(
                              "Secure • Fast • Community Driven",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // (Optional) Add an illustration or hero image here for extra flair
                        // Expanded(child: Image.asset('assets/hero.png', fit: BoxFit.contain)),
                      ],
                    ),
                  ),
                ),
              // Right: Login/Register Card
              Expanded(
                flex: 2,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Card(
                      elevation: 6,
                      margin: EdgeInsets.symmetric(horizontal: isWide ? 32 : 12, vertical: isWide ? 60 : 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 42),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isWide)
                                Column(
                                  children: [
                                    Icon(Icons.message_rounded, size: 48, color: theme.colorScheme.primary),
                                    const SizedBox(height: 12),
                                    Text(
                                      "APRS Messenger",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 26,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ),
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
                                  onPressed: isLoading ? null : _attemptConnection,
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}