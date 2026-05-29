import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(const DeepWorkBrokerApp());
}

class DeepWorkBrokerApp extends StatelessWidget {
  const DeepWorkBrokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life-OS Broker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DashboardScreen(), // Sets your new screen as the homepage
    );
  }
}
