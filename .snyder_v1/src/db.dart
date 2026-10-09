import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'widgets/common.dart';

class AppDb {
  AppDb._();
  static final AppDb i = AppDb._();
  Database? _db;

  Future<Database> get db async => _db ??= await open();

  Future<Database> open() async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'snyder_family_v1.db'),
      version: 1,
      onCreate: _create,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
    return _db!;
  }

  Future<void> _create(Database d, int version) async {
    await d.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
    await d.execute('''CREATE TABLE bills(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      funded_cents INTEGER NOT NULL DEFAULT 0,
      next_due TEXT NOT NULL,
      frequency TEXT NOT NULL DEFAULT 'monthly',
      category TEXT NOT NULL DEFAULT 'Household',
      autopay INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''');
    await d.execute('''CREATE TABLE goals(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      target_cents INTEGER NOT NULL,
      saved_cents INTEGER NOT NULL DEFAULT 0,
      target_date TEXT,
      per_paycheck_cents INTEGER NOT NULL DEFAULT 0,
      priority INTEGER NOT NULL DEFAULT 1,
      category TEXT NOT NULL DEFAULT 'Savings',
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''');
    await d.execute('''CREATE TABLE paycheck_history(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pay_date TEXT NOT NULL,
      expected_cents INTEGER NOT NULL,
      actual_cents INTEGER,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )''');
    await d.execute('''CREATE TABLE stock_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'Household',
      on_hand REAL NOT NULL DEFAULT 0,
      annual_need REAL NOT NULL DEFAULT 0,
      reserve_qty REAL NOT NULL DEFAULT 0,
      package_qty REAL NOT NULL DEFAULT 1,
      package_cost_cents INTEGER NOT NULL DEFAULT 0,
      reorder_point REAL NOT NULL DEFAULT 0,
      preferred_store TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''');
    await d.execute('''CREATE TABLE shopping_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'Household',
      qty REAL NOT NULL DEFAULT 1,
      estimated_cents INTEGER NOT NULL DEFAULT 0,
      checked INTEGER NOT NULL DEFAULT 0,
      stock_item_id INTEGER,
      created_at TEXT NOT NULL,
      FOREIGN KEY(stock_item_id) REFERENCES stock_items(id)
    )''');
    await d.execute('''CREATE TABLE tasks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'Household',
      due_date TEXT,
      due_label TEXT NOT NULL DEFAULT '',
      recurrence TEXT NOT NULL DEFAULT 'none',
      done INTEGER NOT NULL DEFAULT 0,
      completed_at TEXT,
      created_at TEXT NOT NULL
    )''');
    await d.execute('''CREATE TABLE household_members(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )''');
    await d.execute('''CREATE TABLE home_goals(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      target_cents INTEGER NOT NULL DEFAULT 0,
      saved_cents INTEGER NOT NULL DEFAULT 0,
      target_date TEXT,
      category TEXT NOT NULL DEFAULT 'Home',
      notes TEXT NOT NULL DEFAULT '',
      done INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )''');

    await d.execute('''CREATE TABLE properties(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      label TEXT NOT NULL,
      address TEXT NOT NULL DEFAULT '',
      landlord_name TEXT NOT NULL DEFAULT '',
      landlord_phone TEXT NOT NULL DEFAULT '',
      landlord_email TEXT NOT NULL DEFAULT '',
      tenant_name TEXT NOT NULL DEFAULT '',
      tenant_phone TEXT NOT NULL DEFAULT '',
      tenant_email TEXT NOT NULL DEFAULT '',
      lease_start TEXT,
      lease_end TEXT,
      tracking_start TEXT,
      legacy_source_hash TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''');
    await d.execute('''CREATE TABLE rent_rules(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_id INTEGER NOT NULL,
      effective_date TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      due_day INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      FOREIGN KEY(property_id) REFERENCES properties(id)
    )''');
    await d.execute('''CREATE TABLE property_ledger(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_id INTEGER NOT NULL,
      kind TEXT NOT NULL,
      event_date TEXT NOT NULL,
      period TEXT,
      amount_cents INTEGER NOT NULL,
      effect_cents INTEGER NOT NULL,
      description TEXT NOT NULL,
      method TEXT NOT NULL DEFAULT '',
      other_method TEXT NOT NULL DEFAULT '',
      reference TEXT NOT NULL DEFAULT '',
      reverses_id INTEGER,
      legacy_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(property_id) REFERENCES properties(id),
      FOREIGN KEY(reverses_id) REFERENCES property_ledger(id)
    )''');
    await d.execute('CREATE UNIQUE INDEX idx_unique_rent_period ON property_ledger(property_id, period, kind) WHERE kind = \'charge\' AND period IS NOT NULL');
    await d.execute('''CREATE TABLE receipts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_id INTEGER NOT NULL,
      payment_ledger_id INTEGER NOT NULL,
      receipt_number TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 1,
      document_type TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'prepared',
      snapshot_json TEXT NOT NULL,
      snapshot_hash TEXT NOT NULL,
      generated_at TEXT NOT NULL,
      issued_at TEXT,
      revision_reason TEXT NOT NULL DEFAULT '',
      legacy_id TEXT,
      FOREIGN KEY(property_id) REFERENCES properties(id),
      FOREIGN KEY(payment_ledger_id) REFERENCES property_ledger(id)
    )''');
    await d.execute('''CREATE TABLE property_expenses(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_id INTEGER NOT NULL,
      event_date TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      effect_cents INTEGER NOT NULL,
      category TEXT NOT NULL,
      vendor TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      reverses_id INTEGER,
      legacy_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(property_id) REFERENCES properties(id),
      FOREIGN KEY(reverses_id) REFERENCES property_expenses(id)
    )''');
    await d.execute('''CREATE TABLE tenant_journal(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_id INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      category TEXT NOT NULL,
      note TEXT NOT NULL,
      parent_id INTEGER,
      legacy_id TEXT,
      FOREIGN KEY(property_id) REFERENCES properties(id),
      FOREIGN KEY(parent_id) REFERENCES tenant_journal(id)
    )''');
    await d.execute('''CREATE TABLE documents(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_id INTEGER NOT NULL,
      document_date TEXT NOT NULL,
      category TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      original_name TEXT NOT NULL,
      stored_path TEXT NOT NULL,
      sha256 TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      legacy_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(property_id) REFERENCES properties(id)
    )''');
    await d.execute('''CREATE TABLE audit_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_id INTEGER,
      timestamp TEXT NOT NULL,
      action TEXT NOT NULL,
      record_type TEXT NOT NULL DEFAULT '',
      record_id TEXT NOT NULL DEFAULT '',
      details_json TEXT NOT NULL DEFAULT '{}',
      FOREIGN KEY(property_id) REFERENCES properties(id)
    )''');

    await d.insert('settings', {'k': 'setup_complete', 'v': '0'});
    await d.insert('settings', {'k': 'household_name', 'v': 'Snyder Family'});
    await d.insert('settings', {'k': 'display_name', 'v': 'Cyn'});
    await d.insert('settings', {'k': 'pay_frequency_days', 'v': '14'});
    await d.insert('settings', {'k': 'expected_takehome_cents', 'v': '0'});
    await d.insert('settings', {'k': 'next_payday', 'v': isoDate(DateTime.now().add(const Duration(days: 14)))});
    await d.insert('settings', {'k': 'available_cash_cents', 'v': '0'});
    await d.insert('settings', {'k': 'household_buffer_cents', 'v': '0'});
    await d.insert('settings', {'k': 'app_lock_enabled', 'v': '0'});
  }

  String now() => DateTime.now().toIso8601String();

  Future<bool> isSetupComplete() async => (await setting('setup_complete')) == '1';

  Future<String> setting(String key, {String fallback = ''}) async {
    final d = await db;
    final rows = await d.query('settings', where: 'k=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? fallback : rows.first['v']?.toString() ?? fallback;
  }

  Future<int> settingInt(String key, {int fallback = 0}) async => int.tryParse(await setting(key)) ?? fallback;

  Future<void> setSetting(String key, Object value) async {
    final d = await db;
    await d.insert('settings', {'k': key, 'v': value.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> rows(String table, {String? where, List<Object?>? args, String? orderBy, int? limit}) async {
    final d = await db;
    return d.query(table, where: where, whereArgs: args, orderBy: orderBy, limit: limit);
  }

  Future<Map<String, Object?>?> one(String table, int id) async {
    final r = await rows(table, where: 'id=?', args: [id], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<int> insert(String table, Map<String, Object?> values) async => (await db).insert(table, values);
  Future<int> update(String table, Map<String, Object?> values, int id) async => (await db).update(table, values, where: 'id=?', whereArgs: [id]);
  Future<int> delete(String table, int id) async => (await db).delete(table, where: 'id=?', whereArgs: [id]);

  Future<void> audit({int? propertyId, required String action, String recordType = '', String recordId = '', Map<String, Object?> details = const {}}) async {
    await insert('audit_log', {
      'property_id': propertyId,
      'timestamp': now(),
      'action': action,
      'record_type': recordType,
      'record_id': recordId,
      'details_json': jsonEncode(details),
    });
  }

  Future<Map<String, dynamic>> exportAllData() async {
    const tables = [
      'settings', 'bills', 'goals', 'paycheck_history', 'stock_items', 'shopping_items', 'tasks', 'household_members', 'home_goals',
      'properties', 'rent_rules', 'property_ledger', 'receipts', 'property_expenses', 'tenant_journal', 'documents', 'audit_log'
    ];
    final out = <String, dynamic>{'schema': 1, 'exported_at': now(), 'tables': <String, dynamic>{}};
    for (final table in tables) {
      (out['tables'] as Map<String, dynamic>)[table] = await rows(table);
    }
    return out;
  }

  Future<void> restoreAllData(Map<String, dynamic> payload) async {
    if (payload['schema'] != 1 || payload['tables'] is! Map) {
      throw const FormatException('This is not a Snyder Family v1 backup.');
    }
    final d = await db;
    const insertOrder = [
      'settings', 'bills', 'goals', 'paycheck_history', 'stock_items', 'shopping_items', 'tasks', 'household_members', 'home_goals',
      'properties', 'rent_rules', 'property_ledger', 'receipts', 'property_expenses', 'tenant_journal', 'documents', 'audit_log'
    ];
    await d.transaction((txn) async {
      for (final table in insertOrder.reversed) {
        await txn.delete(table);
      }
      final tables = Map<String, dynamic>.from(payload['tables'] as Map);
      for (final table in insertOrder) {
        final list = (tables[table] as List? ?? const []);
        for (final row in list) {
          await txn.insert(table, Map<String, Object?>.from(row as Map));
        }
      }
    });
  }

  Future<void> wipeAll() async {
    final d = await db;
    await d.close();
    _db = null;
    final root = await getDatabasesPath();
    await deleteDatabase(p.join(root, 'snyder_family_v1.db'));
    await open();
  }
}