import 'package:flutter/material.dart';
import 'pages/landing_page.dart';

void main() => runApp(const APRSMessengerApp());

class APRSMessengerApp extends StatelessWidget {
  const APRSMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      home: const LandingPage(),
    );
  }
}