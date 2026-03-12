import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../data_models/inference_stat.dart';

// ---------------------------------------------------------------------------
// Device model helper — fetches once and caches for the app lifetime
// ---------------------------------------------------------------------------
class DeviceInfoHelper {
  static String _cachedModel = 'unknown';

  /// Async init — call once at app startup (e.g. in main()) before
  /// any inference runs. After that [cachedDeviceModel] is safe to use
  /// synchronously anywhere in the app.
  static Future<void> init() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        _cachedModel = '${info.manufacturer} ${info.model}'.trim();
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        _cachedModel = info.utsname.machine;
      }
    } catch (_) {
      _cachedModel = 'unknown';
    }
  }

  /// Synchronous access after [init()] has been awaited.
  static String get cachedDeviceModel => _cachedModel;

  static String get currentPlatform =>
      Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : 'unknown';
}

// ---------------------------------------------------------------------------
// StatsService — SQLite-backed local inference stats store
// ---------------------------------------------------------------------------
class StatsService {
  static const _dbName = 'inference_stats.db';
  static const _table = 'stats';
  static const _version = 1;

  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: _version,
      onCreate:
          (db, version) => db.execute('''
        CREATE TABLE $_table (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          model_version_id TEXT NOT NULL,
          model_name       TEXT NOT NULL,
          task_type        TEXT,
          timestamp        TEXT NOT NULL,
          total_inference_ms INTEGER NOT NULL,
          success          INTEGER NOT NULL,
          top_confidence   REAL,
          num_results      INTEGER,
          device_model     TEXT NOT NULL,
          platform         TEXT NOT NULL,
          synced           INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
    return _db!;
  }

  // ── Write ────────────────────────────────────────────────────────────────

  Future<InferenceStat> recordStat(InferenceStat stat) async {
    final db = await _getDb();
    final id = await db.insert(_table, stat.toMap()..remove('id'));
    return stat.copyWith(id: id);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  Future<List<InferenceStat>> getStatsForVersion(String versionId) async {
    final db = await _getDb();
    final rows = await db.query(
      _table,
      where: 'model_version_id = ?',
      whereArgs: [versionId],
      orderBy: 'timestamp DESC',
    );
    return rows.map(InferenceStat.fromMap).toList();
  }

  Future<List<InferenceStat>> getUnsyncedStats() async {
    final db = await _getDb();
    final rows = await db.query(
      _table,
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
      limit: 200, // batch cap
    );
    return rows.map(InferenceStat.fromMap).toList();
  }

  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _getDb();
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $_table SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  Future<InferenceStatSummary?> getSummaryForVersion(String versionId) async {
    final db = await _getDb();
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*)                        AS total_runs,
        SUM(success)                    AS successful_runs,
        AVG(total_inference_ms)         AS avg_latency_ms,
        AVG(top_confidence)             AS avg_confidence,
        MAX(timestamp)                  AS last_run_at
      FROM $_table
      WHERE model_version_id = ?
    ''',
      [versionId],
    );

    if (rows.isEmpty) return null;
    final row = rows.first;
    final total = (row['total_runs'] as int?) ?? 0;
    if (total == 0) return null;

    return InferenceStatSummary(
      modelVersionId: versionId,
      totalRuns: total,
      successfulRuns: (row['successful_runs'] as int?) ?? 0,
      avgLatencyMs: (row['avg_latency_ms'] as double?) ?? 0,
      avgConfidence: row['avg_confidence'] as double?,
      lastRunAt:
          row['last_run_at'] != null
              ? DateTime.tryParse(row['last_run_at'] as String)
              : null,
    );
  }

  // ── Housekeeping ──────────────────────────────────────────────────────────

  /// Deletes all synced records older than [maxAge] to keep the DB lean.
  Future<void> pruneOldSynced({
    Duration maxAge = const Duration(days: 30),
  }) async {
    final db = await _getDb();
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();
    await db.delete(
      _table,
      where: 'synced = 1 AND timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  Future<void> close() async => _db?.close();
}
