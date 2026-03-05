import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data_models/inference_result_model.dart';
import '../../core/services/inferenceService.dart';

class TextGenerationWidget extends ConsumerStatefulWidget {
  final String pipelinePath;
  final String modelName;
  final bool isLocalFile;
  final String? localDir;

  const TextGenerationWidget({
    super.key,
    required this.modelName,
    required this.pipelinePath,
    this.isLocalFile = false,
    this.localDir,
  });

  @override
  ConsumerState<TextGenerationWidget> createState() => _TextGenerationWidgetState();
}

class _TextGenerationWidgetState extends ConsumerState<TextGenerationWidget> {
  late final InferenceService inferenceObject;
  Future<void>? _modelInitFuture;

  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;
  String? _generatedText;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    inferenceObject = InferenceService(
      modelPath: widget.modelName,
      pipelinePath: widget.pipelinePath,
      isLocalFile: widget.isLocalFile,
      localDir: widget.localDir,
    );
    _modelInitFuture = inferenceObject.initialize();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    inferenceObject.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _runGeneration() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (!inferenceObject.isReady) {
      if (kDebugMode) debugPrint('[TextGen] Inference object not ready.');
      return;
    }

    setState(() {
      _isLoading = true;
      _generatedText = null;
      _elapsedSeconds = 0;
    });
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
    });

    // Yield to the event loop so Flutter renders the loading state
    // before inference blocks the Dart thread.
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      // Feed the prompt to every text input tensor in the pipeline
      final inputMap = <String, dynamic>{};
      for (final input in inferenceObject.modelPipeline!.inputs) {
        inputMap[input.name] = text;
      }

      final result = await inferenceObject.performInference(inputMap);
      final firstResult = result.values.firstOrNull;

      if (firstResult is TextResult) {
        setState(() => _generatedText = firstResult.text);
      } else if (firstResult != null) {
        setState(() => _generatedText =
            'Unexpected result type: ${firstResult.runtimeType}');
      } else {
        setState(() => _generatedText = 'No output produced.');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[TextGen] Inference error: $e');
      setState(() => _generatedText = 'Error: $e');
    } finally {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      setState(() => _isLoading = false);
    }
  }

  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildLoadingCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('loading-card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Processing your prompt…',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatElapsed(_elapsedSeconds),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _modelInitFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Model not loaded. Check logs.',
              style: TextStyle(color: Colors.orange, fontSize: 16),
            ),
          );
        }
        return _buildMainContent(context);
      },
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          inferenceObject.modelPipeline?.metadata[0].model_name ?? 'Text Generation',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Prompt input
              TextField(
                controller: _promptController,
                enabled: !_isLoading,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter your prompt\u2026',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),
              // Generate button OR loading indicator
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isLoading
                    ? _buildLoadingCard(context)
                    : ElevatedButton.icon(
                        key: const ValueKey('generate-btn'),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generate'),
                        onPressed: _runGeneration,
                      ),
              ),
              const SizedBox(height: 24),
              // Result area
              if (_generatedText != null) ...[
                Text(
                  'Output',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _generatedText!,
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
