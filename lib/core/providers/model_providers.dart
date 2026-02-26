import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data_models/api_models.dart';
import '../services/api_service.dart';

part 'model_providers.g.dart';

// ==========================================
// API SERVICE PROVIDER
// ==========================================

/// Singleton provider for the API service
@riverpod
ApiService apiService(ApiServiceRef ref) {
  return ApiService();
}

// ==========================================
// MODELS PROVIDERS
// ==========================================

/// Fetch all models from the backend
@riverpod
Future<List<MLModel>> allModels(AllModelsRef ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getModels();
}

/// Fetch a specific model by ID
@riverpod
Future<MLModel> modelById(ModelByIdRef ref, String modelId) async {
  final api = ref.watch(apiServiceProvider);
  return api.getModel(modelId);
}

/// Get all models that have at least one supported version
/// Uses backend filtering via supported_only=true parameter
@riverpod
Future<List<MLModel>> supportedModels(SupportedModelsRef ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getModels(supportedOnly: true);
}

// ==========================================
// MODEL VERSIONS PROVIDERS
// ==========================================

/// Fetch all versions for a specific model
@riverpod
Future<List<ModelVersion>> modelVersions(
  ModelVersionsRef ref,
  String modelId,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.getModelVersions(modelId);
}

/// Get only supported versions for a model
@riverpod
Future<List<ModelVersion>> supportedVersions(
  SupportedVersionsRef ref,
  String modelId,
) async {
  final versions = await ref.watch(modelVersionsProvider(modelId).future);
  return versions.where((v) => v.is_supported).toList();
}

/// Fetch a specific model version
@riverpod
Future<ModelVersion> versionById(VersionByIdRef ref, String versionId) async {
  final api = ref.watch(apiServiceProvider);
  return api.getModelVersion(versionId);
}

// ==========================================
// SELECTED MODEL PROVIDER (State Management)
// ==========================================

/// Track the currently selected model
@riverpod
class SelectedModel extends _$SelectedModel {
  @override
  MLModel? build() {
    return null;
  }

  void setModel(MLModel? model) {
    state = model;
  }
}

/// Track the currently selected model version
@riverpod
class SelectedModelVersion extends _$SelectedModelVersion {
  @override
  ModelVersion? build() {
    return null;
  }

  void setVersion(ModelVersion? version) {
    state = version;
  }
}

// ==========================================
// MODEL DOWNLOAD PROVIDERS
// ==========================================

/// Download model file (tflite binary)
@riverpod
Future<List<int>> downloadModelFile(
  DownloadModelFileRef ref,
  String downloadUrl,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.downloadFile(downloadUrl);
}

/// Download asset file (labels, etc)
@riverpod
Future<List<int>> downloadAssetFile(
  DownloadAssetFileRef ref,
  String downloadUrl,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.downloadFile(downloadUrl);
}
