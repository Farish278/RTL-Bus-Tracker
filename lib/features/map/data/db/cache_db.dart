import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class CacheDb {
  CacheDb._();
  static final instance = CacheDb._();
  Database? _db;
  DateTime? _lastCacheReadAt;
  DateTime? _lastCacheWriteAt;
  String? _lastCacheError;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'rtl_bus_cache.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL, updatedAt INTEGER NOT NULL)',
        );
      },
    );
    return _db!;
  }

  Future<void> put(String key, Object value) async {
    try {
      final database = await db;
      await database.insert('kv', {
        'k': key,
        'v': jsonEncode(value),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      _lastCacheWriteAt = DateTime.now();
      _lastCacheError = null;
    } catch (e) {
      _lastCacheError = '$e';
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> get(String key) async {
    try {
      final database = await db;
      final rows = await database.query(
        'kv',
        where: 'k = ?',
        whereArgs: [key],
        limit: 1,
      );
      _lastCacheReadAt = DateTime.now();
      _lastCacheError = null;
      if (rows.isEmpty) return null;
      return {
        'value': jsonDecode(rows.first['v'] as String),
        'updatedAt': rows.first['updatedAt'] as int,
      };
    } catch (e) {
      _lastCacheError = '$e';
      rethrow;
    }
  }

  Future<Map<String, int>> status() async {
    final database = await db;
    final rows = await database.query('kv', columns: ['k', 'updatedAt']);
    return {
      for (final row in rows) row['k'] as String: row['updatedAt'] as int,
    };
  }

  Future<void> clear() async {
    final database = await db;
    await database.delete('kv');
  }

  Future<Map<String, dynamic>> diagnostics() async {
    final entries = await status();
    final selectedRoutesCount = entries.keys
        .where((k) => k.startsWith('geometry:'))
        .length;
    final stopEtaCount = entries.keys.where((k) => k.startsWith('eta:')).length;
    final latestSyncMs = entries.values.isEmpty
        ? null
        : entries.values.reduce((a, b) => a > b ? a : b);
    return {
      'cacheEntries': entries.length,
      'geometryCacheCount': selectedRoutesCount,
      'etaCacheCount': stopEtaCount,
      'lastStaticSyncAt': latestSyncMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(latestSyncMs),
      'lastCacheReadAt': _lastCacheReadAt,
      'lastCacheWriteAt': _lastCacheWriteAt,
      'lastCacheError': _lastCacheError,
    };
  }
}
