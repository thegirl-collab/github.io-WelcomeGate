import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../db.dart';
import '../widgets/common.dart';
import 'local_files.dart';
import 'property_service.dart';

class ReceiptService {
  static Future<Map<String, dynamic>> snapshotForPayment(int paymentLedgerId) async {
    final payment = await AppDb.i.one('property_ledger', paymentLedgerId);
    if (payment == null || payment['kind'] != 'payment') throw StateError('Payment record not found.');
    final propertyId = payment['property_id'] as int;
    final property = await AppDb.i.one('properties', propertyId);
    if (property == null) throw StateError('Property profile not found.');
    final entries = await PropertyService.ledger(propertyId);
    final throughDate = parseDate(payment['event_date']);
    var charge = 0, paid = 0, credits = 0, adjustments = 0, balance = 0;
    final mini = <Map<String, dynamic>>[];
    for (final e in entries) {
      final eventDate = parseDate(e['event_date']);
      if (eventDate.isAfter(throughDate)) continue;
      final effect = e['effect_cents'] as int;
      balance += effect;
      switch (e['kind']) {
        case 'charge': charge += e['amount_cents'] as int; break;
        case 'payment': paid += e['amount_cents'] as int; break;
        case 'credit': credits += e['amount_cents'] as int; break;
        case 'adjustment': adjustments += effect; break;
        case 'reversal':
          final rid = e['reverses_id'] as int?;
          if (rid != null) {
            final o = await AppDb.i.one('property_ledger', rid);
            if (o != null) {
              if (o['kind'] == 'payment') paid -= o['amount_cents'] as int;
              if (o['kind'] == 'credit') credits -= o['amount_cents'] as int;
              if (o['kind'] == 'charge') charge -= o['amount_cents'] as int;
              if (o['kind'] == 'adjustment') adjustments -= o['effect_cents'] as int;
            }
          }
          break;
      }
      mini.add({
        'date': e['event_date'], 'kind': e['kind'], 'description': e['description'],
        'amount_cents': e['amount_cents'], 'effect_cents': effect, 'balance_cents': balance,
      });
      if (e['id'] == paymentLedgerId) break;
    }
    final actualMethod = payment['method'] == 'Other' ? payment['other_method'] : payment['method'];
    return {
      'property_id': propertyId,
      'payment_id': paymentLedgerId,
      'landlord_name': property['landlord_name'], 'landlord_phone': property['landlord_phone'], 'landlord_email': property['landlord_email'],
      'tenant_name': property['tenant_name'], 'tenant_phone': property['tenant_phone'], 'tenant_email': property['tenant_email'],
      'property_label': property['label'], 'property_address': property['address'],
      'payment_date': payment['event_date'], 'payment_amount_cents': payment['amount_cents'], 'payment_method': actualMethod,
      'payment_reference': payment['reference'], 'payment_note': payment['description'], 'balance_after_cents': balance,
      'summary': {'charges_cents': charge, 'payments_cents': paid, 'credits_cents': credits, 'adjustments_cents': adjustments, 'balance_cents': balance},
      'mini_ledger': mini,
      'captured_at': AppDb.i.now(),
    };
  }

  static Future<String> _nextNumber(DateTime date) async {
    final prefix = 'R-${date.year}-';
    final rows = await AppDb.i.rows('receipts', where: 'receipt_number LIKE ?', args: ['$prefix%']);
    var max = 0;
    for (final r in rows) {
      final s = r['receipt_number']?.toString() ?? '';
      final last = int.tryParse(s.split('-').last) ?? 0;
      if (last > max) max = last;
    }
    return '$prefix${(max + 1).toString().padLeft(4, '0')}';
  }

  static Future<Map<String, Object?>> prepareOriginal(int paymentId) async {
    final payment = await AppDb.i.one('property_ledger', paymentId);
    if (payment == null) throw StateError('Payment not found.');
    final existing = await AppDb.i.rows('receipts', where: 'payment_ledger_id=? AND revision=1', args: [paymentId], orderBy: 'id DESC', limit: 1);
    final snap = await snapshotForPayment(paymentId);
    final json = jsonEncode(snap);
    final hash = sha256.convert(utf8.encode(json)).toString();
    if (existing.isNotEmpty && existing.first['status'] != 'issued') {
      final id = existing.first['id'] as int;
      await AppDb.i.update('receipts', {'snapshot_json': json, 'snapshot_hash': hash, 'generated_at': AppDb.i.now(), 'document_type': 'original', 'revision_reason': ''}, id);
      await AppDb.i.audit(propertyId: payment['property_id'] as int, action: 'receipt_prepared_refreshed', recordType: 'receipt', recordId: '$id');
      return (await AppDb.i.one('receipts', id))!;
    }
    if (existing.isNotEmpty && existing.first['status'] == 'issued') {
      throw StateError('The original receipt was already marked issued. Create a revised receipt instead.');
    }
    final number = await _nextNumber(parseDate(payment['event_date']));
    final id = await AppDb.i.insert('receipts', {
      'property_id': payment['property_id'], 'payment_ledger_id': paymentId, 'receipt_number': number,
      'revision': 1, 'document_type': 'original', 'status': 'prepared', 'snapshot_json': json, 'snapshot_hash': hash,
      'generated_at': AppDb.i.now(), 'issued_at': null, 'revision_reason': '', 'legacy_id': null,
    });
    await AppDb.i.audit(propertyId: payment['property_id'] as int, action: 'receipt_prepared', recordType: 'receipt', recordId: '$id', details: {'receipt_number': number, 'revision': 1});
    return (await AppDb.i.one('receipts', id))!;
  }

  static Future<Map<String, Object?>> prepareRevision(int paymentId, String reason) async {
    final payment = await AppDb.i.one('property_ledger', paymentId);
    if (payment == null) throw StateError('Payment not found.');
    final issued = await AppDb.i.rows('receipts', where: 'payment_ledger_id=? AND status=?', args: [paymentId, 'issued'], orderBy: 'revision DESC', limit: 1);
    if (issued.isEmpty) throw StateError('A revised receipt is only appropriate after a prior receipt was explicitly marked issued / delivered.');
    final all = await AppDb.i.rows('receipts', where: 'payment_ledger_id=?', args: [paymentId], orderBy: 'revision DESC');
    final nextRevision = (all.first['revision'] as int) + 1;
    final number = issued.first['receipt_number'].toString();
    final snap = await snapshotForPayment(paymentId);
    final json = jsonEncode(snap);
    final hash = sha256.convert(utf8.encode(json)).toString();
    final id = await AppDb.i.insert('receipts', {
      'property_id': payment['property_id'], 'payment_ledger_id': paymentId, 'receipt_number': number,
      'revision': nextRevision, 'document_type': 'revised', 'status': 'prepared', 'snapshot_json': json, 'snapshot_hash': hash,
      'generated_at': AppDb.i.now(), 'issued_at': null, 'revision_reason': reason.trim(), 'legacy_id': null,
    });
    await AppDb.i.audit(propertyId: payment['property_id'] as int, action: 'revised_receipt_prepared', recordType: 'receipt', recordId: '$id', details: {'receipt_number': number, 'revision': nextRevision, 'reason': reason});
    return (await AppDb.i.one('receipts', id))!;
  }

  static Future<void> markIssued(int receiptId, {String note = ''}) async {
    final r = await AppDb.i.one('receipts', receiptId);
    if (r == null) return;
    if (r['status'] == 'issued') return;
    await AppDb.i.update('receipts', {'status': 'issued', 'issued_at': AppDb.i.now()}, receiptId);
    await AppDb.i.audit(propertyId: r['property_id'] as int, action: 'receipt_marked_issued', recordType: 'receipt', recordId: '$receiptId', details: {'receipt_number': r['receipt_number'], 'revision': r['revision'], 'delivery_note': note});
  }

  static Future<Uint8List> draftPdfForPayment(int paymentId) async {
    final snap = await snapshotForPayment(paymentId);
    return _buildPdf(snapshot: snap, draft: true, receiptNumber: 'DRAFT', revision: 0, documentType: 'draft', reason: '');
  }

  static Future<Uint8List> pdfForReceipt(Map<String, Object?> receipt) async {
    final snap = Map<String, dynamic>.from(jsonDecode(receipt['snapshot_json'] as String) as Map);
    return _buildPdf(snapshot: snap, draft: false, receiptNumber: receipt['receipt_number'].toString(), revision: receipt['revision'] as int, documentType: receipt['document_type'].toString(), reason: receipt['revision_reason']?.toString() ?? '');
  }

  static Future<void> saveDraftPdf(int paymentId) async {
    final bytes = await draftPdfForPayment(paymentId);
    await LocalFiles.saveBytes(fileName: 'Rent_Receipt_DRAFT_${DateTime.now().millisecondsSinceEpoch}.pdf', mime: 'application/pdf', bytes: bytes);
  }

  static Future<void> saveReceiptPdf(Map<String, Object?> receipt) async {
    final bytes = await pdfForReceipt(receipt);
    final rev = receipt['revision'] as int;
    final suffix = rev > 1 ? '_REV$rev' : '';
    final snap = Map<String, dynamic>.from(jsonDecode(receipt['snapshot_json'] as String) as Map);
    final date = parseDate(snap['payment_date']);
    await LocalFiles.saveBytes(
      fileName: 'Rent_Receipt_${receipt['receipt_number']}${suffix}_${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}.pdf',
      mime: 'application/pdf',
      bytes: bytes,
    );
  }

  static Future<Uint8List> _buildPdf({required Map<String, dynamic> snapshot, required bool draft, required String receiptNumber, required int revision, required String documentType, required String reason}) async {
    final doc = pw.Document();
    final rows = (snapshot['mini_ledger'] as List? ?? const []).cast<Map>();
    final summary = Map<String, dynamic>.from(snapshot['summary'] as Map? ?? const {});
    final title = draft ? 'DRAFT - NOT ISSUED' : (documentType == 'revised' ? 'REVISED RENT PAYMENT RECEIPT' : 'RENT PAYMENT RECEIPT');
    doc.addPage(pw.MultiPage(
      pageTheme: const pw.PageTheme(pageFormat: PdfPageFormat.letter, margin: pw.EdgeInsets.all(34)),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
          pw.Text(draft ? 'Preview' : 'Receipt No. $receiptNumber', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ]),
        if (!draft && revision > 1) pw.Text('Revision $revision - Reissued', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (draft) pw.Container(margin: const pw.EdgeInsets.only(top: 5), padding: const pw.EdgeInsets.all(6), color: PdfColors.grey200, child: pw.Text('DRAFT PREVIEW: This document has not been issued or delivered.')),
        if (!draft && revision > 1) pw.Container(margin: const pw.EdgeInsets.only(top: 5), padding: const pw.EdgeInsets.all(6), color: PdfColors.grey200, child: pw.Text('REISSUED RECEIPT${reason.isEmpty ? '' : ': $reason'}')),
        pw.SizedBox(height: 12),
      ]),
      build: (_) => [
        pw.Text(snapshot['landlord_name']?.toString() ?? '', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text([snapshot['landlord_phone'], snapshot['landlord_email']].where((x) => x?.toString().isNotEmpty == true).join(' • ')),
        pw.SizedBox(height: 8),
        pw.Text('Tenant: ${snapshot['tenant_name'] ?? ''}'),
        pw.Text('Rental property: ${snapshot['property_address']?.toString().isNotEmpty == true ? snapshot['property_address'] : snapshot['property_label']}'),
        pw.SizedBox(height: 10),
        pw.Table(columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)}, children: [
          _pair('Payment date', snapshot['payment_date']?.toString() ?? ''),
          _pair('Amount received', moneyFromCents(snapshot['payment_amount_cents'] as int? ?? 0)),
          _pair('Payment method', snapshot['payment_method']?.toString() ?? ''),
          _pair('Reference', snapshot['payment_reference']?.toString().isNotEmpty == true ? snapshot['payment_reference'].toString() : '-'),
          _pair('Balance after payment', moneyFromCents(snapshot['balance_after_cents'] as int? ?? 0)),
        ]),
        pw.SizedBox(height: 14),
        pw.Text('${parseDate(snapshot['payment_date']).year} account summary through this payment', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Wrap(spacing: 18, runSpacing: 4, children: [
          pw.Text('Rent / charges ${moneyFromCents(summary['charges_cents'] as int? ?? 0)}'),
          pw.Text('Payments ${moneyFromCents(summary['payments_cents'] as int? ?? 0)}'),
          pw.Text('Credits ${moneyFromCents(summary['credits_cents'] as int? ?? 0)}'),
          pw.Text('Adjustments ${moneyFromCents(summary['adjustments_cents'] as int? ?? 0)}'),
          pw.Text('Balance ${moneyFromCents(summary['balance_cents'] as int? ?? 0)}'),
        ]),
        pw.SizedBox(height: 14),
        pw.Text('Mini ledger through receipt payment', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Table.fromTextArray(
          headers: const ['Date', 'Type', 'Description', 'Amount', 'Balance'],
          data: rows.map((r) => [
            r['date']?.toString() ?? '', r['kind']?.toString() ?? '', r['description']?.toString() ?? '',
            moneyFromCents((r['amount_cents'] as num? ?? 0).round()), moneyFromCents((r['balance_cents'] as num? ?? 0).round()),
          ]).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 7),
          cellPadding: const pw.EdgeInsets.all(3),
          columnWidths: const {0: pw.FlexColumnWidth(.9), 1: pw.FlexColumnWidth(.7), 2: pw.FlexColumnWidth(2.4), 3: pw.FlexColumnWidth(.9), 4: pw.FlexColumnWidth(.9)},
        ),
        pw.SizedBox(height: 12),
        pw.Text(draft ? 'DRAFT - NOT ISSUED' : 'Receipt snapshot preserved in Snyder Family local records.', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    return Uint8List.fromList(await doc.save());
  }

  static pw.TableRow _pair(String a, String b) => pw.TableRow(children: [
        pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(a, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(b)),
      ]);
}