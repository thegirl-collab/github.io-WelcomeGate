import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import '../db.dart';
import 'local_files.dart';

class BackupService {
  static const magic = 'SNYDERBACKUP1';

  static Future<Map<String, dynamic>> _payloadWithDocuments() async {
    final payload = await AppDb.i.exportAllData();
    final docs = <String, String>{};
    final rows = await AppDb.i.rows('documents');
    for (final row in rows) {
      final path = row['stored_path']?.toString() ?? '';
      if (path.isEmpty) continue;
      final f = File(path);
      if (await f.exists()) {
        docs[row['id'].toString()] = base64Encode(await f.readAsBytes());
      }
    }
    payload['document_bytes'] = docs;
    return payload;
  }

  static Future<Uint8List> createEncrypted(String password) async {
    if (password.length < 6) throw ArgumentError('Backup password must be at least 6 characters.');
    final payload = utf8.encode(jsonEncode(await _payloadWithDocuments()));
    final salt = SecretKeyData.random(length: 16).bytes;
    final nonce = SecretKeyData.random(length: 12).bytes;
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 150000, bits: 256);
    final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final box = await AesGcm.with256bits().encrypt(payload, secretKey: key, nonce: nonce);
    final envelope = {
      'magic': magic,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  static Future<void> exportEncrypted(String password) async {
    final bytes = await createEncrypted(password);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    await LocalFiles.saveBytes(fileName: 'Snyder_Family_Backup_$stamp.snyderbackup', mime: 'application/octet-stream', bytes: bytes);
  }

  static Future<void> importEncrypted(String password) async {
    final picked = await LocalFiles.pickFile(mimeTypes: const ['application/octet-stream', 'application/json', '*/*']);
    if (picked == null) return;
    final envelope = jsonDecode(utf8.decode(picked.bytes)) as Map<String, dynamic>;
    if (envelope['magic'] != magic) throw const FormatException('Not a Snyder Family encrypted backup.');
    final salt = base64Decode(envelope['salt'] as String);
    final nonce = base64Decode(envelope['nonce'] as String);
    final mac = Mac(base64Decode(envelope['mac'] as String));
    final cipher = base64Decode(envelope['ciphertext'] as String);
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 150000, bits: 256);
    final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final clear = await AesGcm.with256bits().decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: key);
    final payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    await AppDb.i.restoreAllData(payload);
    await _restoreDocuments(payload);
  }

  static Future<void> _restoreDocuments(Map<String, dynamic> payload) async {
    final encoded = Map<String, dynamic>.from(payload['document_bytes'] as Map? ?? const {});
    if (encoded.isEmpty) return;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/property_documents');
    await dir.create(recursive: true);
    for (final entry in encoded.entries) {
      final id = int.tryParse(entry.key);
      if (id == null) continue;
      final row = await AppDb.i.one('documents', id);
      if (row == null) continue;
      final name = row['original_name']?.toString() ?? 'document_$id';
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${dir.path}/${id}_$safe';
      await File(path).writeAsBytes(base64Decode(entry.value as String), flush: true);
      await AppDb.i.update('documents', {'stored_path': path}, id);
    }
  }
}