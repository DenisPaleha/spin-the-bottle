import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SpinTheBottleApp());
}

class SpinTheBottleApp extends StatelessWidget {
  const SpinTheBottleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spin the Bottle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
      ),
      home: const GamePage(),
    );
  }
}