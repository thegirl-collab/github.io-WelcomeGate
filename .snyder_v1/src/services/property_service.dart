import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../db.dart';
import '../widgets/common.dart';
import 'local_files.dart';

class IntegrityResult {
  IntegrityResult(this.ok, this.messages);
  final bool ok;
  final List<String> messages;
}

class PropertyService {
  static Future<List<Map<String, Object?>>> properties() => AppDb.i.rows('properties', where: 'active=1', orderBy: 'id ASC');

  static Future<int> createProperty({
    required String label,
    String address = '',
    String landlordName = '',
    String landlordPhone = '',
    String landlordEmail = '',
    String tenantName = '',
    String tenantPhone = '',
    String tenantEmail = '',
    DateTime? leaseStart,
    DateTime? leaseEnd,
    DateTime? trackingStart,
  }) async {
    final id = await AppDb.i.insert('properties', {
      'label': label,
      'address': address,
      'landlord_name': landlordName,
      'landlord_phone': landlordPhone,
      'landlord_email': landlordEmail,
      'tenant_name': tenantName,
      'tenant_phone': tenantPhone,
      'tenant_email': tenantEmail,
      'lease_start': leaseStart == null ? null : isoDate(leaseStart),
      'lease_end': leaseEnd == null ? null : isoDate(leaseEnd),
      'tracking_start': trackingStart == null ? null : isoDate(trackingStart),
      'legacy_source_hash': null,
      'active': 1,
      'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: id, action: 'property_created', recordType: 'property', recordId: '$id');
    return id;
  }

  static Future<void> updateProperty(int id, Map<String, Object?> values) async {
    await AppDb.i.update('properties', values, id);
    await AppDb.i.audit(propertyId: id, action: 'property_profile_updated', recordType: 'property', recordId: '$id');
  }

  static Future<int> addRentRule(int propertyId, DateTime effective, int amountCents, int dueDay) async {
    if (dueDay < 1 || dueDay > 28) throw ArgumentError('Due day must be 1–28.');
    final id = await AppDb.i.insert('rent_rules', {
      'property_id': propertyId,
      'effective_date': isoDate(effective),
      'amount_cents': amountCents,
      'due_day': dueDay,
      'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: propertyId, action: 'rent_rule_added', recordType: 'rent_rule', recordId: '$id', details: {
      'effective_date': isoDate(effective), 'amount_cents': amountCents, 'due_day': dueDay
    });
    return id;
  }

  static Future<Map<String, Object?>?> ruleForDate(int propertyId, DateTime date) async {
    final rows = await AppDb.i.rows('rent_rules', where: 'property_id=? AND effective_date<=?', args: [propertyId, isoDate(date)], orderBy: 'effective_date DESC, id DESC', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static DateTime _safeDue(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, math.min(day, last));
  }

  static Future<int> postChargesThroughToday(int propertyId) async {
    final prop = await AppDb.i.one('properties', propertyId);
    if (prop == null) return 0;
    final trackingRaw = prop['tracking_start']?.toString() ?? '';
    if (trackingRaw.isEmpty) return 0;
    final tracking = parseDate(trackingRaw);
    final today = DateTime.now();
    var month = DateTime(tracking.year, tracking.month, 1);
    final endMonth = DateTime(today.year, today.month, 1);
    var count = 0;
    while (!month.isAfter(endMonth)) {
      final rule = await ruleForDate(propertyId, month);
      if (rule != null) {
        final due = _safeDue(month.year, month.month, rule['due_day'] as int);
        if (!due.isAfter(today) && !due.isBefore(tracking)) {
          final period = '${due.year.toString().padLeft(4, '0')}-${due.month.toString().padLeft(2, '0')}';
          final existing = await AppDb.i.rows('property_ledger', where: 'property_id=? AND kind=? AND period=?', args: [propertyId, 'charge', period], limit: 1);
          if (existing.isEmpty) {
            final amount = rule['amount_cents'] as int;
            final id = await AppDb.i.insert('property_ledger', {
              'property_id': propertyId,
              'kind': 'charge',
              'event_date': isoDate(due),
              'period': period,
              'amount_cents': amount,
              'effect_cents': amount,
              'description': 'Rent due for ${DateTime(due.year, due.month).monthName} ${due.year}',
              'method': '', 'other_method': '', 'reference': '', 'reverses_id': null, 'legacy_id': null,
              'created_at': AppDb.i.now(),
            });
            await AppDb.i.audit(propertyId: propertyId, action: 'rent_charge_posted', recordType: 'ledger', recordId: '$id', details: {'period': period, 'amount_cents': amount});
            count++;
          }
        }
      }
      month = DateTime(month.year, month.month + 1, 1);
    }
    return count;
  }

  static Future<int> recordPayment({required int propertyId, required DateTime date, required int amountCents, required String method, String otherMethod = '', String reference = '', String note = ''}) async {
    if (amountCents <= 0) throw ArgumentError('Payment must be greater than zero.');
    if (!['Chime', 'Cash', 'Other'].contains(method)) throw ArgumentError('Choose Chime, Cash, or Other.');
    if (method == 'Other' && otherMethod.trim().isEmpty) throw ArgumentError('Enter the actual payment method.');
    final actualMethod = method == 'Other' ? otherMethod.trim() : method;
    final id = await AppDb.i.insert('property_ledger', {
      'property_id': propertyId,
      'kind': 'payment',
      'event_date': isoDate(date),
      'period': null,
      'amount_cents': amountCents,
      'effect_cents': -amountCents,
      'description': note.trim().isEmpty ? 'Rental payment received ($actualMethod)' : note.trim(),
      'method': method,
      'other_method': otherMethod.trim(),
      'reference': reference.trim(),
      'reverses_id': null,
      'legacy_id': null,
      'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: propertyId, action: 'payment_posted', recordType: 'ledger', recordId: '$id', details: {'amount_cents': amountCents, 'method': actualMethod, 'date': isoDate(date)});
    return id;
  }

  static Future<int> recordCredit({required int propertyId, required DateTime date, required int amountCents, required String description}) async {
    if (amountCents <= 0) throw ArgumentError('Credit must be greater than zero.');
    final id = await AppDb.i.insert('property_ledger', {
      'property_id': propertyId, 'kind': 'credit', 'event_date': isoDate(date), 'period': null,
      'amount_cents': amountCents, 'effect_cents': -amountCents, 'description': description.trim().isEmpty ? 'Credit / waiver' : description.trim(),
      'method': '', 'other_method': '', 'reference': '', 'reverses_id': null, 'legacy_id': null, 'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: propertyId, action: 'credit_posted', recordType: 'ledger', recordId: '$id', details: {'amount_cents': amountCents});
    return id;
  }

  static Future<int> recordAdjustment({required int propertyId, required DateTime date, required int effectCents, required String description}) async {
    if (effectCents == 0) throw ArgumentError('Adjustment cannot be zero.');
    final id = await AppDb.i.insert('property_ledger', {
      'property_id': propertyId, 'kind': 'adjustment', 'event_date': isoDate(date), 'period': null,
      'amount_cents': effectCents.abs(), 'effect_cents': effectCents, 'description': description.trim().isEmpty ? 'Ledger adjustment' : description.trim(),
      'method': '', 'other_method': '', 'reference': '', 'reverses_id': null, 'legacy_id': null, 'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: propertyId, action: 'adjustment_posted', recordType: 'ledger', recordId: '$id', details: {'effect_cents': effectCents});
    return id;
  }

  static Future<int> reverseLedger(Map<String, Object?> original, {String reason = ''}) async {
    final id = original['id'] as int;
    final existing = await AppDb.i.rows('property_ledger', where: 'reverses_id=?', args: [id], limit: 1);
    if (existing.isNotEmpty) throw StateError('This ledger entry already has a reversal.');
    final propertyId = original['property_id'] as int;
    final effect = original['effect_cents'] as int;
    final reversalId = await AppDb.i.insert('property_ledger', {
      'property_id': propertyId, 'kind': 'reversal', 'event_date': isoDate(DateTime.now()), 'period': null,
      'amount_cents': effect.abs(), 'effect_cents': -effect,
      'description': 'Reversal of #$id${reason.trim().isEmpty ? '' : ': ${reason.trim()}'}',
      'method': original['method'] ?? '', 'other_method': original['other_method'] ?? '', 'reference': original['reference'] ?? '',
      'reverses_id': id, 'legacy_id': null, 'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: propertyId, action: 'ledger_entry_reversed', recordType: 'ledger', recordId: '$reversalId', details: {'reverses_id': id, 'reason': reason});
    return reversalId;
  }

  static Future<List<Map<String, Object?>>> ledger(int propertyId) => AppDb.i.rows('property_ledger', where: 'property_id=?', args: [propertyId], orderBy: 'event_date ASC, id ASC');

  static Future<int> balance(int propertyId, {DateTime? through}) async {
    final entries = await ledger(propertyId);
    var total = 0;
    for (final e in entries) {
      if (through != null && parseDate(e['event_date']).isAfter(through)) continue;
      total += e['effect_cents'] as int;
    }
    return total;
  }

  static Future<int> balanceAfterLedgerId(int propertyId, int ledgerId) async {
    final entries = await ledger(propertyId);
    var total = 0;
    for (final e in entries) {
      total += e['effect_cents'] as int;
      if (e['id'] == ledgerId) return total;
    }
    return total;
  }

  static Future<int> recordExpense({required int propertyId, required DateTime date, required int amountCents, required String category, String vendor = '', String note = ''}) async {
    if (amountCents <= 0) throw ArgumentError('Expense must be greater than zero.');
    final id = await AppDb.i.insert('property_expenses', {
      'property_id': propertyId, 'event_date': isoDate(date), 'amount_cents': amountCents, 'effect_cents': amountCents,
      'category': category.trim().isEmpty ? 'Other' : category.trim(), 'vendor': vendor.trim(), 'note': note.trim(),
      'reverses_id': null, 'legacy_id': null, 'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: propertyId, action: 'property_expense_posted', recordType: 'expense', recordId: '$id', details: {'amount_cents': amountCents, 'category': category});
    return id;
  }

  static Future<int> reverseExpense(Map<String, Object?> original, {String reason = ''}) async {
    final id = original['id'] as int;
    final existing = await AppDb.i.rows('property_expenses', where: 'reverses_id=?', args: [id], limit: 1);
    if (existing.isNotEmpty) throw StateError('This expense already has a reversal.');
    final pid = original['property_id'] as int;
    final effect = original['effect_cents'] as int;
    final rid = await AppDb.i.insert('property_expenses', {
      'property_id': pid, 'event_date': isoDate(DateTime.now()), 'amount_cents': effect.abs(), 'effect_cents': -effect,
      'category': 'Reversal', 'vendor': original['vendor'] ?? '', 'note': 'Reversal of expense #$id${reason.trim().isEmpty ? '' : ': ${reason.trim()}'}',
      'reverses_id': id, 'legacy_id': null, 'created_at': AppDb.i.now(),
    });
    await AppDb.i.audit(propertyId: pid, action: 'property_expense_reversed', recordType: 'expense', recordId: '$rid', details: {'reverses_id': id});
    return rid;
  }

  static Future<int> netExpenses(int propertyId, {int? year}) async {
    final xs = await AppDb.i.rows('property_expenses', where: 'property_id=?', args: [propertyId]);
    var total = 0;
    for (final x in xs) {
      if (year != null && parseDate(x['event_date']).year != year) continue;
      total += x['effect_cents'] as int;
    }
    return total;
  }

  static Future<int> rentCashFlow(int propertyId, {int? year}) async {
    final xs = await ledger(propertyId);
    var received = 0;
    for (final x in xs) {
      if (year != null && parseDate(x['event_date']).year != year) continue;
      if (x['kind'] == 'payment') received += x['amount_cents'] as int;
      if (x['kind'] == 'reversal') {
        final originalId = x['reverses_id'] as int?;
        if (originalId != null) {
          final o = await AppDb.i.one('property_ledger', originalId);
          if (o != null && o['kind'] == 'payment') received -= o['amount_cents'] as int;
        }
      }
    }
    return received - await netExpenses(propertyId, year: year);
  }

  static Future<int> addJournal({required int propertyId, required String category, required String note, int? parentId}) async {
    if (note.trim().isEmpty) throw ArgumentError('Journal note cannot be empty.');
    final id = await AppDb.i.insert('tenant_journal', {
      'property_id': propertyId, 'created_at': AppDb.i.now(), 'category': category.trim().isEmpty ? 'General' : category.trim(),
      'note': note.trim(), 'parent_id': parentId, 'legacy_id': null,
    });
    await AppDb.i.audit(propertyId: propertyId, action: parentId == null ? 'journal_entry_added' : 'journal_followup_added', recordType: 'journal', recordId: '$id', details: {'parent_id': parentId});
    return id;
  }

  static String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static Future<int?> pickAndStoreDocument({required int propertyId, required String category, required String description, DateTime? date}) async {
    final picked = await LocalFiles.pickFile();
    if (picked == null) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/property_documents');
    await dir.create(recursive: true);
    final hash = sha256.convert(picked.bytes).toString();
    final tempId = await AppDb.i.insert('documents', {
      'property_id': propertyId, 'document_date': isoDate(date ?? DateTime.now()), 'category': category.trim().isEmpty ? 'Other' : category.trim(),
      'description': description.trim(), 'original_name': picked.name, 'stored_path': '', 'sha256': hash, 'status': 'active', 'legacy_id': null, 'created_at': AppDb.i.now(),
    });
    final path = '${dir.path}/${tempId}_${_safeName(picked.name)}';
    await File(path).writeAsBytes(picked.bytes, flush: true);
    await AppDb.i.update('documents', {'stored_path': path}, tempId);
    await AppDb.i.audit(propertyId: propertyId, action: 'document_stored', recordType: 'document', recordId: '$tempId', details: {'file_name': picked.name, 'sha256': hash});
    return tempId;
  }

  static Future<bool> verifyDocument(Map<String, Object?> row) async {
    final path = row['stored_path']?.toString() ?? '';
    if (path.isEmpty) return false;
    final f = File(path);
    if (!await f.exists()) return false;
    return sha256.convert(await f.readAsBytes()).toString() == row['sha256']?.toString();
  }

  static Future<void> supersedeDocument(int id) async {
    final row = await AppDb.i.one('documents', id);
    if (row == null) return;
    await AppDb.i.update('documents', {'status': 'superseded'}, id);
    await AppDb.i.audit(propertyId: row['property_id'] as int, action: 'document_superseded', recordType: 'document', recordId: '$id');
  }

  static Future<IntegrityResult> integrityCheck(int propertyId) async {
    final messages = <String>[];
    final ledgerRows = await ledger(propertyId);
    final ids = ledgerRows.map((e) => e['id'] as int).toSet();
    final reversed = <int>{};
    final periods = <String>{};
    for (final e in ledgerRows) {
      if (e['kind'] == 'charge') {
        final period = e['period']?.toString() ?? '';
        if (period.isNotEmpty && !periods.add(period)) messages.add('Duplicate rent charge period: $period');
      }
      final r = e['reverses_id'] as int?;
      if (r != null) {
        if (!ids.contains(r)) messages.add('Reversal #${e['id']} references missing ledger #$r.');
        if (!reversed.add(r)) messages.add('Ledger #$r has more than one reversal.');
      }
    }
    final receipts = await AppDb.i.rows('receipts', where: 'property_id=?', args: [propertyId]);
    for (final r in receipts) {
      final expected = sha256.convert(utf8.encode(r['snapshot_json'] as String)).toString();
      if (expected != r['snapshot_hash']) messages.add('Receipt ${r['receipt_number']} revision ${r['revision']} snapshot hash mismatch.');
      if (!ids.contains(r['payment_ledger_id'])) messages.add('Receipt ${r['receipt_number']} points to missing payment ledger entry.');
    }
    final docs = await AppDb.i.rows('documents', where: 'property_id=?', args: [propertyId]);
    for (final d in docs) {
      if (d['status'] == 'legacy-missing') continue;
      if (!await verifyDocument(d)) messages.add('Document ${d['original_name']} is missing or has a hash mismatch.');
    }
    if (messages.isEmpty) messages.add('Ledger, receipt snapshots, reversals, and stored document hashes passed integrity checks.');
    await AppDb.i.audit(propertyId: propertyId, action: 'integrity_check_run', details: {'ok': messages.length == 1 && messages.first.startsWith('Ledger,'), 'messages': messages});
    return IntegrityResult(messages.length == 1 && messages.first.startsWith('Ledger,'), messages);
  }

  static Future<int> importLegacyV7Bytes(List<int> bytes) async {
    final sourceHash = sha256.convert(bytes).toString();
    final existing = await AppDb.i.rows('properties', where: 'legacy_source_hash=?', args: [sourceHash], limit: 1);
    if (existing.isNotEmpty) throw StateError('This exact landlord data file has already been imported.');
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) throw const FormatException('Legacy landlord JSON root is invalid.');
    final propertyId = await createProperty(
      label: data['property_label']?.toString().trim().isNotEmpty == true ? data['property_label'].toString() : 'Imported Rental Property',
      address: data['property_label']?.toString() ?? '',
      landlordName: data['landlord_name']?.toString() ?? '',
      landlordPhone: data['landlord_phone']?.toString() ?? '',
      landlordEmail: data['landlord_email']?.toString() ?? '',
      tenantName: data['tenant_name']?.toString() ?? '',
      tenantPhone: data['tenant_phone']?.toString() ?? '',
      tenantEmail: data['tenant_email']?.toString() ?? '',
      leaseStart: _dateOrNull(data['lease_start_date']),
      leaseEnd: _dateOrNull(data['lease_end_date']),
      trackingStart: _dateOrNull(data['tracking_start_date']),
    );
    await AppDb.i.update('properties', {'legacy_source_hash': sourceHash}, propertyId);

    for (final raw in (data['rent_rules'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      final date = _dateOrNull(r['effective_date']);
      if (date == null) continue;
      await AppDb.i.insert('rent_rules', {
        'property_id': propertyId, 'effective_date': isoDate(date), 'amount_cents': _int(r['amount_cents']),
        'due_day': math.max(1, math.min(28, _int(r['due_day'], 1))), 'created_at': r['created_at']?.toString() ?? AppDb.i.now(),
      });
    }

    final legacyToNewLedger = <String, int>{};
    Future<void> importLedgerList(String key, String kind, int sign) async {
      for (final raw in (data[key] as List? ?? const [])) {
        final r = Map<String, dynamic>.from(raw as Map);
        final dateRaw = r['date'] ?? r['payment_date'] ?? r['due_date'] ?? r['created_at'];
        final date = _dateOrNull(dateRaw) ?? DateTime.now();
        final amount = _int(r['amount_cents']);
        final legacyId = r['id']?.toString();
        final method = r['method']?.toString() ?? r['payment_method']?.toString() ?? '';
        final other = r['other_method']?.toString() ?? '';
        final desc = r['description']?.toString() ?? (kind == 'charge' ? 'Imported rent charge' : kind == 'payment' ? 'Imported rental payment' : 'Imported $kind');
        final id = await AppDb.i.insert('property_ledger', {
          'property_id': propertyId, 'kind': kind, 'event_date': isoDate(date),
          'period': kind == 'charge' ? (r['period']?.toString() ?? isoDate(date).substring(0, 7)) : null,
          'amount_cents': amount.abs(), 'effect_cents': amount.abs() * sign, 'description': desc,
          'method': method, 'other_method': other, 'reference': r['reference']?.toString() ?? '',
          'reverses_id': null, 'legacy_id': legacyId, 'created_at': r['created_at']?.toString() ?? AppDb.i.now(),
        });
        if (legacyId != null && legacyId.isNotEmpty) legacyToNewLedger[legacyId] = id;
      }
    }
    await importLedgerList('charges', 'charge', 1);
    await importLedgerList('payments', 'payment', -1);
    await importLedgerList('credits', 'credit', -1);
    for (final raw in (data['adjustments'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      final amount = _int(r['amount_cents']);
      final effect = _int(r['effect_cents'], amount);
      final legacyId = r['id']?.toString();
      final id = await AppDb.i.insert('property_ledger', {
        'property_id': propertyId, 'kind': r['kind']?.toString() == 'reversal' ? 'reversal' : 'adjustment',
        'event_date': isoDate(_dateOrNull(r['date'] ?? r['created_at']) ?? DateTime.now()), 'period': null,
        'amount_cents': amount.abs(), 'effect_cents': effect, 'description': r['description']?.toString() ?? 'Imported adjustment',
        'method': '', 'other_method': '', 'reference': '', 'reverses_id': null, 'legacy_id': legacyId, 'created_at': r['created_at']?.toString() ?? AppDb.i.now(),
      });
      if (legacyId != null && legacyId.isNotEmpty) legacyToNewLedger[legacyId] = id;
    }

    for (final raw in (data['receipts'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      final paymentLegacy = r['payment_id']?.toString() ?? r['snapshot']?['payment_id']?.toString();
      final paymentId = paymentLegacy == null ? null : legacyToNewLedger[paymentLegacy];
      if (paymentId == null) continue;
      final snap = r['snapshot'] is Map ? Map<String, dynamic>.from(r['snapshot'] as Map) : <String, dynamic>{'legacy_receipt': r};
      final snapJson = jsonEncode(snap);
      await AppDb.i.insert('receipts', {
        'property_id': propertyId, 'payment_ledger_id': paymentId,
        'receipt_number': r['receipt_number']?.toString() ?? 'LEGACY-${r['id'] ?? paymentId}',
        'revision': _int(r['revision'], 1), 'document_type': r['document_type']?.toString() ?? 'original',
        'status': r['status']?.toString() ?? 'prepared', 'snapshot_json': snapJson,
        'snapshot_hash': r['snapshot_hash']?.toString().isNotEmpty == true ? r['snapshot_hash'].toString() : sha256.convert(utf8.encode(snapJson)).toString(),
        'generated_at': r['generated_at']?.toString() ?? r['last_exported_at']?.toString() ?? AppDb.i.now(),
        'issued_at': (r['issued_at']?.toString().isEmpty ?? true) ? null : r['issued_at'].toString(),
        'revision_reason': (r['change_summary'] is List) ? (r['change_summary'] as List).join('; ') : '',
        'legacy_id': r['id']?.toString(),
      });
    }

    for (final raw in (data['expenses'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      final amount = _int(r['amount_cents']);
      await AppDb.i.insert('property_expenses', {
        'property_id': propertyId, 'event_date': isoDate(_dateOrNull(r['date']) ?? DateTime.now()), 'amount_cents': amount.abs(),
        'effect_cents': _int(r['effect_cents'], amount), 'category': r['category']?.toString() ?? 'Imported',
        'vendor': r['payee']?.toString() ?? r['vendor']?.toString() ?? '', 'note': r['note']?.toString() ?? r['business_purpose']?.toString() ?? '',
        'reverses_id': null, 'legacy_id': r['id']?.toString(), 'created_at': r['created_at']?.toString() ?? AppDb.i.now(),
      });
    }
    for (final raw in (data['tenant_journal'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      await AppDb.i.insert('tenant_journal', {
        'property_id': propertyId, 'created_at': r['created_at']?.toString() ?? AppDb.i.now(), 'category': r['category']?.toString() ?? 'Imported',
        'note': r['note']?.toString() ?? r['text']?.toString() ?? '', 'parent_id': null, 'legacy_id': r['id']?.toString(),
      });
    }
    for (final raw in (data['documents'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      await AppDb.i.insert('documents', {
        'property_id': propertyId, 'document_date': isoDate(_dateOrNull(r['document_date'] ?? r['date']) ?? DateTime.now()),
        'category': r['category']?.toString() ?? 'Imported', 'description': r['description']?.toString() ?? '',
        'original_name': r['original_filename']?.toString() ?? r['file_name']?.toString() ?? 'legacy_document',
        'stored_path': '', 'sha256': r['sha256']?.toString() ?? r['file_hash']?.toString() ?? '', 'status': 'legacy-missing',
        'legacy_id': r['id']?.toString(), 'created_at': r['created_at']?.toString() ?? AppDb.i.now(),
      });
    }
    for (final raw in (data['audit_log'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      await AppDb.i.insert('audit_log', {
        'property_id': propertyId, 'timestamp': r['timestamp']?.toString() ?? AppDb.i.now(), 'action': 'legacy:${r['action'] ?? 'event'}',
        'record_type': r['record_type']?.toString() ?? '', 'record_id': r['record_id']?.toString() ?? '',
        'details_json': jsonEncode(r['details'] ?? const {}),
      });
    }
    await AppDb.i.audit(propertyId: propertyId, action: 'legacy_v7_import_completed', recordType: 'property', recordId: '$propertyId', details: {'source_sha256': sourceHash});
    return propertyId;
  }

  static DateTime? _dateOrNull(Object? value) {
    final s = value?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static int _int(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

extension MonthName on DateTime {
  String get monthName => const ['January','February','March','April','May','June','July','August','September','October','November','December'][month - 1];
}