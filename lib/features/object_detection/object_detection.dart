import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:developer' as developer;
import '../../core/data_models/inference_result_model.dart';
import '../../core/services/inferenceService.dart';
import '../../core/utils/painters.dart';
import '../../core/widgets/image_inference_shell.dart';

class ObjectDetectionWidget extends ConsumerStatefulWidget {
  final String modelName;
  final String pipelinePath;
  final bool isLocalFile;
  final String? localDir;

  const ObjectDetectionWidget({
    super.key,
    required this.modelName,
    required this.pipelinePath,
    this.isLocalFile = false,
    this.localDir,
  });

  @override
  ConsumerState<ObjectDetectionWidget> createState() =>
      _ObjectDetectionWidgetState();
}

class _ObjectDetectionWidgetState extends ConsumerState<ObjectDetectionWidget> {
  late final InferenceService _inferenceObject;
  late final Future<void> _initFuture;

  File? _selectedImage;
  img.Image? _decodedImage;
  bool _isLoading = false;
  List<Map<String, dynamic>>? _recognitions;
  Size _imageSize = Size.zero;

  final List<Color> _boxColors = [
    Colors.red,
    Colors.blue.shade600,
    Colors.green,
    Colors.amber,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _inferenceObject = InferenceService(
      modelPath: widget.modelName,
      pipelinePath: widget.pipelinePath,
      isLocalFile: widget.isLocalFile,
      localDir: widget.localDir,
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
      final XFile? picked =
          await ImagePicker().pickImage(source: source);
      if (picked == null) return;

      final imageFile = File(picked.path);
      _decodedImage = img.decodeImage(await imageFile.readAsBytes());
      _imageSize = Size(
        _decodedImage!.width.toDouble(),
        _decodedImage!.height.toDouble(),
      );
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
      final inferenceOutput =
          await _inferenceObject.performInference(inputMap);

      if (kDebugMode) {
        developer.log('Object detection inference output:');
        developer.inspect(inferenceOutput);
      }

      final first = inferenceOutput.isNotEmpty
          ? inferenceOutput.values.first
          : null;
      if (first is DetectionResult) {
        setState(() => _recognitions = first.results[0] ?? []);
      } else {
        if (kDebugMode) debugPrint('Inference result is not DetectionResult.');
        setState(() => _recognitions = []);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Inference error: $e');
      setState(() => _recognitions = []);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildImageArea(double previewWidth, double previewHeight) {
    return Container(
      width: previewWidth,
      height: previewHeight,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[200],
      ),
      child: _selectedImage == null
          ? const Center(child: Text('No image selected.'))
          : ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                key: ValueKey(_selectedImage?.path),
                fit: StackFit.expand,
                children: [
                  Image.file(
                    _selectedImage!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Text('Error loading image')),
                  ),
                  if (_recognitions != null &&
                      _recognitions!.isNotEmpty &&
                      _imageSize != Size.zero)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (!constraints.maxWidth.isFinite ||
                            !constraints.maxHeight.isFinite) {
                          return const SizedBox.shrink();
                        }
                        return CustomPaint(
                          painter: DetectionBoxPainter(
                            recognitions: _recognitions!,
                            originalImageSize: _imageSize,
                            previewSize: constraints.biggest,
                            boxColors: _boxColors,
                          ),
                        );
                      },
                    ),
                  if (_recognitions != null && _recognitions!.isEmpty)
                    const Center(
                      child: Text(
                        'No detections.',
                        style: TextStyle(
                          color: Color(0xFFF73939),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final previewWidth = screenSize.width - 32.0;
    final aspectRatio =
        _imageSize.width > 0 ? _imageSize.height / _imageSize.width : 1.0;
    final previewHeight =
        math.min(previewWidth * aspectRatio, screenSize.height * 0.5);

    return ImageInferenceShell(
      title: 'Object Detection',
      initFuture: _initFuture,
      isRunning: _isLoading,
      onImagePicked: _pickImage,
      imageArea: _buildImageArea(previewWidth, previewHeight),
    );
  }
}
