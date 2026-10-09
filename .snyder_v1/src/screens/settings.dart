import 'package:flutter/material.dart';
import '../db.dart';
import '../services/backup_service.dart';
import '../services/local_files.dart';
import '../services/property_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'setup_wizard.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.refreshRoot});
  final VoidCallback refreshRoot;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Snyder Family Settings'), backgroundColor: SnyderColors.bg),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(14), children: [
          SnyderCard(accent: SnyderColors.green, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionTitle(Icons.phonelink_lock, 'Phone-only Privacy', color: SnyderColors.green), const SizedBox(height: 10),
            const Text('Snyder Family stores its database and copied Property Hub documents inside Android app-private storage.'),
            const SizedBox(height: 8),
            const Text('No account • No cloud database • No bank connection • No Internet permission • Android cloud backup disabled', style: TextStyle(color: SnyderColors.green, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Manual exports happen only when you explicitly choose a destination in the Android file picker.', style: TextStyle(color: SnyderColors.muted)),
          ])),
          const SizedBox(height: 12),
          SnyderCard(accent: SnyderColors.violet, child: Column(children: [
            sectionTitle(Icons.security, 'Encrypted Backup / Restore'),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Backups include the Snyder Family database and any locally copied Property Hub documents. They are AES-256-GCM encrypted with a password you choose.', style: TextStyle(color: SnyderColors.muted, fontSize: 12))),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : _exportBackup, icon: const Icon(Icons.lock_outline), label: const Text('Create Encrypted Backup'))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: busy ? null : _restoreBackup, icon: const Icon(Icons.restore), label: const Text('Restore Encrypted Backup'))),
          ])),
          const SizedBox(height: 12),
          SnyderCard(accent: SnyderColors.blue, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionTitle(Icons.move_to_inbox_outlined, 'Landlord Control Center Import'), const SizedBox(height: 8),
            const Text('Import an existing v7 landlord JSON file into Property Hub. Posted charges, payments, credits, receipts, expenses, journal records, and audit history are migrated without changing the original file.', style: TextStyle(color: SnyderColors.muted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: busy ? null : _importLegacy, icon: const Icon(Icons.file_open), label: const Text('Import Landlord v7 JSON'))),
          ])),
          const SizedBox(height: 12),
          SnyderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionTitle(Icons.info_outline, 'About Snyder Family'), const SizedBox(height: 8),
            const Text('Version 1.0.0 • Private household operating system'),
            const Text('Home + money + stockpile + planning + property + records', style: TextStyle(color: SnyderColors.lavender)),
            const SizedBox(height: 8),
            const Text('Property Hub is recordkeeping software, not universal legal or tax advice. Jurisdiction-specific notices, eviction procedures, deposit rules, tax treatment, and evidentiary requirements should be reviewed separately.', style: TextStyle(color: SnyderColors.muted, fontSize: 11)),
          ])),
          const SizedBox(height: 12),
          SnyderCard(accent: SnyderColors.danger, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionTitle(Icons.delete_forever_outlined, 'Reset Local App', color: SnyderColors.danger), const SizedBox(height: 8),
            const Text('This permanently deletes the local Snyder Family database from this phone. Create an encrypted backup first if you may need the records later.', style: TextStyle(color: SnyderColors.muted)),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: busy ? null : _reset, icon: const Icon(Icons.delete_forever, color: SnyderColors.danger), label: const Text('Erase Local Snyder Family Data')),
          ])),
          if (busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        ]),
      ),
    );
  }

  Future<String?> _passwordDialog(String title, {bool confirm = false}) async {
    final pass = TextEditingController(), again = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(title), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Backup password')), if (confirm) ...[const SizedBox(height: 8), TextField(controller: again, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password'))],
      const SizedBox(height: 8), const Text('Keep this password somewhere safe. Snyder Family cannot recover an encrypted backup without it.', style: TextStyle(color: SnyderColors.muted, fontSize: 11)),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Continue'))]));
    if (ok != true) return null;
    if (pass.text.length < 6) { if (mounted) showMessage(context, 'Use at least 6 characters.'); return null; }
    if (confirm && pass.text != again.text) { if (mounted) showMessage(context, 'Passwords did not match.'); return null; }
    return pass.text;
  }

  Future<void> _exportBackup() async {
    final password = await _passwordDialog('Create encrypted backup', confirm: true); if (password == null) return;
    setState(() => busy = true);
    try { await BackupService.exportEncrypted(password); if (mounted) showMessage(context, 'Android save dialog opened for your encrypted backup.'); } catch (e) { if (mounted) showError(context, e); } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _restoreBackup() async {
    final password = await _passwordDialog('Restore encrypted backup'); if (password == null) return;
    final yes = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Replace current local data?'), content: const Text('Restore will replace the current Snyder Family database on this phone with the selected backup.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Restore'))]));
    if (yes != true) return;
    setState(() => busy = true);
    try { await BackupService.importEncrypted(password); widget.refreshRoot(); if (mounted) showMessage(context, 'Backup restored.'); } catch (e) { if (mounted) showError(context, 'Restore failed. Check the file and password.\n$e'); } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _importLegacy() async {
    setState(() => busy = true);
    try {
      final file = await LocalFiles.pickFile(mimeTypes: const ['application/json', 'text/plain', '*/*']);
      if (file == null) return;
      final id = await PropertyService.importLegacyV7Bytes(file.bytes);
      widget.refreshRoot();
      if (mounted) showMessage(context, 'Landlord v7 data imported as Property #$id.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reset() async {
    final phrase = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Erase local data?'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('This cannot be undone without a backup. Type ERASE to confirm.'), const SizedBox(height: 10), TextField(controller: phrase, decoration: const InputDecoration(labelText: 'Type ERASE'))]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Erase'))]));
    if (ok != true || phrase.text.trim() != 'ERASE') return;
    setState(() => busy = true);
    await AppDb.i.wipeAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SetupWizard()), (_) => false);
  }
}