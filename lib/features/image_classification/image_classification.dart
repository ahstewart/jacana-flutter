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
import '../../core/widgets/image_inference_shell.dart';

class ImageClassificationWidget extends ConsumerStatefulWidget {
  final String modelName;
  final String pipelinePath;
  final bool isLocalFile;
  final String? localDir;
  final String? modelVersionId;
  final String? modelDisplayName;

  const ImageClassificationWidget({
    super.key,
    required this.modelName,
    required this.pipelinePath,
    this.isLocalFile = false,
    this.localDir,
    this.modelVersionId,
    this.modelDisplayName,
  });

  @override
  ConsumerState<ImageClassificationWidget> createState() =>
      _ImageClassificationWidgetState();
}

class _ImageClassificationWidgetState
    extends ConsumerState<ImageClassificationWidget> {
  late final InferenceService _inferenceObject;
  late final Future<void> _initFuture;

  File? _selectedImage;
  img.Image? _decodedImage;
  bool _isLoading = false;
  List<dynamic>? _recognitions;
  int _numResults = 3;

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
    _inferenceObject.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isLoading) return;

    try {
      final XFile? picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;

      final imageFile = File(picked.path);
      _decodedImage = img.decodeImage(await imageFile.readAsBytes());
      setState(() {
        _selectedImage = imageFile;
        _recognitions = null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to pick image: $e');
      return;
    }

    if (!_inferenceObject.isReady) return;

    setState(() => _isLoading = true);
    try {
      final inputMap = {
        for (final input in _inferenceObject.modelPipeline!.inputs)
          input.name: _decodedImage,
      };
      final inferenceResults = await _inferenceObject.performInference(
        inputMap,
      );

      final first =
          inferenceResults.isNotEmpty ? inferenceResults.values.first : null;
      if (first is ClassificationResult) {
        final recognitions = List<Map<String, dynamic>>.from(first.results);
        recognitions.removeWhere((r) => r['confidence'] == null);
        recognitions.sort(
          (a, b) =>
              (b['confidence'] as double).compareTo(a['confidence'] as double),
        );
        setState(() => _recognitions = recognitions);
      } else {
        setState(
          () =>
              _recognitions = [
                {'label': 'Error running model', 'confidence': 0.0},
              ],
        );
      }

      // Read top_k from pipeline if present.
      for (final block in _inferenceObject.modelPipeline!.postprocessing) {
        for (final step in block.steps) {
          if (step.step == 'map_labels' && step.params['top_k'] != null) {
            _numResults = step.params['top_k'] as int;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Inference error: $e');
      setState(
        () =>
            _recognitions = [
              {'label': 'Error', 'confidence': 0.0},
            ],
      );
    } finally {
      if (widget.modelVersionId != null) {
        ref
            .read(telemetryServiceProvider)
            .syncIfEligible(
              optedIn: ref.read(telemetryOptInProvider),
              authToken: null,
            )
            .ignore();
      }
      setState(() => _isLoading = false);
    }
  }

  Widget _buildImageArea() {
    if (_selectedImage == null) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[200],
        ),
        child: const Center(child: Text('No image selected.')),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.file(
          _selectedImage!,
          width: double.infinity,
          height: 300,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Results:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ..._recognitions!
              .take(_numResults)
              .map(
                (rec) => Text(
                  '${rec['label']} (${((rec['confidence'] as num) * 100).toStringAsFixed(1)}%)',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ImageInferenceShell(
      title: 'Image Classification',
      initFuture: _initFuture,
      isRunning: _isLoading,
      onImagePicked: _pickImage,
      imageArea: _buildImageArea(),
      results: _recognitions != null && !_isLoading ? _buildResults() : null,
    );
  }
}
