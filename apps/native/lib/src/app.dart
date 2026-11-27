import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

class MineMeApp extends StatelessWidget {
  const MineMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MINE-ME',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080C11),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFADFF65),
          brightness: Brightness.dark,
          surface: const Color(0xFF111923),
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111923),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF273440)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF273440)),
          ),
        ),
      ),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          return session == null ? const LoginScreen() : const HomeScreen();
        },
      ),
    );
  }
}
