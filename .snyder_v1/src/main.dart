import 'package:flutter/material.dart';
import 'db.dart';
import 'screens/setup_wizard.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.i.open();
  runApp(const SnyderFamilyApp());
}

class SnyderFamilyApp extends StatelessWidget {
  const SnyderFamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Snyder Family',
      theme: snyderTheme(),
      home: FutureBuilder<bool>(
        future: AppDb.i.isSetupComplete(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snap.data! ? const AppShell() : const SetupWizard();
        },
      ),
    );
  }
}