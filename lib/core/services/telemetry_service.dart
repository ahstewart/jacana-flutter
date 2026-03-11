import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../data_models/inference_stat.dart';
import '../services/stats_service.dart';
import '../services/api_service.dart';

/// Syncs unsynced local [InferenceStat] records to the backend.
///
/// Sync only happens when:
///   1. The user has opted in (telemetry_opt_in = true in SharedPreferences)
///   2. The app has a valid auth token (user is signed in)
///   3. A network connection is available
///
/// All three conditions must be true. By default opt-in is false, so no data
/// leaves the device unless the user explicitly enables it.
class TelemetryService {
  final StatsService _statsService;
  final ApiService _apiService;

  TelemetryService({
    required StatsService statsService,
    required ApiService apiService,
  })  : _statsService = statsService,
        _apiService = apiService;

  /// Call this after each inference run (or on app resume) to drain the
  /// unsynced queue when eligible.
  Future<void> syncIfEligible({
    required bool optedIn,
    String? authToken,
  }) async {
    if (!optedIn) return;
    if (authToken == null || authToken.isEmpty) return;

    // Check network availability
    final connectivity = await Connectivity().checkConnectivity();
    final hasNetwork = connectivity.any((c) =>
        c == ConnectivityResult.wifi ||
        c == ConnectivityResult.mobile ||
        c == ConnectivityResult.ethernet);
    if (!hasNetwork) return;

    // Drain the unsynced queue
    try {
      final unsynced = await _statsService.getUnsyncedStats();
      if (unsynced.isEmpty) return;

      await _apiService.uploadTelemetryBatch(
        stats: unsynced,
        authToken: authToken,
      );

      final ids = unsynced
          .where((s) => s.id != null)
          .map((s) => s.id!)
          .toList();
      await _statsService.markSynced(ids);

      if (kDebugMode) {
        debugPrint('[TelemetryService] Synced ${ids.length} stat(s) to backend.');
      }
    } catch (e) {
      // Non-fatal: stats remain unsynced and will be retried next time.
      if (kDebugMode) {
        debugPrint('[TelemetryService] Sync failed (will retry): $e');
      }
    }
  }
}
