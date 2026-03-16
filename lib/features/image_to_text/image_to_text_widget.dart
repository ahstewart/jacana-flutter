import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../../core/data_models/inference_result_model.dart';
import '../../core/services/inferenceService.dart';
import '../../core/services/stats_service.dart';
import '../../core/providers/stats_providers.dart';

class ImageToTextWidget extends ConsumerStatefulWidget {
  final String modelName;
  final String pipelinePath;
  final bool isLocalFile;
  final String? localDir;
  final String? modelVersionId;
  final String? modelDisplayName;

  const ImageToTextWidget({
    super.key,
    required this.modelName,
    required this.pipelinePath,
    this.isLocalFile = false,
    this.localDir,
    this.modelVersionId,
    this.modelDisplayName,
  });

  @override
  ConsumerState<ImageToTextWidget> createState() => _ImageToTextWidgetState();
}

class _ImageToTextWidgetState extends ConsumerState<ImageToTextWidget> {
  late final InferenceService _inferenceObject;
  late final Future<void> _initFuture;

  File? _selectedImage;
  img.Image? _decodedImage;
  bool _isLoading = false;
  String? _caption;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _inferenceObject = InferenceService(
      modelPath: widget.modelName,
      pipelinePath: widget.pipelinePath,
      isLocalFile: widget.isLocalFile,
      localDir: widget.localDir,
      modelVersionId: widget.modelVersionId,
      modelDisplayName: widget.modelDisplayName,
      statsService: widget.modelVersionId != null ? StatsService() : null,
    );
    _initFuture = _inferenceObject.initialize();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _inferenceObject.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isLoading) return;
    final XFile? picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    setState(() {
      _selectedImage = File(picked.path);
      _decodedImage = decoded;
      _caption = null;
    });
  }

  Future<void> _runCaption() async {
    if (_decodedImage == null || _isLoading) return;
    if (!_inferenceObject.isReady) return;

    setState(() {
      _isLoading = true;
      _caption = null;
      _elapsedSeconds = 0;
    });
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
    });

    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final inputMap = <String, dynamic>{};
      for (final input in _inferenceObject.modelPipeline!.inputs) {
        inputMap[input.name] = _decodedImage;
      }

      final result = await _inferenceObject.performInference(inputMap);
      final firstResult = result.values.firstOrNull;

      if (firstResult is TextResult) {
        setState(() => _caption = firstResult.text);
      } else if (firstResult != null) {
        setState(() => _caption = 'Unexpected result: ${firstResult.runtimeType}');
      } else {
        setState(() => _caption = 'No output produced.');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageToText] Inference error: $e');
      setState(() => _caption = 'Error: $e');
    } finally {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      if (widget.modelVersionId != null) {
        ref.read(telemetryServiceProvider).syncIfEligible(
          optedIn: ref.read(telemetryOptInProvider),
          authToken: null,
        ).ignore();
      }
      setState(() => _isLoading = false);
    }
  }

  String _formatElapsed(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  Widget _buildLoadingCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('loading-card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Generating caption\u2026',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatElapsed(_elapsedSeconds),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Model not loaded. Check logs.',
                style: TextStyle(color: Colors.orange, fontSize: 16),
              ),
            ),
          );
        }
        return _buildMainContent(context);
      },
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _inferenceObject.modelPipeline?.metadata[0].model_name ??
              widget.modelDisplayName ??
              'Image to Text',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Image preview
              GestureDetector(
                onTap: () => _pickImage(ImageSource.gallery),
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _selectedImage != null
                      ? Image.file(_selectedImage!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image_outlined, size: 48, color: cs.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to pick an image',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Pick image buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Generate / loading
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isLoading
                    ? _buildLoadingCard(context)
                    : ElevatedButton.icon(
                        key: const ValueKey('caption-btn'),
                        onPressed: _decodedImage != null ? _runCaption : null,
                        icon: const Icon(Icons.text_snippet_outlined),
                        label: const Text('Generate Caption'),
                      ),
              ),
              const SizedBox(height: 24),
              // Result
              if (_caption != null) ...[
                Text('Caption', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _caption!,
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
