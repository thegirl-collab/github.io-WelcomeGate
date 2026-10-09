import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

String moneyFromCents(int cents) => NumberFormat.currency(symbol: r'$').format(cents / 100.0);
String money(double amount) => NumberFormat.currency(symbol: r'$').format(amount);
String shortDate(DateTime d) => DateFormat('MMM d, yyyy').format(d);
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseDate(Object? value) => DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
int centsFromText(String value) => ((double.tryParse(value.replaceAll(',', '').replaceAll(r'$', '')) ?? 0) * 100).round();

class SnyderCard extends StatelessWidget {
  const SnyderCard({super.key, required this.child, this.accent = SnyderColors.cyan, this.padding = const EdgeInsets.all(15)});
  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: SnyderColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .44)),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: .08), blurRadius: 20)],
      ),
      child: child,
    );
  }
}

Widget sectionTitle(IconData icon, String title, {Widget? trailing, Color color = SnyderColors.cyan}) {
  return Row(
    children: [
      Icon(icon, color: color, size: 21),
      const SizedBox(width: 8),
      Expanded(child: Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .55))),
      if (trailing != null) trailing,
    ],
  );
}

class SnyderHeader extends StatelessWidget {
  const SnyderHeader({super.key, required this.title, required this.subtitle, this.actions = const []});
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF071221), Color(0xFF18152D), Color(0xFF07131E)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: SnyderColors.violet.withValues(alpha: .52)),
        boxShadow: [BoxShadow(color: SnyderColors.cyan.withValues(alpha: .08), blurRadius: 24)],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset('assets/snyder_logo.png', width: 82, height: 82, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: SnyderColors.lavender, fontSize: 12)),
                const SizedBox(height: 7),
                const Text('☾  Our Home • Our Plan • Our Peace  🐦‍⬛', style: TextStyle(color: SnyderColors.muted, fontSize: 10)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class SnyderPage extends StatelessWidget {
  const SnyderPage({super.key, required this.title, required this.subtitle, required this.child, this.actions = const []});
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SnyderHeader(title: title, subtitle: subtitle, actions: actions)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
            sliver: SliverToBoxAdapter(child: child),
          ),
        ],
      ),
    );
  }
}

Future<DateTime?> pickDate(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}