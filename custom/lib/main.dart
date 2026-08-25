import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'session_state.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const IntercomApp());
}

class IntercomApp extends StatelessWidget {
  const IntercomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionState(),
      child: MaterialApp(
        title: 'Intercom',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}
