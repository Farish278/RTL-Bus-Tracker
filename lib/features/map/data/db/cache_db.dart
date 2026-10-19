import 'dart:convert';
import 'cache_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class CacheDb implements CacheStore {
  CacheDb._();
  static final instance = CacheDb._();
  Database? _db;
  Future<Database>? _opening;
  DateTime? _lastCacheReadAt;
  DateTime? _lastCacheWriteAt;
  String? _lastCacheError;

  Future<Database> get db async {
    if (_db != null) return _db!;
    try {
      return await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'rtl_bus_cache.db');
    _db = await openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createNotificationClaims(db);
      },
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL, updatedAt INTEGER NOT NULL)',
        );
        await _createNotificationClaims(db);
      },
    );
    return _db!;
  }

  static Future<void> _createNotificationClaims(Database db) => db.execute(
    'CREATE TABLE IF NOT EXISTS notification_claims (id TEXT PRIMARY KEY, claimedAt INTEGER NOT NULL, sent INTEGER NOT NULL DEFAULT 0)',
  );
  Future<bool> claimNotification(String id) async {
    final database = await db;
    return database.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.delete(
        'notification_claims',
        where: 'id = ? AND sent = 0 AND claimedAt < ?',
        whereArgs: [id, now - 30000],
      );
      await txn.rawInsert(
        'INSERT OR IGNORE INTO notification_claims (id, claimedAt, sent) VALUES (?, ?, 0)',
        [id, now],
      );
      return (await txn.rawQuery('SELECT changes() AS count')).first['count'] ==
          1;
    });
  }

  Future<void> completeNotification(String id) async {
    await (await db).update(
      'notification_claims',
      {'sent': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> releaseNotification(String id) async {
    await (await db).delete(
      'notification_claims',
      where: 'id = ? AND sent = 0',
      whereArgs: [id],
    );
  }

  @override
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

  @override
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

  @override
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
    final latestSyncMs = entries['routes'];
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
