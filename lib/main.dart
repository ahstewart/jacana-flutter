import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
//import 'package:freezed_annotation/freezed_annotation.dart';
//import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'features/image_classification/image_classification.dart';
import 'core/services/inferenceService.dart';
import 'core/data_models/pipeline.dart';
import 'core/data_models/api_models.dart';
import 'core/providers/model_providers.dart';
import 'package:yaml/yaml.dart';
import 'dart:convert';
import 'features/object_detection/object_detection.dart';
import 'package:path_provider/path_provider.dart';

// Returns free bytes available on the filesystem containing [dirPath], or null on failure.
Future<int?> _getFreeDiskBytes(String dirPath) async {
  try {
    final result = await Process.run('df', ['-B1', dirPath]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    // Typical df -B1 output: Filesystem 1B-blocks Used Available Use% Mounted
    final parts = lines.last.trim().split(RegExp(r'\s+'));
    if (parts.length >= 4) return int.tryParse(parts[3]);
  } catch (_) {}
  return null;
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details); // Still show red screen in debug
    debugPrint('Caught by global error handler: ${details.exception}');
    // Optionally, you can log details.stack as well
  };
  // This will catch all uncaught async errors
  runZonedGuarded(
    () {
      runApp(ProviderScope(child: const MyApp()));
    },
    (error, stackTrace) {
      debugPrint('Uncaught async error: $error');
      // Optionally log stackTrace
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket AI',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 23, 148, 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      home: const ModelList(title: 'Pocket AI'),
    );
  }
}

final selectedModelProvider = StateProvider<MLModel?>((ref) {
  return null;
});

// Provider to track which model's modal is open
final selectedModelModalProvider = StateProvider<MLModel?>((ref) {
  return null;
});

// Model for storing downloaded model metadata
class DownloadedModel {
  final String modelId;
  final String modelName;
  final String versionName;
  final String versionId;
  final String category;
  final DateTime downloadedAt;
  final String localPath;

  DownloadedModel({
    required this.modelId,
    required this.modelName,
    required this.versionName,
    required this.versionId,
    required this.category,
    required this.downloadedAt,
    required this.localPath,
  });

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'versionName': versionName,
    'versionId': versionId,
    'category': category,
    'downloadedAt': downloadedAt.toIso8601String(),
    'localPath': localPath,
  };

  static DownloadedModel fromJson(Map<String, dynamic> json) => DownloadedModel(
    modelId: json['modelId'],
    modelName: json['modelName'],
    versionName: json['versionName'],
    versionId: json['versionId'],
    category: json['category'],
    downloadedAt: DateTime.parse(json['downloadedAt']),
    localPath: json['localPath'],
  );
}

// Provider for managing downloaded models
final downloadedModelsProvider =
    StateNotifierProvider<DownloadedModelsNotifier, List<DownloadedModel>>(
      (ref) => DownloadedModelsNotifier(),
    );

class DownloadedModelsNotifier extends StateNotifier<List<DownloadedModel>> {
  DownloadedModelsNotifier() : super([]) {
    _loadDownloadedModels();
  }

  Future<void> _loadDownloadedModels() async {
    // TODO: Load downloaded models from local storage (SharedPreferences or local JSON file)
    // For now, starting with empty list
  }

  void addDownloadedModel(DownloadedModel model) {
    state = [...state, model];
    // TODO: Save updated list to local storage
  }

  void removeDownloadedModel(String versionId) {
    state = state.where((m) => m.versionId != versionId).toList();
    // TODO: Save updated list to local storage
  }
}

// Widget containing the model tile list
class Models extends ConsumerStatefulWidget {
  const Models({super.key});

  @override
  ConsumerState<Models> createState() => _ModelsState();
}

class _ModelsState extends ConsumerState<Models> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(supportedModelsProvider);

    return modelsAsync.when(
      data: (modelList) {
        if (modelList.isEmpty) {
          return const Center(child: Text('No supported models available'));
        }

        // Collect unique categories, sorted alphabetically
        final categories = modelList.map((m) => m.category).toSet().toList()..sort();

        // Apply search and category filters
        final filtered = modelList.where((m) {
          final q = _searchQuery.toLowerCase();
          final matchesSearch = q.isEmpty ||
              m.name.toLowerCase().contains(q) ||
              m.description.toLowerCase().contains(q);
          final matchesCategory =
              _selectedCategory == null || m.category == _selectedCategory;
          return matchesSearch && matchesCategory;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search models\u2026',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            // Category filter chips
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _selectedCategory == null,
                      onSelected: (_) => setState(() => _selectedCategory = null),
                    ),
                  ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(category),
                        selected: _selectedCategory == category,
                        onSelected: (selected) => setState(
                          () => _selectedCategory = selected ? category : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Model list or empty state
            if (filtered.isEmpty)
              const Expanded(
                child: Center(child: Text('No models match your search.')),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 16.0,
                      runSpacing: 16.0,
                      children: [
                        for (MLModel model in filtered)
                          SizedBox(
                            width: 300,
                            child: Card(
                              child: ListTile(
                                title: Text(model.name),
                                subtitle: Text(model.category),
                                leading: const Icon(Icons.model_training),
                                onTap: () => _showModelDetailsModal(context, model),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading models: $err')),
    );
  }

  void _showModelDetailsModal(BuildContext context, MLModel model) {
    showDialog(
      context: context,
      builder: (context) => ModelDetailsModal(model: model),
    );
  }
}

// Modal widget for displaying model details and versions
class ModelDetailsModal extends ConsumerStatefulWidget {
  final MLModel model;

  const ModelDetailsModal({required this.model, super.key});

  @override
  ConsumerState<ModelDetailsModal> createState() => _ModelDetailsModalState();
}

class _ModelDetailsModalState extends ConsumerState<ModelDetailsModal> {
  @override
  Widget build(BuildContext context) {
    final versionsAsync = ref.watch(modelVersionsProvider(widget.model.id));

    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      child: versionsAsync.when(
        data: (versions) {
          final supportedVersions =
              versions.where((v) => v.is_supported).toList();

          if (supportedVersions.isEmpty) {
            return AlertDialog(
              title: const Text('Model Details'),
              content: const Text('No supported versions available'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          }

          return AlertDialog(
            title: Text(widget.model.name),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Category: ${widget.model.category}'),
                  const SizedBox(height: 8),
                  Text('Description: ${widget.model.description}'),
                  const SizedBox(height: 16),
                  Text(
                    'Supported Versions (${supportedVersions.length}):',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  ...supportedVersions.map(
                    (version) => _VersionTile(
                      version: version,
                      modelName: widget.model.name,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
        loading:
            () => AlertDialog(
              content: const Center(child: CircularProgressIndicator()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
        error:
            (err, stack) => AlertDialog(
              title: const Text('Error'),
              content: Text('Error loading versions: $err'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
      ),
    );
  }
}

class _VersionTile extends ConsumerStatefulWidget {
  final ModelVersion version;
  final String modelName;

  const _VersionTile({required this.version, required this.modelName});

  @override
  ConsumerState<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends ConsumerState<_VersionTile> {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version: ${widget.version.version_name}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text('Status: ${widget.version.status}'),
            Text('License: ${widget.version.license_type}'),
            Text(
              'Size: ${(widget.version.file_size_bytes / 1024 / 1024).toStringAsFixed(2)} MB',
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _handleDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    ref
                        .read(selectedModelVersionProvider.notifier)
                        .setVersion(widget.version);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDownload() async {
    final version = widget.version;
    final modelName = widget.modelName;

    // Show storage-aware confirmation before doing anything.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _StorageConfirmDialog(version: version, modelName: modelName),
    );
    if (confirmed != true || !mounted) return;

    // Capture everything before closing — widget will be disposed after the pop.
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiServiceProvider);
    final notifier = ref.read(downloadedModelsProvider.notifier);

    // Close the parent dialog immediately so the user isn't blocked.
    Navigator.pop(context);

    // Show a persistent in-progress snackbar.
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading $modelName\u2026'),
        duration: const Duration(minutes: 10),
      ),
    );

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final versionDir = Directory(
        '${appDir.path}/downloaded_models/${version.id}',
      );
      debugPrint(
        '[Download] Starting: $modelName v${version.version_name} (${version.id})',
      );
      debugPrint('[Download] Target dir: ${versionDir.path}');
      if (!await versionDir.exists()) {
        await versionDir.create(recursive: true);
        debugPrint('[Download] Created directory: ${versionDir.path}');
      }

      final assetKeys = <String>[
        'tflite',
        if (version.assets.labels != null) 'labels',
        if (version.assets.anchors != null) 'anchors',
        if (version.assets.tokenizer != null) 'tokenizer',
        if (version.assets.vocab != null) 'vocab',
      ];
      debugPrint('[Download] Assets to fetch: $assetKeys');

      for (final assetKey in assetKeys) {
        debugPrint('[Download] Fetching asset: $assetKey');
        final bytes = await api.downloadAsset(version.id, assetKey);
        debugPrint('[Download] Received $assetKey: ${bytes.length} bytes');
        await File('${versionDir.path}/$assetKey').writeAsBytes(bytes);
        debugPrint('[Download] Wrote $assetKey to disk');
      }

      if (version.pipeline_spec != null) {
        debugPrint('[Download] Writing pipeline_spec.json');
        await File(
          '${versionDir.path}/pipeline_spec.json',
        ).writeAsString(jsonEncode(version.pipeline_spec!.toJson()));
      }

      debugPrint('[Download] Complete: $modelName → ${versionDir.path}');
      notifier.addDownloadedModel(
        DownloadedModel(
          modelId: version.model_id,
          modelName: modelName,
          versionName: version.version_name,
          versionId: version.id,
          category: version.pipeline_spec?.metadata.firstOrNull?.model_task ?? 'unknown',
          downloadedAt: DateTime.now(),
          localPath: versionDir.path,
        ),
      );

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$modelName downloaded! Check the "My AI" tab.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e, stack) {
      debugPrint('[Download] Error: $e');
      debugPrint('[Download] Stack: $stack');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

// widget for the model range
class ModelRange extends ConsumerWidget {
  const ModelRange({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModel = ref.watch(selectedModelProvider);

    // check if no model has been selected
    if (selectedModel == null) {
      return const Center(child: Text('Select a model to view details!'));
    }

    // Fetch versions for the selected model
    final versionsAsync = ref.watch(modelVersionsProvider(selectedModel.id));

    return versionsAsync.when(
      data: (versions) {
        // Filter to only supported versions
        final supportedVersions =
            versions.where((v) => v.is_supported).toList();

        if (supportedVersions.isEmpty) {
          return const Center(
            child: Text('No supported versions available for this model'),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: () {
                    ref.read(selectedModelProvider.notifier).state = null;
                    ref.read(selectedIndexProvider.notifier).state = 0;
                  },
                  child: const Text('Back to Model List'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Model: ${selectedModel.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('Description: ${selectedModel.description}'),
                Text('Category: ${selectedModel.category}'),
                Text('Total Downloads: ${selectedModel.total_download_count}'),
                const SizedBox(height: 16),
                Text(
                  'Supported Versions (${supportedVersions.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: supportedVersions.length,
                  itemBuilder: (context, index) {
                    final version = supportedVersions[index];
                    return VersionCard(
                      version: version,
                      modelName: selectedModel.name,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (err, stack) => Center(child: Text('Error loading versions: $err')),
    );
  }
}

// Widget to display individual version details
class VersionCard extends ConsumerWidget {
  final ModelVersion version;
  final String modelName;

  const VersionCard({
    required this.version,
    required this.modelName,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version: ${version.version_name}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text('Status: ${version.status}'),
            Text('License: ${version.license_type}'),
            Text(
              'File Size: ${(version.file_size_bytes / 1024 / 1024).toStringAsFixed(2)} MB',
            ),
            Text('Downloads: ${version.download_count}'),
            const SizedBox(height: 12),
            if (version.pipeline_spec != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pipeline Configuration:',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  PipelineConfigDisplay(config: version.pipeline_spec!),
                  const SizedBox(height: 12),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _showDownloadDialog(context, ref, version, modelName);
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download Model'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    ref
                        .read(selectedModelVersionProvider.notifier)
                        .setVersion(version);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Use Model'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloadDialog(
    BuildContext context,
    WidgetRef ref,
    ModelVersion version,
    String modelName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _StorageConfirmDialog(version: version, modelName: modelName),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiServiceProvider);
    final notifier = ref.read(downloadedModelsProvider.notifier);

    // Show a persistent in-progress snackbar.
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading $modelName\u2026'),
        duration: const Duration(minutes: 10),
      ),
    );

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final versionDir = Directory(
        '${appDir.path}/downloaded_models/${version.id}',
      );
      debugPrint(
        '[Download] Starting: $modelName v${version.version_name} (${version.id})',
      );
      debugPrint('[Download] Target dir: ${versionDir.path}');
      if (!await versionDir.exists()) {
        await versionDir.create(recursive: true);
        debugPrint('[Download] Created directory: ${versionDir.path}');
      }

      final assetKeys = <String>[
        'tflite',
        if (version.assets.labels != null) 'labels',
        if (version.assets.anchors != null) 'anchors',
        if (version.assets.tokenizer != null) 'tokenizer',
        if (version.assets.vocab != null) 'vocab',
      ];
      debugPrint('[Download] Assets to fetch: $assetKeys');

      for (final assetKey in assetKeys) {
        debugPrint('[Download] Fetching asset: $assetKey');
        final bytes = await api.downloadAsset(version.id, assetKey);
        debugPrint('[Download] Received $assetKey: ${bytes.length} bytes');
        await File('${versionDir.path}/$assetKey').writeAsBytes(bytes);
        debugPrint('[Download] Wrote $assetKey to disk');
      }

      if (version.pipeline_spec != null) {
        debugPrint('[Download] Writing pipeline_spec.json');
        await File('${versionDir.path}/pipeline_spec.json').writeAsString(
          jsonEncode(version.pipeline_spec!.toJson()),
        );
      }

      debugPrint('[Download] Complete: $modelName → ${versionDir.path}');
      notifier.addDownloadedModel(
        DownloadedModel(
          modelId: version.model_id,
          modelName: modelName,
          versionName: version.version_name,
          versionId: version.id,
          category: version.pipeline_spec?.metadata.firstOrNull?.model_task ?? 'unknown',
          downloadedAt: DateTime.now(),
          localPath: versionDir.path,
        ),
      );

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$modelName downloaded! Check the "My AI" tab.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e, stack) {
      debugPrint('[Download] Error: $e');
      debugPrint('[Download] Stack: $stack');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

// Confirmation dialog that shows model size vs available device storage
// before the user commits to a download.
class _StorageConfirmDialog extends StatefulWidget {
  final ModelVersion version;
  final String modelName;

  const _StorageConfirmDialog({
    required this.version,
    required this.modelName,
  });

  @override
  State<_StorageConfirmDialog> createState() => _StorageConfirmDialogState();
}

class _StorageConfirmDialogState extends State<_StorageConfirmDialog> {
  int? _freeBytes;
  bool _loadingSpace = true;

  @override
  void initState() {
    super.initState();
    _loadFreeSpace();
  }

  Future<void> _loadFreeSpace() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final free = await _getFreeDiskBytes(appDir.path);
      if (mounted) setState(() { _freeBytes = free; _loadingSpace = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingSpace = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelBytes = widget.version.file_size_bytes;
    final tooLow = _freeBytes != null && _freeBytes! < modelBytes;

    return AlertDialog(
      title: const Text('Download Model?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Model: ${widget.modelName}'),
            Text('Version: ${widget.version.version_name}'),
            const SizedBox(height: 12),
            // Storage comparison
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Download size:'),
                Text(
                  _formatBytes(modelBytes),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available storage:'),
                _loadingSpace
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _freeBytes != null
                            ? _formatBytes(_freeBytes!)
                            : 'Unknown',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: tooLow ? Colors.red : null,
                        ),
                      ),
              ],
            ),
            if (tooLow) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Not enough free space — download may fail.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            const Text('Assets included:'),
            const SizedBox(height: 4),
            const Text('• TFLite model'),
            if (widget.version.assets.labels != null) const Text('• Labels'),
            if (widget.version.assets.anchors != null) const Text('• Anchors'),
            if (widget.version.assets.tokenizer != null) const Text('• Tokenizer'),
            if (widget.version.assets.vocab != null) const Text('• Vocab'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Download'),
        ),
      ],
    );
  }
}

// Widget to display pipeline configuration details
class PipelineConfigDisplay extends StatelessWidget {
  final PipelineConfig config;

  const PipelineConfigDisplay({required this.config, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inputs: ${config.inputs.length}',
          style: const TextStyle(fontSize: 12),
        ),
        for (var input in config.inputs)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Text(
              '• ${input.name} [${input.shape.join(',')}}] - ${input.dtype}',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Preprocessing: ${config.preprocessing.length} block(s)',
          style: const TextStyle(fontSize: 12),
        ),
        for (var block in config.preprocessing)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Text(
              '• ${block.input_name} (${block.steps.length} steps)',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Postprocessing: ${config.postprocessing.length} block(s)',
          style: const TextStyle(fontSize: 12),
        ),
        for (var block in config.postprocessing)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Text(
              '• ${block.output_name} (${block.interpretation})',
              style: const TextStyle(fontSize: 10),
            ),
          ),
      ],
    );
  }
}

// Widget to display downloaded models
class DownloadedModels extends ConsumerWidget {
  const DownloadedModels({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadedModels = ref.watch(downloadedModelsProvider);

    if (downloadedModels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No downloaded models yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Download models from the Home page to use them offline',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloaded Models (${downloadedModels.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: downloadedModels.length,
              itemBuilder: (context, index) {
                final model = downloadedModels[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.modelName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text('Version: ${model.versionName}'),
                        Text(
                          'Downloaded: ${model.downloadedAt.toString().split('.')[0]}',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _runModel(context, model),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Run Model'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                ref
                                    .read(downloadedModelsProvider.notifier)
                                    .removeDownloadedModel(model.versionId);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Model removed successfully'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _runModel(BuildContext context, DownloadedModel model) {
    final tflitePath = '${model.localPath}/tflite';
    final pipelinePath = '${model.localPath}/pipeline_spec.json';

    Widget? inferenceWidget;
    switch (model.category) {
      case 'image_classification':
      case 'image-classification':
        inferenceWidget = ImageClassificationWidget(
          modelName: tflitePath,
          pipelinePath: pipelinePath,
          isLocalFile: true,
          localDir: model.localPath,
        );
      case 'object_detection':
      case 'object-detection':
        inferenceWidget = ObjectDetectionWidget(
          modelName: tflitePath,
          pipelinePath: pipelinePath,
          isLocalFile: true,
          localDir: model.localPath,
        );
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Task type "${model.category}" is not yet supported for on-device inference.',
            ),
          ),
        );
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => inferenceWidget!),
    );
  }
}

// widget for the user
class Profile extends StatelessWidget {
  const Profile({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('This is where the user profile will show up');
  }
}

// provider for selected page
final selectedIndexProvider = StateProvider<int>((ref) {
  return 0;
});

class ModelList extends ConsumerStatefulWidget {
  const ModelList({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  ConsumerState<ModelList> createState() => _ModelList();
}

class _ModelList extends ConsumerState<ModelList> {
  late List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [Models(), DownloadedModels(), ModelRange(), Profile()];
  }

  @override
  Widget build(BuildContext context) {
    var selectedIndex = ref.watch(selectedIndexProvider);
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Center(child: Text(widget.title)),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(child: pages[selectedIndex]),

            // This is the nav bar
            SafeArea(
              child: NavigationBar(
                destinations: [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.cloud_download),
                    label: 'My AI',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.science),
                    label: 'Range',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
                selectedIndex: selectedIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    ref.read(selectedIndexProvider.notifier).state = index;
                  });
                },
              ),
            ),
          ],
        ),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
