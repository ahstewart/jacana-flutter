/// A single recorded inference run, stored locally on-device via SQLite.
/// Optionally uploaded to the backend if the user is authenticated and has
/// opted into telemetry.
class InferenceStat {
  final int? id;               // local SQLite row id
  final String modelVersionId;
  final String modelName;
  final String? taskType;       // e.g. 'image-classification'
  final DateTime timestamp;
  final int totalInferenceMs;
  final bool success;
  final double? topConfidence;  // 0.0–1.0; top score (classification) or avg (detection)
  final int? numResults;        // number of classifications returned, or number of detections
  final String deviceModel;
  final String platform;        // 'android' | 'ios'
  final bool synced;            // true once pushed to the backend

  const InferenceStat({
    this.id,
    required this.modelVersionId,
    required this.modelName,
    this.taskType,
    required this.timestamp,
    required this.totalInferenceMs,
    required this.success,
    this.topConfidence,
    this.numResults,
    required this.deviceModel,
    required this.platform,
    this.synced = false,
  });

  InferenceStat copyWith({bool? synced, int? id}) => InferenceStat(
    id: id ?? this.id,
    modelVersionId: modelVersionId,
    modelName: modelName,
    taskType: taskType,
    timestamp: timestamp,
    totalInferenceMs: totalInferenceMs,
    success: success,
    topConfidence: topConfidence,
    numResults: numResults,
    deviceModel: deviceModel,
    platform: platform,
    synced: synced ?? this.synced,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'model_version_id': modelVersionId,
    'model_name': modelName,
    'task_type': taskType,
    'timestamp': timestamp.toIso8601String(),
    'total_inference_ms': totalInferenceMs,
    'success': success ? 1 : 0,
    'top_confidence': topConfidence,
    'num_results': numResults,
    'device_model': deviceModel,
    'platform': platform,
    'synced': synced ? 1 : 0,
  };

  factory InferenceStat.fromMap(Map<String, dynamic> map) => InferenceStat(
    id: map['id'] as int?,
    modelVersionId: map['model_version_id'] as String,
    modelName: map['model_name'] as String,
    taskType: map['task_type'] as String?,
    timestamp: DateTime.parse(map['timestamp'] as String),
    totalInferenceMs: map['total_inference_ms'] as int,
    success: (map['success'] as int) == 1,
    topConfidence: map['top_confidence'] as double?,
    numResults: map['num_results'] as int?,
    deviceModel: map['device_model'] as String,
    platform: map['platform'] as String,
    synced: (map['synced'] as int) == 1,
  );

  /// Serialised form sent to the backend telemetry endpoint.
  Map<String, dynamic> toApiJson() => {
    'model_version_id': modelVersionId,
    'device_model': deviceModel,
    'platform': platform,
    'total_inference_ms': totalInferenceMs,
    'success': success,
    if (taskType != null) 'task_type': taskType,
    if (topConfidence != null) 'top_confidence': topConfidence,
    if (numResults != null) 'num_results': numResults,
  };
}

/// Aggregated stats for a single model version, computed from local records.
class InferenceStatSummary {
  final String modelVersionId;
  final int totalRuns;
  final int successfulRuns;
  final double avgLatencyMs;
  final double? avgConfidence;  // null if no run produced a confidence value
  final DateTime? lastRunAt;

  const InferenceStatSummary({
    required this.modelVersionId,
    required this.totalRuns,
    required this.successfulRuns,
    required this.avgLatencyMs,
    this.avgConfidence,
    this.lastRunAt,
  });

  double get successRate => totalRuns == 0 ? 0.0 : successfulRuns / totalRuns;

  static final InferenceStatSummary empty = InferenceStatSummary(
    modelVersionId: '',
    totalRuns: 0,
    successfulRuns: 0,
    avgLatencyMs: 0,
  );
}
