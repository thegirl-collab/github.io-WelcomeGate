import 'package:flutter/material.dart';
import '../theme.dart';
import 'dashboard.dart';
import 'life.dart';
import 'stockpile.dart';
import 'finances.dart';
import 'property.dart';
import 'settings.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  int token = 0;
  void refresh() => setState(() => token++);

  Future<void> openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(refreshRoot: refresh)));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(token: token, refresh: refresh, openSettings: openSettings),
      LifeScreen(token: token, refresh: refresh, openSettings: openSettings),
      StockpileScreen(token: token, refresh: refresh, openSettings: openSettings),
      FinancesScreen(token: token, refresh: refresh, openSettings: openSettings),
      PropertyScreen(token: token, refresh: refresh, openSettings: openSettings),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_motion_outlined), selectedIcon: Icon(Icons.auto_awesome_motion), label: 'Life'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stockpile'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Finances'),
          NavigationDestination(icon: Icon(Icons.key_outlined), selectedIcon: Icon(Icons.key, color: SnyderColors.violet), label: 'Property'),
        ],
      ),
    );
  }
}