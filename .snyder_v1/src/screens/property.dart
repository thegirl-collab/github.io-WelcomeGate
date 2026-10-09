import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../db.dart';
import '../services/local_files.dart';
import '../services/property_service.dart';
import '../services/receipt_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PropertyScreen extends StatefulWidget {
  const PropertyScreen({super.key, required this.token, required this.refresh, required this.openSettings});
  final int token;
  final VoidCallback refresh;
  final VoidCallback openSettings;
  @override
  State<PropertyScreen> createState() => _PropertyScreenState();
}

class _PropertyScreenState extends State<PropertyScreen> {
  int view = 0;
  int? selectedProperty;
  final labels = const ['Overview', 'Ledger', 'Receipts', 'Expenses', 'Journal', 'Documents', 'Audit'];
  final icons = const [Icons.home_work_outlined, Icons.account_balance, Icons.receipt_long, Icons.build_outlined, Icons.menu_book_outlined, Icons.folder_copy_outlined, Icons.shield_outlined];

  @override
  Widget build(BuildContext context) {
    return SnyderPage(
      title: 'Property Hub',
      subtitle: 'Protect the property • Preserve the record',
      actions: [IconButton(onPressed: widget.openSettings, icon: const Icon(Icons.settings_outlined, color: SnyderColors.cyan))],
      child: FutureBuilder<List<Map<String, Object?>>>(
        key: ValueKey('properties-${widget.token}'),
        future: PropertyService.properties(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final props = snap.data!;
          if (props.isEmpty) return _noProperty();
          final ids = props.map((x) => x['id'] as int).toSet();
          final pid = selectedProperty != null && ids.contains(selectedProperty) ? selectedProperty! : props.first['id'] as int;
          final profile = props.firstWhere((x) => x['id'] == pid);
          return Column(children: [
            SnyderCard(accent: SnyderColors.violet, child: Row(children: [
              const Icon(Icons.key, color: SnyderColors.violet), const SizedBox(width: 9),
              Expanded(child: DropdownButtonFormField<int>(
                initialValue: pid,
                decoration: const InputDecoration(labelText: 'Property'),
                items: props.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text(p['label'].toString()))).toList(),
                onChanged: (v) => setState(() => selectedProperty = v),
              )),
              const SizedBox(width: 8),
              IconButton(onPressed: () => _propertyDialog(), icon: const Icon(Icons.add_home_work_outlined)),
            ])),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: view,
              decoration: const InputDecoration(labelText: 'Property Hub module'),
              items: List.generate(labels.length, (i) => DropdownMenuItem(value: i, child: Row(children: [Icon(icons[i], size: 19, color: i == 6 ? SnyderColors.violet : SnyderColors.cyan), const SizedBox(width: 8), Text(labels[i])]))),
              onChanged: (v) => setState(() => view = v ?? 0),
            ),
            const SizedBox(height: 12),
            IndexedStack(index: view, children: [
              _overview(pid, profile), _ledger(pid), _receipts(pid), _expenses(pid), _journal(pid), _documents(pid), _audit(pid),
            ]),
          ]);
        },
      ),
    );
  }

  Widget _noProperty() => Column(children: [
    SnyderCard(accent: SnyderColors.violet, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionTitle(Icons.key_outlined, 'Property Hub'), const SizedBox(height: 10),
      const Text('No rental property is configured yet. Create one here, or import your existing Landlord Control Center v7 JSON from Settings.'),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _propertyDialog(), icon: const Icon(Icons.add_home_work), label: const Text('Create Property'))),
    ])),
  ]);

  Widget _overview(int propertyId, Map<String, Object?> profile) => FutureBuilder<Map<String, dynamic>>(
    key: ValueKey('overview-$propertyId-${widget.token}'),
    future: _loadOverview(propertyId),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final d = snap.data!;
      final rule = d['rule'] as Map<String, Object?>?;
      return Column(children: [
        SnyderCard(accent: SnyderColors.violet, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.home_work_outlined, 'Property Overview', trailing: IconButton(onPressed: () => _propertyDialog(existing: profile), icon: const Icon(Icons.edit_outlined))),
          const SizedBox(height: 8),
          Text(profile['label'].toString(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          if (profile['address'].toString().isNotEmpty) Text(profile['address'].toString(), style: const TextStyle(color: SnyderColors.muted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('Tenant balance', moneyFromCents(d['balance'] as int), (d['balance'] as int) > 0 ? SnyderColors.warning : SnyderColors.green)),
            Expanded(child: _metric('YTD net cash flow', moneyFromCents(d['cashflow'] as int), (d['cashflow'] as int) >= 0 ? SnyderColors.green : SnyderColors.danger)),
          ]),
          const SizedBox(height: 10),
          Text('Tenant: ${profile['tenant_name'].toString().isEmpty ? 'Not set' : profile['tenant_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('Landlord / manager: ${profile['landlord_name'].toString().isEmpty ? 'Not set' : profile['landlord_name']}', style: const TextStyle(color: SnyderColors.muted)),
        ])),
        const SizedBox(height: 12),
        SnyderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.calendar_month, 'Rent Schedule', trailing: IconButton(onPressed: () => _rentRuleDialog(propertyId), icon: const Icon(Icons.add))),
          const SizedBox(height: 8),
          if (rule == null) const Text('No effective rent rule yet. Add the current rent and due day.') else ...[
            Text('${moneyFromCents(rule['amount_cents'] as int)} / month', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: SnyderColors.cyan)),
            Text('Due day ${rule['due_day']} • effective ${shortDate(parseDate(rule['effective_date']))}', style: const TextStyle(color: SnyderColors.muted)),
          ],
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () async { final n = await PropertyService.postChargesThroughToday(propertyId); widget.refresh(); if (mounted) showMessage(context, n == 0 ? 'No missing rent charges.' : '$n rent charge${n == 1 ? '' : 's'} posted.'); }, icon: const Icon(Icons.playlist_add_check), label: const Text('Post Any Missing Charges Through Today'))),
        ])),
      ]);
    },
  );

  Future<Map<String, dynamic>> _loadOverview(int pid) async {
    await PropertyService.postChargesThroughToday(pid);
    return {'balance': await PropertyService.balance(pid), 'cashflow': await PropertyService.rentCashFlow(pid, year: DateTime.now().year), 'rule': await PropertyService.ruleForDate(pid, DateTime.now())};
  }

  Widget _ledger(int propertyId) => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('ledger-$propertyId-${widget.token}'),
    future: PropertyService.ledger(propertyId),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!.reversed.toList();
      return Column(children: [
        SnyderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.account_balance, 'Rent Ledger'),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Posted financial history is append-only. Corrections are separate reversal or adjustment entries — never silent rewrites.', style: TextStyle(color: SnyderColors.muted, fontSize: 12))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => _paymentDialog(propertyId), icon: const Icon(Icons.add_card), label: const Text('Payment')),
            OutlinedButton.icon(onPressed: () => _creditDialog(propertyId), icon: const Icon(Icons.favorite_border), label: const Text('Credit / Waiver')),
            OutlinedButton.icon(onPressed: () => _adjustmentDialog(propertyId), icon: const Icon(Icons.tune), label: const Text('Adjustment')),
          ]),
        ])),
        const SizedBox(height: 12),
        SnyderCard(accent: SnyderColors.blue, child: Column(children: [
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Ledger is empty.')),
          ...rows.map((x) {
            final effect = x['effect_cents'] as int;
            final kind = x['kind'].toString();
            final canReverse = kind != 'reversal';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_kindIcon(kind), color: _kindColor(kind)),
              title: Text(x['description'].toString()),
              subtitle: Text('${shortDate(parseDate(x['event_date']))}${x['method'].toString().isEmpty ? '' : ' • ${x['method'] == 'Other' ? x['other_method'] : x['method']}'}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${effect > 0 ? '+' : '−'}${moneyFromCents(effect.abs())}', style: TextStyle(fontWeight: FontWeight.w900, color: effect > 0 ? SnyderColors.warning : SnyderColors.green)),
                if (canReverse) PopupMenuButton<String>(onSelected: (v) async { if (v == 'reverse') await _reverseLedger(x); }, itemBuilder: (_) => const [PopupMenuItem(value: 'reverse', child: Text('Post reversal'))]),
              ]),
            );
          }),
        ])),
      ]);
    },
  );

  IconData _kindIcon(String kind) => switch (kind) { 'payment' => Icons.south_west, 'charge' => Icons.north_east, 'credit' => Icons.favorite, 'reversal' => Icons.undo, _ => Icons.tune };
  Color _kindColor(String kind) => switch (kind) { 'payment' => SnyderColors.green, 'charge' => SnyderColors.warning, 'credit' => SnyderColors.violet, 'reversal' => SnyderColors.danger, _ => SnyderColors.cyan };

  Widget _receipts(int propertyId) => FutureBuilder<Map<String, dynamic>>(
    key: ValueKey('receipts-$propertyId-${widget.token}'),
    future: _loadReceipts(propertyId),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final payments = snap.data!['payments'] as List<Map<String, Object?>>;
      final receipts = snap.data!['receipts'] as List<Map<String, Object?>>;
      return Column(children: [
        SnyderCard(accent: SnyderColors.violet, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.receipt_long, 'Receipt Control'),
          const SizedBox(height: 8),
          const Text('Draft Preview does not create an issued record. Original receipts can remain prepared until you explicitly mark them issued / delivered. Once issued, revisions are separate preserved snapshots.', style: TextStyle(color: SnyderColors.muted, fontSize: 12)),
          const SizedBox(height: 10),
          if (payments.isEmpty) const Text('Record a rent payment first.'),
          ...payments.take(12).map((p) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.payments, color: SnyderColors.green),
            title: Text('${shortDate(parseDate(p['event_date']))} • ${moneyFromCents(p['amount_cents'] as int)}'),
            subtitle: Text('${p['method'] == 'Other' ? p['other_method'] : p['method']}${p['reference'].toString().isNotEmpty ? ' • ${p['reference']}' : ''}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'draft') { await ReceiptService.saveDraftPdf(p['id'] as int); if (mounted) showMessage(context, 'Draft PDF save dialog opened.'); }
                if (v == 'original') await _prepareOriginal(p['id'] as int);
                if (v == 'revision') await _prepareRevision(p['id'] as int);
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'draft', child: Text('Draft preview PDF')), PopupMenuItem(value: 'original', child: Text('Prepare original receipt')), PopupMenuItem(value: 'revision', child: Text('Prepare revised receipt'))],
            ),
          )),
        ])),
        const SizedBox(height: 12),
        SnyderCard(child: Column(children: [
          sectionTitle(Icons.history, 'Receipt History / Issue Status'),
          if (receipts.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No prepared receipts yet.')),
          ...receipts.map((r) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(r['status'] == 'issued' ? Icons.verified : Icons.description_outlined, color: r['status'] == 'issued' ? SnyderColors.green : SnyderColors.cyan),
            title: Text('${r['receipt_number']}${(r['revision'] as int) > 1 ? ' • Rev ${r['revision']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${r['document_type']} • ${r['status'] == 'issued' ? 'Issued / Delivered ${r['issued_at'] == null ? '' : shortDate(parseDate(r['issued_at']))}' : 'Prepared — not marked delivered'}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'pdf') { await ReceiptService.saveReceiptPdf(r); if (mounted) showMessage(context, 'Receipt PDF save dialog opened.'); }
                if (v == 'issue') { await ReceiptService.markIssued(r['id'] as int); widget.refresh(); }
              },
              itemBuilder: (_) => [const PopupMenuItem(value: 'pdf', child: Text('Save exact PDF snapshot')), if (r['status'] != 'issued') const PopupMenuItem(value: 'issue', child: Text('Mark issued / delivered'))],
            ),
          )),
        ])),
      ]);
    },
  );

  Future<Map<String, dynamic>> _loadReceipts(int pid) async {
    final ledger = await PropertyService.ledger(pid);
    return {
      'payments': ledger.where((x) => x['kind'] == 'payment').toList().reversed.toList(),
      'receipts': await AppDb.i.rows('receipts', where: 'property_id=?', args: [pid], orderBy: 'generated_at DESC, id DESC'),
    };
  }

  Widget _expenses(int propertyId) => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('expenses-$propertyId-${widget.token}'),
    future: AppDb.i.rows('property_expenses', where: 'property_id=?', args: [propertyId], orderBy: 'event_date DESC, id DESC'),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!;
      final net = rows.fold<int>(0, (s, x) => s + (x['effect_cents'] as int));
      return SnyderCard(accent: SnyderColors.blue, child: Column(children: [
        sectionTitle(Icons.build_outlined, 'Property Expenses', trailing: IconButton(onPressed: () => _expenseDialog(propertyId), icon: const Icon(Icons.add))),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Recorded net expenses', style: TextStyle(color: SnyderColors.muted)), Text(moneyFromCents(net), style: const TextStyle(color: SnyderColors.warning, fontWeight: FontWeight.w900))])),
        const Text('Expenses are bookkeeping records and do NOT change what the tenant owes.', style: TextStyle(color: SnyderColors.muted, fontSize: 11)),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No property expenses recorded.')),
        ...rows.map((x) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon((x['effect_cents'] as int) < 0 ? Icons.undo : Icons.build_circle_outlined, color: (x['effect_cents'] as int) < 0 ? SnyderColors.green : SnyderColors.warning),
          title: Text(x['category'].toString()),
          subtitle: Text('${shortDate(parseDate(x['event_date']))}${x['vendor'].toString().isEmpty ? '' : ' • ${x['vendor']}'}${x['note'].toString().isEmpty ? '' : ' • ${x['note']}'}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(moneyFromCents((x['effect_cents'] as int).abs()), style: const TextStyle(fontWeight: FontWeight.w900)), if ((x['effect_cents'] as int) > 0) PopupMenuButton<String>(onSelected: (v) async { if (v == 'reverse') { await PropertyService.reverseExpense(x); widget.refresh(); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'reverse', child: Text('Post reversal'))])]),
        )),
      ]));
    },
  );

  Widget _journal(int propertyId) => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('journal-$propertyId-${widget.token}'),
    future: AppDb.i.rows('tenant_journal', where: 'property_id=?', args: [propertyId], orderBy: 'created_at DESC, id DESC'),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!;
      return SnyderCard(accent: SnyderColors.violet, child: Column(children: [
        sectionTitle(Icons.menu_book_outlined, 'Tenant Journal & Concerns', trailing: IconButton(onPressed: () => _journalDialog(propertyId), icon: const Icon(Icons.add))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Original notes are preserved. Later updates are appended as follow-ups / resolutions rather than replacing the original.', style: TextStyle(color: SnyderColors.muted, fontSize: 12))),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No journal entries.')),
        ...rows.map((x) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(x['parent_id'] == null ? Icons.auto_stories : Icons.subdirectory_arrow_right, color: x['parent_id'] == null ? SnyderColors.violet : SnyderColors.cyan),
          title: Text(x['category'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${shortDate(parseDate(x['created_at']))} • ${x['note']}'),
          trailing: x['parent_id'] == null ? IconButton(onPressed: () => _journalDialog(propertyId, parentId: x['id'] as int), icon: const Icon(Icons.reply, color: SnyderColors.cyan), tooltip: 'Add follow-up') : null,
        )),
      ]));
    },
  );

  Widget _documents(int propertyId) => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('docs-$propertyId-${widget.token}'),
    future: AppDb.i.rows('documents', where: 'property_id=?', args: [propertyId], orderBy: 'document_date DESC, id DESC'),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!;
      return SnyderCard(accent: SnyderColors.blue, child: Column(children: [
        sectionTitle(Icons.folder_copy_outlined, 'Documents / Notices Vault', trailing: IconButton(onPressed: () => _documentDialog(propertyId), icon: const Icon(Icons.add))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Selected files are copied into the app’s private local storage and recorded with SHA-256 integrity hashes. Superseding a file never deletes its record.', style: TextStyle(color: SnyderColors.muted, fontSize: 12))),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No stored property documents.')),
        ...rows.map((x) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(x['status'] == 'superseded' ? Icons.layers_clear : x['status'] == 'legacy-missing' ? Icons.cloud_off_outlined : Icons.description, color: x['status'] == 'active' ? SnyderColors.cyan : SnyderColors.muted),
          title: Text(x['original_name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${x['category']} • ${shortDate(parseDate(x['document_date']))} • ${x['status']}${x['description'].toString().isEmpty ? '' : '\n${x['description']}'}'),
          isThreeLine: x['description'].toString().isNotEmpty,
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'verify') { final ok = await PropertyService.verifyDocument(x); if (mounted) showMessage(context, ok ? 'SHA-256 verified. File matches its stored record.' : 'Verification failed: file missing or hash mismatch.'); }
              if (v == 'supersede') { await PropertyService.supersedeDocument(x['id'] as int); widget.refresh(); }
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'verify', child: Text('Verify file hash')), if (x['status'] == 'active') const PopupMenuItem(value: 'supersede', child: Text('Mark superseded'))],
          ),
        )),
      ]));
    },
  );

  Widget _audit(int propertyId) => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('audit-$propertyId-${widget.token}'),
    future: AppDb.i.rows('audit_log', where: 'property_id=?', args: [propertyId], orderBy: 'timestamp DESC, id DESC', limit: 100),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!;
      return Column(children: [
        SnyderCard(accent: SnyderColors.green, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.shield_outlined, 'Audit & Data Control', color: SnyderColors.green),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => _runIntegrity(propertyId), icon: const Icon(Icons.verified_user_outlined), label: const Text('Integrity Check')),
            OutlinedButton.icon(onPressed: () => _exportLedgerCsv(propertyId), icon: const Icon(Icons.table_view), label: const Text('Ledger CSV')),
            OutlinedButton.icon(onPressed: () => _exportExpenseCsv(propertyId), icon: const Icon(Icons.table_chart_outlined), label: const Text('Expense CSV')),
          ]),
        ])),
        const SizedBox(height: 12),
        SnyderCard(child: Column(children: [
          sectionTitle(Icons.history, 'Audit Log'),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No audit events yet.')),
          ...rows.map((x) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.fingerprint, color: SnyderColors.violet), title: Text(x['action'].toString()), subtitle: Text('${shortDate(parseDate(x['timestamp']))} • ${x['record_type']} ${x['record_id']}')),
        ])),
      ]);
    },
  );

  Widget _metric(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: SnyderColors.muted, fontSize: 11)), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18))]);

  Future<void> _propertyDialog({Map<String, Object?>? existing}) async {
    final label = TextEditingController(text: existing?['label']?.toString() ?? 'Rental Property');
    final address = TextEditingController(text: existing?['address']?.toString() ?? '');
    final landlord = TextEditingController(text: existing?['landlord_name']?.toString() ?? '');
    final landlordPhone = TextEditingController(text: existing?['landlord_phone']?.toString() ?? '');
    final landlordEmail = TextEditingController(text: existing?['landlord_email']?.toString() ?? '');
    final tenant = TextEditingController(text: existing?['tenant_name']?.toString() ?? '');
    final tenantPhone = TextEditingController(text: existing?['tenant_phone']?.toString() ?? '');
    final tenantEmail = TextEditingController(text: existing?['tenant_email']?.toString() ?? '');
    DateTime? tracking = existing?['tracking_start']?.toString().isNotEmpty == true ? parseDate(existing!['tracking_start']) : DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime? leaseStart = existing?['lease_start']?.toString().isNotEmpty == true ? parseDate(existing!['lease_start']) : null;
    DateTime? leaseEnd = existing?['lease_end']?.toString().isNotEmpty == true ? parseDate(existing!['lease_end']) : null;
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: Text(existing == null ? 'Create property' : 'Property & account profile'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: label, decoration: const InputDecoration(labelText: 'Property label')), const SizedBox(height: 8), TextField(controller: address, decoration: const InputDecoration(labelText: 'Property / address')), const SizedBox(height: 8),
      TextField(controller: landlord, decoration: const InputDecoration(labelText: 'Landlord / manager name')), const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: landlordPhone, decoration: const InputDecoration(labelText: 'Landlord phone'))), const SizedBox(width: 8), Expanded(child: TextField(controller: landlordEmail, decoration: const InputDecoration(labelText: 'Landlord email')))]), const SizedBox(height: 8),
      TextField(controller: tenant, decoration: const InputDecoration(labelText: 'Tenant name')), const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: tenantPhone, decoration: const InputDecoration(labelText: 'Tenant phone'))), const SizedBox(width: 8), Expanded(child: TextField(controller: tenantEmail, decoration: const InputDecoration(labelText: 'Tenant email')))]),
      _dateTile('Ledger tracking start', tracking, (d) => setDialog(() => tracking = d)), _dateTile('Lease start', leaseStart, (d) => setDialog(() => leaseStart = d), allowClear: true), _dateTile('Lease end', leaseEnd, (d) => setDialog(() => leaseEnd = d), allowClear: true),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))])));
    if (ok == true && label.text.trim().isNotEmpty) {
      if (existing == null) {
        final id = await PropertyService.createProperty(label: label.text.trim(), address: address.text.trim(), landlordName: landlord.text.trim(), landlordPhone: landlordPhone.text.trim(), landlordEmail: landlordEmail.text.trim(), tenantName: tenant.text.trim(), tenantPhone: tenantPhone.text.trim(), tenantEmail: tenantEmail.text.trim(), leaseStart: leaseStart, leaseEnd: leaseEnd, trackingStart: tracking);
        setState(() => selectedProperty = id);
      } else {
        await PropertyService.updateProperty(existing['id'] as int, {'label': label.text.trim(), 'address': address.text.trim(), 'landlord_name': landlord.text.trim(), 'landlord_phone': landlordPhone.text.trim(), 'landlord_email': landlordEmail.text.trim(), 'tenant_name': tenant.text.trim(), 'tenant_phone': tenantPhone.text.trim(), 'tenant_email': tenantEmail.text.trim(), 'lease_start': leaseStart == null ? null : isoDate(leaseStart!), 'lease_end': leaseEnd == null ? null : isoDate(leaseEnd!), 'tracking_start': tracking == null ? null : isoDate(tracking!)});
      }
      widget.refresh();
    }
  }

  Widget _dateTile(String label, DateTime? date, void Function(DateTime?) setDate, {bool allowClear = false}) => ListTile(contentPadding: EdgeInsets.zero, title: Text(label), subtitle: Text(date == null ? 'Not set' : shortDate(date)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (allowClear && date != null) IconButton(onPressed: () => setDate(null), icon: const Icon(Icons.clear)), const Icon(Icons.calendar_month)]), onTap: () async { final d = await pickDate(context, date ?? DateTime.now()); if (d != null) setDate(d); });

  Future<void> _rentRuleDialog(int propertyId) async {
    final amount = TextEditingController(); final due = TextEditingController(text: '1'); var effective = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('New rent rule'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('New rules apply prospectively. Already-posted monthly charges are not repriced.', style: TextStyle(color: SnyderColors.muted, fontSize: 12)), const SizedBox(height: 10),
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monthly rent', prefixText: r'$ ')), const SizedBox(height: 8),
      TextField(controller: due, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Due day (1–28)')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Effective date'), subtitle: Text(shortDate(effective)), onTap: () async { final x = await pickDate(context, effective); if (x != null) setDialog(() => effective = x); }),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add Rule'))])));
    if (ok == true) { try { await PropertyService.addRentRule(propertyId, effective, centsFromText(amount.text), int.tryParse(due.text) ?? 1); await PropertyService.postChargesThroughToday(propertyId); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _paymentDialog(int pid) async {
    final amount = TextEditingController(), ref = TextEditingController(), note = TextEditingController(); var method = ''; final other = TextEditingController(); var date = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Record rent payment'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: r'$ ')), const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: method.isEmpty ? null : method, decoration: const InputDecoration(labelText: 'Payment method — required'), items: const [DropdownMenuItem(value: 'Chime', child: Text('Chime')), DropdownMenuItem(value: 'Cash', child: Text('Cash')), DropdownMenuItem(value: 'Other', child: Text('Other'))], onChanged: (v) => setDialog(() => method = v ?? '')),
      if (method == 'Other') ...[const SizedBox(height: 8), TextField(controller: other, decoration: const InputDecoration(labelText: 'Actual method (Money Order, ACH, etc.)'))],
      const SizedBox(height: 8), TextField(controller: ref, decoration: const InputDecoration(labelText: 'Reference')), const SizedBox(height: 8), TextField(controller: note, decoration: const InputDecoration(labelText: 'Payment note (optional)')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Payment date'), subtitle: Text(shortDate(date)), onTap: () async { final x = await pickDate(context, date); if (x != null) setDialog(() => date = x); }),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Post Payment'))])));
    if (ok == true) { try { await PropertyService.recordPayment(propertyId: pid, date: date, amountCents: centsFromText(amount.text), method: method, otherMethod: other.text, reference: ref.text, note: note.text); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _creditDialog(int pid) async {
    final amount = TextEditingController(), desc = TextEditingController(); var date = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Credit / Waiver'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: r'$ ')), const SizedBox(height: 8), TextField(controller: desc, decoration: const InputDecoration(labelText: 'Reason / description')), ListTile(contentPadding: EdgeInsets.zero, title: const Text('Date'), subtitle: Text(shortDate(date)), onTap: () async { final x = await pickDate(context, date); if (x != null) setDialog(() => date = x); })]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Post'))])));
    if (ok == true) { try { await PropertyService.recordCredit(propertyId: pid, date: date, amountCents: centsFromText(amount.text), description: desc.text); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _adjustmentDialog(int pid) async {
    final amount = TextEditingController(), desc = TextEditingController(); var direction = 'increase'; var date = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Ledger adjustment'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(initialValue: direction, decoration: const InputDecoration(labelText: 'Effect on tenant balance'), items: const [DropdownMenuItem(value: 'increase', child: Text('Increase balance')), DropdownMenuItem(value: 'decrease', child: Text('Decrease balance'))], onChanged: (v) => setDialog(() => direction = v ?? 'increase')), const SizedBox(height: 8),
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: r'$ ')), const SizedBox(height: 8), TextField(controller: desc, decoration: const InputDecoration(labelText: 'Reason')), ListTile(contentPadding: EdgeInsets.zero, title: const Text('Date'), subtitle: Text(shortDate(date)), onTap: () async { final x = await pickDate(context, date); if (x != null) setDialog(() => date = x); }),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Post'))])));
    if (ok == true) { final cents = centsFromText(amount.text) * (direction == 'increase' ? 1 : -1); try { await PropertyService.recordAdjustment(propertyId: pid, date: date, effectCents: cents, description: desc.text); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _reverseLedger(Map<String, Object?> row) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Post reversal'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('The original record will remain unchanged. A separate reversing entry will be added.'), const SizedBox(height: 10), TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)'))]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Post Reversal'))]));
    if (ok == true) { try { await PropertyService.reverseLedger(row, reason: reason.text); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _prepareOriginal(int paymentId) async { try { final r = await ReceiptService.prepareOriginal(paymentId); await ReceiptService.saveReceiptPdf(r); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  Future<void> _prepareRevision(int paymentId) async { final reason = TextEditingController(); final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Prepare revised receipt'), content: TextField(controller: reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Revision reason / changed content')), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Prepare'))])); if (ok == true) { try { final r = await ReceiptService.prepareRevision(paymentId, reason.text); await ReceiptService.saveReceiptPdf(r); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } } }

  Future<void> _expenseDialog(int pid) async {
    final amount = TextEditingController(), category = TextEditingController(text: 'Maintenance'), vendor = TextEditingController(), note = TextEditingController(); var date = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Property expense'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: r'$ ')), const SizedBox(height: 8), TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8), TextField(controller: vendor, decoration: const InputDecoration(labelText: 'Payee / vendor')), const SizedBox(height: 8), TextField(controller: note, decoration: const InputDecoration(labelText: 'Business-purpose note')), ListTile(contentPadding: EdgeInsets.zero, title: const Text('Date'), subtitle: Text(shortDate(date)), onTap: () async { final x = await pickDate(context, date); if (x != null) setDialog(() => date = x); })])), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))])));
    if (ok == true) { try { await PropertyService.recordExpense(propertyId: pid, date: date, amountCents: centsFromText(amount.text), category: category.text, vendor: vendor.text, note: note.text); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _journalDialog(int pid, {int? parentId}) async {
    final category = TextEditingController(text: parentId == null ? 'General' : 'Follow-up / Resolution'), note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(parentId == null ? 'Tenant journal entry' : 'Append follow-up'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8), TextField(controller: note, maxLines: 5, decoration: const InputDecoration(labelText: 'Note'))]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Append'))]));
    if (ok == true) { try { await PropertyService.addJournal(propertyId: pid, category: category.text, note: note.text, parentId: parentId); widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _documentDialog(int pid) async {
    final category = TextEditingController(text: 'Notice'), description = TextEditingController(); var date = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Store property document'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8), TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')), ListTile(contentPadding: EdgeInsets.zero, title: const Text('Document date'), subtitle: Text(shortDate(date)), onTap: () async { final x = await pickDate(context, date); if (x != null) setDialog(() => date = x); }), const Text('After Save, Android will ask you to pick the local file to copy into Snyder Family private storage.', style: TextStyle(color: SnyderColors.muted, fontSize: 11))]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Choose File'))])));
    if (ok == true) { try { final id = await PropertyService.pickAndStoreDocument(propertyId: pid, category: category.text, description: description.text, date: date); if (id != null) widget.refresh(); } catch (e) { if (mounted) showError(context, e); } }
  }

  Future<void> _runIntegrity(int pid) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final r = await PropertyService.integrityCheck(pid);
    if (!mounted) return; Navigator.pop(context);
    await showDialog<void>(context: context, builder: (d) => AlertDialog(title: Row(children: [Icon(r.ok ? Icons.verified : Icons.warning_amber_rounded, color: r.ok ? SnyderColors.green : SnyderColors.warning), const SizedBox(width: 8), Text(r.ok ? 'Integrity Passed' : 'Review Needed')]), content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: r.messages.map((m) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('• $m'))).toList())), actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Done'))]));
    widget.refresh();
  }

  Future<void> _exportLedgerCsv(int pid) async {
    final rows = await PropertyService.ledger(pid); final b = StringBuffer('date,kind,description,amount,effect,method,reference\n');
    for (final x in rows) b.writeln([x['event_date'], x['kind'], _csv(x['description']), (x['amount_cents'] as int) / 100, (x['effect_cents'] as int) / 100, _csv(x['method'] == 'Other' ? x['other_method'] : x['method']), _csv(x['reference'])].join(','));
    await LocalFiles.saveBytes(fileName: 'Snyder_Property_Ledger_${DateTime.now().year}.csv', mime: 'text/csv', bytes: Uint8List.fromList(utf8.encode(b.toString())));
  }
  Future<void> _exportExpenseCsv(int pid) async {
    final rows = await AppDb.i.rows('property_expenses', where: 'property_id=?', args: [pid], orderBy: 'event_date ASC,id ASC'); final b = StringBuffer('date,category,vendor,note,amount,effect\n');
    for (final x in rows) b.writeln([x['event_date'], _csv(x['category']), _csv(x['vendor']), _csv(x['note']), (x['amount_cents'] as int) / 100, (x['effect_cents'] as int) / 100].join(','));
    await LocalFiles.saveBytes(fileName: 'Snyder_Property_Expenses_${DateTime.now().year}.csv', mime: 'text/csv', bytes: Uint8List.fromList(utf8.encode(b.toString())));
  }
  String _csv(Object? v) => '"${v?.toString().replaceAll('"', '""') ?? ''}"';
}