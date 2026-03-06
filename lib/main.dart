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
import 'features/text_generation/text_generation.dart';
import 'features/semantic_segmentation/semantic_segmentation.dart';
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
  if (bytes >= 1024 * 1024)
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
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

  /// Pipeline model_task (e.g. "image_classification") — used for inference routing.
  final String category;

  /// MLModel category (e.g. "utility", "diagnostic") — used for filtering.
  final String modelCategory;

  final DateTime downloadedAt;
  final String localPath;

  DownloadedModel({
    required this.modelId,
    required this.modelName,
    required this.versionName,
    required this.versionId,
    required this.category,
    required this.modelCategory,
    required this.downloadedAt,
    required this.localPath,
  });

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'versionName': versionName,
    'versionId': versionId,
    'category': category,
    'modelCategory': modelCategory,
    'downloadedAt': downloadedAt.toIso8601String(),
    'localPath': localPath,
  };

  static DownloadedModel fromJson(Map<String, dynamic> json) => DownloadedModel(
    modelId: json['modelId'],
    modelName: json['modelName'],
    versionName: json['versionName'],
    versionId: json['versionId'],
    category: json['category'],
    modelCategory: json['modelCategory'] ?? 'other',
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

// Model for tracking an in-progress model download
class InProgressDownload {
  final String versionId;
  final String modelName;
  final String versionName;
  final int completedSteps;
  final int totalSteps;

  InProgressDownload({
    required this.versionId,
    required this.modelName,
    required this.versionName,
    required this.completedSteps,
    required this.totalSteps,
  });

  double get progress => totalSteps > 0 ? completedSteps / totalSteps : 0.0;

  InProgressDownload copyWith({int? completedSteps}) => InProgressDownload(
    versionId: versionId,
    modelName: modelName,
    versionName: versionName,
    completedSteps: completedSteps ?? this.completedSteps,
    totalSteps: totalSteps,
  );
}

final inProgressDownloadsProvider = StateNotifierProvider<
  InProgressDownloadsNotifier,
  Map<String, InProgressDownload>
>((ref) => InProgressDownloadsNotifier());

class InProgressDownloadsNotifier
    extends StateNotifier<Map<String, InProgressDownload>> {
  InProgressDownloadsNotifier() : super({});

  void startDownload(InProgressDownload download) {
    state = {...state, download.versionId: download};
  }

  void updateProgress(String versionId, int completedSteps) {
    final current = state[versionId];
    if (current == null) return;
    state = {
      ...state,
      versionId: current.copyWith(completedSteps: completedSteps),
    };
  }

  void finishDownload(String versionId) {
    final updated = Map<String, InProgressDownload>.from(state)
      ..remove(versionId);
    state = updated;
  }
}

// Widget containing the model tile list
String _friendlyTask(String category) => category
    .split('_')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

class Models extends ConsumerStatefulWidget {
  const Models({super.key});

  @override
  ConsumerState<Models> createState() => _ModelsState();
}

class _ModelsState extends ConsumerState<Models> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedTask;
  String _sortOrder = 'downloads'; // 'downloads' | 'rating' | 'newest'

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

        // Collect unique categories and tasks, sorted alphabetically
        final categories =
            modelList.map((m) => m.category).toSet().toList()..sort();
        final tasks =
            modelList
                .map((m) => m.task)
                .whereType<String>()
                .where((t) => t.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

        // Apply search, category, and task filters
        var filtered =
            modelList.where((m) {
              final q = _searchQuery.toLowerCase();
              final matchesSearch =
                  q.isEmpty ||
                  m.name.toLowerCase().contains(q) ||
                  m.description.toLowerCase().contains(q) ||
                  (m.task?.toLowerCase().contains(q) ?? false);
              final matchesCategory =
                  _selectedCategory == null || m.category == _selectedCategory;
              final matchesTask =
                  _selectedTask == null || m.task == _selectedTask;
              return matchesSearch && matchesCategory && matchesTask;
            }).toList();

        // Apply sort
        switch (_sortOrder) {
          case 'rating':
            filtered.sort(
              (a, b) => b.rating_weighted_avg.compareTo(a.rating_weighted_avg),
            );
          case 'newest':
            filtered.sort((a, b) => b.created_at.compareTo(a.created_at));
          default:
            filtered.sort(
              (a, b) =>
                  b.total_download_count.compareTo(a.total_download_count),
            );
        }

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
                  suffixIcon:
                      _searchQuery.isNotEmpty
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
            // Category filter chips + sort button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FilterChip(
                              label: const Text('All'),
                              selected: _selectedCategory == null,
                              onSelected:
                                  (_) =>
                                      setState(() => _selectedCategory = null),
                            ),
                          ),
                          for (final category in categories)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: FilterChip(
                                label: Text(_friendlyTask(category)),
                                selected: _selectedCategory == category,
                                onSelected:
                                    (selected) => setState(
                                      () =>
                                          _selectedCategory =
                                              selected ? category : null,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.sort),
                    tooltip: 'Sort by',
                    initialValue: _sortOrder,
                    onSelected: (v) => setState(() => _sortOrder = v),
                    itemBuilder:
                        (_) => const [
                          PopupMenuItem(
                            value: 'downloads',
                            child: Text('Most Downloaded'),
                          ),
                          PopupMenuItem(
                            value: 'rating',
                            child: Text('Top Rated'),
                          ),
                          PopupMenuItem(value: 'newest', child: Text('Newest')),
                        ],
                  ),
                ],
              ),
            ),
            // Task filter chips (only shown when tasks are available)
            if (tasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: const Text('All Tasks'),
                          selected: _selectedTask == null,
                          onSelected:
                              (_) => setState(() => _selectedTask = null),
                        ),
                      ),
                      for (final task in tasks)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(_friendlyTask(task)),
                            selected: _selectedTask == task,
                            onSelected:
                                (selected) => setState(
                                  () => _selectedTask = selected ? task : null,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // Model list or empty state
            if (filtered.isEmpty)
              const Expanded(
                child: Center(child: Text('No models match your search.')),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final model = filtered[index];
                    return _ModelCard(
                      model: model,
                      onTap: () => _showModelDetailsModal(context, model),
                    );
                  },
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

class _ModelCard extends StatelessWidget {
  final MLModel model;
  final VoidCallback onTap;

  const _ModelCard({required this.model, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category + task badges
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Chip(
                    label: Text(
                      _friendlyTask(model.category),
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: cs.primaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (model.task != null && model.task!.isNotEmpty)
                    Chip(
                      label: Text(
                        _friendlyTask(model.task!),
                        style: TextStyle(
                          color: cs.onSecondaryContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      backgroundColor: cs.secondaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Model name
              Text(
                model.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Description
              Text(
                model.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              // Stats row
              Row(
                children: [
                  const Icon(Icons.download_outlined, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _formatCount(model.total_download_count),
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.star_outline, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    model.total_ratings > 0
                        ? '${model.rating_weighted_avg.toStringAsFixed(1)} (${_formatCount(model.total_ratings)})'
                        : 'No ratings yet',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
              versions.where((v) => v.isUsable).toList();

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

          final theme = Theme.of(context);
          final cs = theme.colorScheme;

          return AlertDialog(
            contentPadding: EdgeInsets.zero,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category + task badges
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Chip(
                              label: Text(
                                _friendlyTask(widget.model.category),
                                style: TextStyle(
                                  color: cs.onPrimaryContainer,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor: cs.primaryContainer,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            if (widget.model.task != null &&
                                widget.model.task!.isNotEmpty)
                              Chip(
                                label: Text(
                                  _friendlyTask(widget.model.task!),
                                  style: TextStyle(
                                    color: cs.onSecondaryContainer,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                backgroundColor: cs.secondaryContainer,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Model name
                        Text(
                          widget.model.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Description
                        Text(
                          widget.model.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Aggregate stats row
                        Row(
                          children: [
                            const Icon(Icons.download_outlined, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              _formatCount(widget.model.total_download_count),
                              style: theme.textTheme.labelMedium,
                            ),
                            const SizedBox(width: 20),
                            const Icon(Icons.star_outline, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              widget.model.total_ratings > 0
                                  ? '${widget.model.rating_weighted_avg.toStringAsFixed(1)} (${_formatCount(widget.model.total_ratings)})'
                                  : 'No ratings yet',
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // ── Versions ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      'Versions (${supportedVersions.length})',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      children:
                          supportedVersions
                              .map(
                                (version) => _VersionTile(
                                  version: version,
                                  modelName: widget.model.name,
                                  modelCategory: widget.model.category,
                                ),
                              )
                              .toList(),
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
  final String modelCategory;

  const _VersionTile({
    required this.version,
    required this.modelName,
    required this.modelCategory,
  });

  @override
  ConsumerState<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends ConsumerState<_VersionTile> {
  @override
  Widget build(BuildContext context) {
    final downloaded = ref.watch(downloadedModelsProvider);
    final isDownloaded = downloaded.any(
      (m) => m.versionId == widget.version.id,
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.version.version_name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.download_outlined, size: 14),
                const SizedBox(width: 4),
                Text(
                  _formatCount(widget.version.download_count),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(width: 16),
                const Icon(Icons.star_outline, size: 14),
                const SizedBox(width: 4),
                Text(
                  widget.version.num_ratings > 0
                      ? '${widget.version.rating_avg.toStringAsFixed(1)} (${_formatCount(widget.version.num_ratings)})'
                      : 'No ratings',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(width: 16),
                Text(
                  '${(widget.version.file_size_bytes / 1024 / 1024).toStringAsFixed(1)} MB',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.version.license_type,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child:
                  isDownloaded
                      ? ElevatedButton.icon(
                        onPressed: () {
                          ref
                              .read(selectedModelVersionProvider.notifier)
                              .setVersion(widget.version);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Run'),
                      )
                      : ElevatedButton.icon(
                        onPressed: _handleDownload,
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                      ),
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
      builder:
          (_) => _StorageConfirmDialog(version: version, modelName: modelName),
    );
    if (confirmed != true || !mounted) return;

    // Capture everything before closing — widget will be disposed after the pop.
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiServiceProvider);
    final notifier = ref.read(downloadedModelsProvider.notifier);
    final inProgressNotifier = ref.read(inProgressDownloadsProvider.notifier);

    // Compute the asset list here so we know totalSteps before closing.
    final assetKeys = <String>[
      'tflite',
      if (version.assets.labels != null) 'labels',
      if (version.assets.anchors != null) 'anchors',
      if (version.assets.tokenizer != null) 'tokenizer',
      if (version.assets.vocab != null) 'vocab',
    ];
    final totalSteps =
        assetKeys.length + (version.pipeline_spec != null ? 1 : 0);

    // Register with in-progress provider so the My AI tab shows the card immediately.
    inProgressNotifier.startDownload(
      InProgressDownload(
        versionId: version.id,
        modelName: modelName,
        versionName: version.version_name,
        completedSteps: 0,
        totalSteps: totalSteps,
      ),
    );

    // Close the parent dialog and navigate directly to the My AI tab.
    Navigator.pop(context);
    ref.read(selectedIndexProvider.notifier).state = 1;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading $modelName\u2026'),
        duration: const Duration(seconds: 2),
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

      debugPrint('[Download] Assets to fetch: $assetKeys');

      int completedSteps = 0;
      for (final assetKey in assetKeys) {
        debugPrint('[Download] Fetching asset: $assetKey');
        final bytes = await api.downloadAsset(version.id, assetKey);
        debugPrint('[Download] Received $assetKey: ${bytes.length} bytes');
        await File('${versionDir.path}/$assetKey').writeAsBytes(bytes);
        debugPrint('[Download] Wrote $assetKey to disk');
        inProgressNotifier.updateProgress(version.id, ++completedSteps);
      }

      if (version.pipeline_spec != null) {
        debugPrint('[Download] Writing pipeline_spec.json');
        await File(
          '${versionDir.path}/pipeline_spec.json',
        ).writeAsString(jsonEncode(version.pipeline_spec!.toJson()));
        inProgressNotifier.updateProgress(version.id, ++completedSteps);
      }

      debugPrint('[Download] Complete: $modelName → ${versionDir.path}');
      inProgressNotifier.finishDownload(version.id);
      notifier.addDownloadedModel(
        DownloadedModel(
          modelId: version.model_id,
          modelName: modelName,
          versionName: version.version_name,
          versionId: version.id,
          category:
              version.pipeline_spec?.metadata.firstOrNull?.model_task ??
              'unknown',
          modelCategory: widget.modelCategory,
          downloadedAt: DateTime.now(),
          localPath: versionDir.path,
        ),
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text('$modelName downloaded!'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stack) {
      debugPrint('[Download] Error: $e');
      debugPrint('[Download] Stack: $stack');
      inProgressNotifier.finishDownload(version.id);
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select a model to take out to the range'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.read(selectedIndexProvider.notifier).state = 0;
              },
              child: const Text('Browse Models'),
            ),
          ],
        ),
      );
    }

    // Fetch versions for the selected model
    final versionsAsync = ref.watch(modelVersionsProvider(selectedModel.id));

    return versionsAsync.when(
      data: (versions) {
        // Filter to only supported versions
        final supportedVersions =
            versions.where((v) => v.isUsable).toList();

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
                      modelCategory: selectedModel.category,
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
  final String modelCategory;

  const VersionCard({
    required this.version,
    required this.modelName,
    required this.modelCategory,
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
              version.version_name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.download_outlined, size: 14),
                const SizedBox(width: 4),
                Text(
                  _formatCount(version.download_count),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(width: 16),
                const Icon(Icons.star_outline, size: 14),
                const SizedBox(width: 4),
                Text(
                  version.num_ratings > 0
                      ? '${version.rating_avg.toStringAsFixed(1)} (${_formatCount(version.num_ratings)})'
                      : 'No ratings',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(width: 16),
                Text(
                  '${(version.file_size_bytes / 1024 / 1024).toStringAsFixed(1)} MB',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              version.license_type,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
      builder:
          (_) => _StorageConfirmDialog(version: version, modelName: modelName),
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
          category:
              version.pipeline_spec?.metadata.firstOrNull?.model_task ??
              'unknown',
          modelCategory: modelCategory,
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

  const _StorageConfirmDialog({required this.version, required this.modelName});

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
      if (mounted)
        setState(() {
          _freeBytes = free;
          _loadingSpace = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingSpace = false;
        });
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
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
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
            if (widget.version.assets.tokenizer != null)
              const Text('• Tokenizer'),
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
class DownloadedModels extends ConsumerStatefulWidget {
  const DownloadedModels({super.key});

  @override
  ConsumerState<DownloadedModels> createState() => _DownloadedModelsState();
}

class _DownloadedModelsState extends ConsumerState<DownloadedModels> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTask;
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadedModels = ref.watch(downloadedModelsProvider);
    final inProgress = ref.watch(inProgressDownloadsProvider);

    if (downloadedModels.isEmpty && inProgress.isEmpty) {
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

    // Collect unique tasks and categories from downloaded models
    final tasks =
        downloadedModels
            .map((m) => m.category)
            .where((t) => t.isNotEmpty && t != 'unknown')
            .toSet()
            .toList()
          ..sort();
    final categories =
        downloadedModels
            .map((m) => m.modelCategory)
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    // Apply search + filters
    final filtered =
        downloadedModels.where((m) {
          final q = _searchQuery.toLowerCase();
          final matchesSearch =
              q.isEmpty ||
              m.modelName.toLowerCase().contains(q) ||
              m.category.toLowerCase().contains(q);
          final matchesTask =
              _selectedTask == null || m.category == _selectedTask;
          final matchesCategory =
              _selectedCategory == null || m.modelCategory == _selectedCategory;
          return matchesSearch && matchesTask && matchesCategory;
        }).toList();

    final totalCount = downloadedModels.length + inProgress.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search my models\u2026',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _searchQuery.isNotEmpty
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
        // Task filter chips
        if (tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: const Text('All Tasks'),
                      selected: _selectedTask == null,
                      onSelected: (_) => setState(() => _selectedTask = null),
                    ),
                  ),
                  for (final task in tasks)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(_friendlyTask(task)),
                        selected: _selectedTask == task,
                        onSelected:
                            (selected) => setState(
                              () => _selectedTask = selected ? task : null,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Category filter chips
        if (categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: const Text('All Categories'),
                      selected: _selectedCategory == null,
                      onSelected:
                          (_) => setState(() => _selectedCategory = null),
                    ),
                  ),
                  for (final cat in categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(_friendlyTask(cat)),
                        selected: _selectedCategory == cat,
                        onSelected:
                            (selected) => setState(
                              () => _selectedCategory = selected ? cat : null,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Count header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'My AI ($totalCount)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // In-progress download cards (always visible regardless of filter)
                for (final download in inProgress.values)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            download.modelName,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text('Version: ${download.versionName}'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.download_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Downloading\u2026 ${(download.progress * 100).toInt()}%',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: download.progress),
                        ],
                      ),
                    ),
                  ),
                // Filtered download cards
                if (filtered.isEmpty && downloadedModels.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('No models match your filters.')),
                  )
                else
                  ...filtered.map(
                    (model) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Task + category chips
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (model.category != 'unknown' &&
                                    model.category.isNotEmpty)
                                  Chip(
                                    label: Text(
                                      _friendlyTask(model.category),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                    backgroundColor:
                                        Theme.of(
                                          context,
                                        ).colorScheme.secondaryContainer,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                if (model.modelCategory.isNotEmpty)
                                  Chip(
                                    label: Text(
                                      _friendlyTask(model.modelCategory),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    backgroundColor:
                                        Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              model.modelName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
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
                                        content: Text(
                                          'Model removed successfully',
                                        ),
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
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
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
      case 'text_generation':
      case 'text-generation':
        inferenceWidget = TextGenerationWidget(
          modelName: tflitePath,
          pipelinePath: pipelinePath,
          isLocalFile: true,
          localDir: model.localPath,
        );
      case 'semantic_segmentation':
      case 'image_segmentation':
      case 'image-segmentation':
      case 'semantic-segmentation':
      case 'segmentation':
        inferenceWidget = SemanticSegmentationWidget(
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
