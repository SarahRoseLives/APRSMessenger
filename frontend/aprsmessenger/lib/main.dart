import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'pages/landing_page.dart' as web;
import 'appui/landing_page.dart' as app;

void main() => runApp(const APRSMessengerApp());

class APRSMessengerApp extends StatelessWidget {
  const APRSMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Determine if the platform is a desktop OS (Linux, Windows, macOS).
    final bool isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return MaterialApp(
      title: 'APRS Messenger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Colors.teal.shade400,
          secondary: Colors.teal.shade200,
          background: const Color(0xfff5f6fa),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xfff5f6fa),
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.teal.shade700,
          elevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.teal.shade700,
            fontSize: 21,
            letterSpacing: 0.2,
          ),
          iconTheme: IconThemeData(
            color: Colors.teal.shade700,
          ),
        ),
      ),
      // Use the desktop UI for web and desktop platforms, otherwise use the app UI.
      home: isDesktop || kIsWeb ? const web.LandingPage() : const app.LandingPage(),
    );
  }
}