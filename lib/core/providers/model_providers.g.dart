// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$apiServiceHash() => r'ce72c4f572ea14a273b01086cdc8905a2e469468';

/// Singleton provider for the API service
///
/// Copied from [apiService].
@ProviderFor(apiService)
final apiServiceProvider = AutoDisposeProvider<ApiService>.internal(
  apiService,
  name: r'apiServiceProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$apiServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ApiServiceRef = AutoDisposeProviderRef<ApiService>;
String _$allModelsHash() => r'71dd7ac9642e26621020539ed3b78b9ebbc0e40d';

/// Fetch all models from the backend
///
/// Copied from [allModels].
@ProviderFor(allModels)
final allModelsProvider = AutoDisposeFutureProvider<List<MLModel>>.internal(
  allModels,
  name: r'allModelsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$allModelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AllModelsRef = AutoDisposeFutureProviderRef<List<MLModel>>;
String _$modelByIdHash() => r'd9e98deaff1bd323f405cca3e4515617c1b5c2b3';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Fetch a specific model by ID
///
/// Copied from [modelById].
@ProviderFor(modelById)
const modelByIdProvider = ModelByIdFamily();

/// Fetch a specific model by ID
///
/// Copied from [modelById].
class ModelByIdFamily extends Family<AsyncValue<MLModel>> {
  /// Fetch a specific model by ID
  ///
  /// Copied from [modelById].
  const ModelByIdFamily();

  /// Fetch a specific model by ID
  ///
  /// Copied from [modelById].
  ModelByIdProvider call(String modelId) {
    return ModelByIdProvider(modelId);
  }

  @override
  ModelByIdProvider getProviderOverride(covariant ModelByIdProvider provider) {
    return call(provider.modelId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'modelByIdProvider';
}

/// Fetch a specific model by ID
///
/// Copied from [modelById].
class ModelByIdProvider extends AutoDisposeFutureProvider<MLModel> {
  /// Fetch a specific model by ID
  ///
  /// Copied from [modelById].
  ModelByIdProvider(String modelId)
    : this._internal(
        (ref) => modelById(ref as ModelByIdRef, modelId),
        from: modelByIdProvider,
        name: r'modelByIdProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$modelByIdHash,
        dependencies: ModelByIdFamily._dependencies,
        allTransitiveDependencies: ModelByIdFamily._allTransitiveDependencies,
        modelId: modelId,
      );

  ModelByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.modelId,
  }) : super.internal();

  final String modelId;

  @override
  Override overrideWith(
    FutureOr<MLModel> Function(ModelByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ModelByIdProvider._internal(
        (ref) => create(ref as ModelByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        modelId: modelId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<MLModel> createElement() {
    return _ModelByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ModelByIdProvider && other.modelId == modelId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, modelId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ModelByIdRef on AutoDisposeFutureProviderRef<MLModel> {
  /// The parameter `modelId` of this provider.
  String get modelId;
}

class _ModelByIdProviderElement
    extends AutoDisposeFutureProviderElement<MLModel>
    with ModelByIdRef {
  _ModelByIdProviderElement(super.provider);

  @override
  String get modelId => (origin as ModelByIdProvider).modelId;
}

String _$supportedModelsHash() => r'5a686ae5ecbc4fb91e3c2360aa64aaefe2ce9d09';

/// Get all models that have at least one supported version
/// Uses backend filtering via supported_only=true parameter
///
/// Copied from [supportedModels].
@ProviderFor(supportedModels)
final supportedModelsProvider =
    AutoDisposeFutureProvider<List<MLModel>>.internal(
      supportedModels,
      name: r'supportedModelsProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$supportedModelsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SupportedModelsRef = AutoDisposeFutureProviderRef<List<MLModel>>;
String _$modelVersionsHash() => r'2bffbbf75ce4b5d05fa34731275e560c60088e98';

/// Fetch all versions for a specific model
///
/// Copied from [modelVersions].
@ProviderFor(modelVersions)
const modelVersionsProvider = ModelVersionsFamily();

/// Fetch all versions for a specific model
///
/// Copied from [modelVersions].
class ModelVersionsFamily extends Family<AsyncValue<List<ModelVersion>>> {
  /// Fetch all versions for a specific model
  ///
  /// Copied from [modelVersions].
  const ModelVersionsFamily();

  /// Fetch all versions for a specific model
  ///
  /// Copied from [modelVersions].
  ModelVersionsProvider call(String modelId) {
    return ModelVersionsProvider(modelId);
  }

  @override
  ModelVersionsProvider getProviderOverride(
    covariant ModelVersionsProvider provider,
  ) {
    return call(provider.modelId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'modelVersionsProvider';
}

/// Fetch all versions for a specific model
///
/// Copied from [modelVersions].
class ModelVersionsProvider
    extends AutoDisposeFutureProvider<List<ModelVersion>> {
  /// Fetch all versions for a specific model
  ///
  /// Copied from [modelVersions].
  ModelVersionsProvider(String modelId)
    : this._internal(
        (ref) => modelVersions(ref as ModelVersionsRef, modelId),
        from: modelVersionsProvider,
        name: r'modelVersionsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$modelVersionsHash,
        dependencies: ModelVersionsFamily._dependencies,
        allTransitiveDependencies:
            ModelVersionsFamily._allTransitiveDependencies,
        modelId: modelId,
      );

  ModelVersionsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.modelId,
  }) : super.internal();

  final String modelId;

  @override
  Override overrideWith(
    FutureOr<List<ModelVersion>> Function(ModelVersionsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ModelVersionsProvider._internal(
        (ref) => create(ref as ModelVersionsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        modelId: modelId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<ModelVersion>> createElement() {
    return _ModelVersionsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ModelVersionsProvider && other.modelId == modelId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, modelId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ModelVersionsRef on AutoDisposeFutureProviderRef<List<ModelVersion>> {
  /// The parameter `modelId` of this provider.
  String get modelId;
}

class _ModelVersionsProviderElement
    extends AutoDisposeFutureProviderElement<List<ModelVersion>>
    with ModelVersionsRef {
  _ModelVersionsProviderElement(super.provider);

  @override
  String get modelId => (origin as ModelVersionsProvider).modelId;
}

String _$supportedVersionsHash() => r'72504b7e627f8958b7af0cdfd52cf03dd99eed5d';

/// Get only supported versions for a model
///
/// Copied from [supportedVersions].
@ProviderFor(supportedVersions)
const supportedVersionsProvider = SupportedVersionsFamily();

/// Get only supported versions for a model
///
/// Copied from [supportedVersions].
class SupportedVersionsFamily extends Family<AsyncValue<List<ModelVersion>>> {
  /// Get only supported versions for a model
  ///
  /// Copied from [supportedVersions].
  const SupportedVersionsFamily();

  /// Get only supported versions for a model
  ///
  /// Copied from [supportedVersions].
  SupportedVersionsProvider call(String modelId) {
    return SupportedVersionsProvider(modelId);
  }

  @override
  SupportedVersionsProvider getProviderOverride(
    covariant SupportedVersionsProvider provider,
  ) {
    return call(provider.modelId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'supportedVersionsProvider';
}

/// Get only supported versions for a model
///
/// Copied from [supportedVersions].
class SupportedVersionsProvider
    extends AutoDisposeFutureProvider<List<ModelVersion>> {
  /// Get only supported versions for a model
  ///
  /// Copied from [supportedVersions].
  SupportedVersionsProvider(String modelId)
    : this._internal(
        (ref) => supportedVersions(ref as SupportedVersionsRef, modelId),
        from: supportedVersionsProvider,
        name: r'supportedVersionsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$supportedVersionsHash,
        dependencies: SupportedVersionsFamily._dependencies,
        allTransitiveDependencies:
            SupportedVersionsFamily._allTransitiveDependencies,
        modelId: modelId,
      );

  SupportedVersionsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.modelId,
  }) : super.internal();

  final String modelId;

  @override
  Override overrideWith(
    FutureOr<List<ModelVersion>> Function(SupportedVersionsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SupportedVersionsProvider._internal(
        (ref) => create(ref as SupportedVersionsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        modelId: modelId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<ModelVersion>> createElement() {
    return _SupportedVersionsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SupportedVersionsProvider && other.modelId == modelId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, modelId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SupportedVersionsRef on AutoDisposeFutureProviderRef<List<ModelVersion>> {
  /// The parameter `modelId` of this provider.
  String get modelId;
}

class _SupportedVersionsProviderElement
    extends AutoDisposeFutureProviderElement<List<ModelVersion>>
    with SupportedVersionsRef {
  _SupportedVersionsProviderElement(super.provider);

  @override
  String get modelId => (origin as SupportedVersionsProvider).modelId;
}

String _$versionByIdHash() => r'65860566bd6012680a7ae1a01366f475819860be';

/// Fetch a specific model version
///
/// Copied from [versionById].
@ProviderFor(versionById)
const versionByIdProvider = VersionByIdFamily();

/// Fetch a specific model version
///
/// Copied from [versionById].
class VersionByIdFamily extends Family<AsyncValue<ModelVersion>> {
  /// Fetch a specific model version
  ///
  /// Copied from [versionById].
  const VersionByIdFamily();

  /// Fetch a specific model version
  ///
  /// Copied from [versionById].
  VersionByIdProvider call(String versionId) {
    return VersionByIdProvider(versionId);
  }

  @override
  VersionByIdProvider getProviderOverride(
    covariant VersionByIdProvider provider,
  ) {
    return call(provider.versionId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'versionByIdProvider';
}

/// Fetch a specific model version
///
/// Copied from [versionById].
class VersionByIdProvider extends AutoDisposeFutureProvider<ModelVersion> {
  /// Fetch a specific model version
  ///
  /// Copied from [versionById].
  VersionByIdProvider(String versionId)
    : this._internal(
        (ref) => versionById(ref as VersionByIdRef, versionId),
        from: versionByIdProvider,
        name: r'versionByIdProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$versionByIdHash,
        dependencies: VersionByIdFamily._dependencies,
        allTransitiveDependencies: VersionByIdFamily._allTransitiveDependencies,
        versionId: versionId,
      );

  VersionByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.versionId,
  }) : super.internal();

  final String versionId;

  @override
  Override overrideWith(
    FutureOr<ModelVersion> Function(VersionByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: VersionByIdProvider._internal(
        (ref) => create(ref as VersionByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        versionId: versionId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<ModelVersion> createElement() {
    return _VersionByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is VersionByIdProvider && other.versionId == versionId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, versionId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin VersionByIdRef on AutoDisposeFutureProviderRef<ModelVersion> {
  /// The parameter `versionId` of this provider.
  String get versionId;
}

class _VersionByIdProviderElement
    extends AutoDisposeFutureProviderElement<ModelVersion>
    with VersionByIdRef {
  _VersionByIdProviderElement(super.provider);

  @override
  String get versionId => (origin as VersionByIdProvider).versionId;
}

String _$downloadModelFileHash() => r'ce21da173b6848d6b5250742e543eed68e46b7d7';

/// Download model file (tflite binary)
///
/// Copied from [downloadModelFile].
@ProviderFor(downloadModelFile)
const downloadModelFileProvider = DownloadModelFileFamily();

/// Download model file (tflite binary)
///
/// Copied from [downloadModelFile].
class DownloadModelFileFamily extends Family<AsyncValue<List<int>>> {
  /// Download model file (tflite binary)
  ///
  /// Copied from [downloadModelFile].
  const DownloadModelFileFamily();

  /// Download model file (tflite binary)
  ///
  /// Copied from [downloadModelFile].
  DownloadModelFileProvider call(String downloadUrl) {
    return DownloadModelFileProvider(downloadUrl);
  }

  @override
  DownloadModelFileProvider getProviderOverride(
    covariant DownloadModelFileProvider provider,
  ) {
    return call(provider.downloadUrl);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'downloadModelFileProvider';
}

/// Download model file (tflite binary)
///
/// Copied from [downloadModelFile].
class DownloadModelFileProvider extends AutoDisposeFutureProvider<List<int>> {
  /// Download model file (tflite binary)
  ///
  /// Copied from [downloadModelFile].
  DownloadModelFileProvider(String downloadUrl)
    : this._internal(
        (ref) => downloadModelFile(ref as DownloadModelFileRef, downloadUrl),
        from: downloadModelFileProvider,
        name: r'downloadModelFileProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$downloadModelFileHash,
        dependencies: DownloadModelFileFamily._dependencies,
        allTransitiveDependencies:
            DownloadModelFileFamily._allTransitiveDependencies,
        downloadUrl: downloadUrl,
      );

  DownloadModelFileProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.downloadUrl,
  }) : super.internal();

  final String downloadUrl;

  @override
  Override overrideWith(
    FutureOr<List<int>> Function(DownloadModelFileRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: DownloadModelFileProvider._internal(
        (ref) => create(ref as DownloadModelFileRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        downloadUrl: downloadUrl,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<int>> createElement() {
    return _DownloadModelFileProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is DownloadModelFileProvider &&
        other.downloadUrl == downloadUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, downloadUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin DownloadModelFileRef on AutoDisposeFutureProviderRef<List<int>> {
  /// The parameter `downloadUrl` of this provider.
  String get downloadUrl;
}

class _DownloadModelFileProviderElement
    extends AutoDisposeFutureProviderElement<List<int>>
    with DownloadModelFileRef {
  _DownloadModelFileProviderElement(super.provider);

  @override
  String get downloadUrl => (origin as DownloadModelFileProvider).downloadUrl;
}

String _$downloadAssetFileHash() => r'8c9c130a15047cc828268943f167f583b391a0cf';

/// Download asset file (labels, etc)
///
/// Copied from [downloadAssetFile].
@ProviderFor(downloadAssetFile)
const downloadAssetFileProvider = DownloadAssetFileFamily();

/// Download asset file (labels, etc)
///
/// Copied from [downloadAssetFile].
class DownloadAssetFileFamily extends Family<AsyncValue<List<int>>> {
  /// Download asset file (labels, etc)
  ///
  /// Copied from [downloadAssetFile].
  const DownloadAssetFileFamily();

  /// Download asset file (labels, etc)
  ///
  /// Copied from [downloadAssetFile].
  DownloadAssetFileProvider call(String downloadUrl) {
    return DownloadAssetFileProvider(downloadUrl);
  }

  @override
  DownloadAssetFileProvider getProviderOverride(
    covariant DownloadAssetFileProvider provider,
  ) {
    return call(provider.downloadUrl);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'downloadAssetFileProvider';
}

/// Download asset file (labels, etc)
///
/// Copied from [downloadAssetFile].
class DownloadAssetFileProvider extends AutoDisposeFutureProvider<List<int>> {
  /// Download asset file (labels, etc)
  ///
  /// Copied from [downloadAssetFile].
  DownloadAssetFileProvider(String downloadUrl)
    : this._internal(
        (ref) => downloadAssetFile(ref as DownloadAssetFileRef, downloadUrl),
        from: downloadAssetFileProvider,
        name: r'downloadAssetFileProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$downloadAssetFileHash,
        dependencies: DownloadAssetFileFamily._dependencies,
        allTransitiveDependencies:
            DownloadAssetFileFamily._allTransitiveDependencies,
        downloadUrl: downloadUrl,
      );

  DownloadAssetFileProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.downloadUrl,
  }) : super.internal();

  final String downloadUrl;

  @override
  Override overrideWith(
    FutureOr<List<int>> Function(DownloadAssetFileRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: DownloadAssetFileProvider._internal(
        (ref) => create(ref as DownloadAssetFileRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        downloadUrl: downloadUrl,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<int>> createElement() {
    return _DownloadAssetFileProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is DownloadAssetFileProvider &&
        other.downloadUrl == downloadUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, downloadUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin DownloadAssetFileRef on AutoDisposeFutureProviderRef<List<int>> {
  /// The parameter `downloadUrl` of this provider.
  String get downloadUrl;
}

class _DownloadAssetFileProviderElement
    extends AutoDisposeFutureProviderElement<List<int>>
    with DownloadAssetFileRef {
  _DownloadAssetFileProviderElement(super.provider);

  @override
  String get downloadUrl => (origin as DownloadAssetFileProvider).downloadUrl;
}

String _$selectedModelHash() => r'53c86c07b453acf9acc1e582c3e1e5d05498b19d';

/// Track the currently selected model
///
/// Copied from [SelectedModel].
@ProviderFor(SelectedModel)
final selectedModelProvider =
    AutoDisposeNotifierProvider<SelectedModel, MLModel?>.internal(
      SelectedModel.new,
      name: r'selectedModelProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$selectedModelHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SelectedModel = AutoDisposeNotifier<MLModel?>;
String _$selectedModelVersionHash() =>
    r'1b07543103e81a7977d7c1199670493b94f186d8';

/// Track the currently selected model version
///
/// Copied from [SelectedModelVersion].
@ProviderFor(SelectedModelVersion)
final selectedModelVersionProvider =
    AutoDisposeNotifierProvider<SelectedModelVersion, ModelVersion?>.internal(
      SelectedModelVersion.new,
      name: r'selectedModelVersionProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$selectedModelVersionHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SelectedModelVersion = AutoDisposeNotifier<ModelVersion?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
