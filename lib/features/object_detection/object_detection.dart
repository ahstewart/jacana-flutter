// this file will house the various functions and classes that will enable model inference
// primary tasks handled will be model pre-processing, inference, and post-processing

//import 'dart:ffi';
import 'dart:io';
import 'dart:math' as Math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data_models/inference_result_model.dart';
import '../../core/services/inferenceService.dart';
import '../../core/data_models/pipeline.dart';
import '../../core/utils/painters.dart';
import 'dart:developer' as developer;

// file purpose: this is the main widget for object detection, it will facilitate the capturing of images and running the inference of a model
// on the captured image. The widget will also display the results of the inference.
var modelNameReal = 'assets/ssd_mobilenet_v1_objectdetection.tflite';
var pipelinePathReal = 'assets/mobilenet_objectdetect.yaml';
var labelName = 'assets/coco-labels-91.txt';

// to generalize the object detection task, we need the object detection widget to accept the model metadata

class ObjectDetectionWidget extends ConsumerStatefulWidget {
  final String pipelinePath;
  final String modelName;
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
  // instantiate the model inference object
  late final InferenceService inferenceObject;
  bool _isLoading = false;
  File? _selectedImage;
  img.Image? _decodedImage;
  List<Map<String, dynamic>>? _recognitions;
  // define the input map
  Map<String, dynamic> inputMap = {};
  // define the detection result variable using the sealed DetectionResult class
  late Map<String, InferenceResult> inferenceOutput;
  // define the final inference results map
  DetectionResult inferenceResults = DetectionResult({});
  List<Map<String, dynamic>> primeDetectionResult = [];
  // number of results displayed on the screen, default to 3
  int numResults = 3;
  // Colors for bounding boxes - cycle through them
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
  Size _imageSize = Size.zero; // Store original image size for scaling boxes

  Future<void>? _modelInitFuture;

  @override
  void initState() {
    super.initState();
    inferenceObject = InferenceService(
      modelPath: widget.modelName,
      pipelinePath: widget.pipelinePath,
      isLocalFile: widget.isLocalFile,
      localDir: widget.localDir,
    );
    debugPrint("Initializing Object Detection Widget");
    _modelInitFuture = inferenceObject.initialize();
    debugPrint("Model initialized successfully.");
  }

  @override
  dispose() {
    inferenceObject.dispose();
    super.dispose();
  }

  // enable the selection of images
  Future<void> _pickImage(ImageSource source) async {
    if (_isLoading)
      return; // can't pick an image if inference is currently happening

    try {
      debugPrint("Picking image...");
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      if (image == null) {
        debugPrint("No image selected.");
        return;
      }
      debugPrint("Image picked.");
      debugPrint("Decoding image so it can fed into model...");
      File imageFile = File(image.path);
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
      if (kDebugMode) {
        debugPrint("Failed to pick image: $e");
      }
    }

    // run inference on the selected image
    try {
      // check that the inference object is initialized and ready
      if (!inferenceObject.isReady) {
        if (kDebugMode) {
          debugPrint(
            "Could not run inference on image, interpreter or labels haven't been loaded.",
          );
        }
        return;
      }

      setState(() {
        _isLoading = true;
      });

      // create input data map, keyed by input name
      for (var input in inferenceObject.modelPipeline!.inputs) {
        inputMap[input.name] = _decodedImage;
      }

      // run inference on selected image
      inferenceOutput = await inferenceObject.performInference(inputMap);
      if (kDebugMode) {
        debugPrint(
          "Raw inference output type (inferenceOutput): ${inferenceOutput.runtimeType}",
        );
        developer.inspect(inferenceOutput);
      }

      if (inferenceOutput[inferenceOutput.keys.toList().first]
          is DetectionResult) {
        inferenceResults =
            inferenceOutput[inferenceOutput.keys.toList().first]
                as DetectionResult;
        primeDetectionResult = inferenceResults.results[0] ?? [];
      } else {
        if (kDebugMode) {
          debugPrint(
            "Inference Error: Final inference result is not DetectionResult.",
          );
        }
        setState(() {
          _recognitions = [];
        });
        primeDetectionResult = [];
      }
      if (kDebugMode) {
        debugPrint("Inference completed.");
        debugPrint("Inference results size: ${primeDetectionResult.length}");
        debugPrint(
          "Inference results type: ${primeDetectionResult.runtimeType}",
        );
        developer.log(
          "Inspecting final inferenceResults in Object Detection widget...",
        );
        developer.inspect(inferenceResults);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Error running inference: $e");
      }
      setState(() {
        _recognitions = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    // check that the inference resulted in actual outputs
    if (primeDetectionResult.isNotEmpty) {
      debugPrint(
        "Inference results is not empty, trying to set the recognitions variable.",
      );
      /*// use the inference results to update the UI
      List<Map<String, dynamic>> recognitions = inferenceResults.values.first;
      // reorder the final recognitions by highest probability first
      recognitions.removeWhere((r) => r['score'] == null);
      recognitions.sort((a,b) => (b['score'] as double).compareTo(a['score'] as double));*/

      List<Map<String, dynamic>> recognitions = [];
      recognitions = primeDetectionResult;
      if (kDebugMode) {
        developer.log("Inspecting final recognitions variable...");
        developer.inspect(recognitions);
      }

      setState(() {
        _recognitions = recognitions;
      });
    } else {
      debugPrint(
        "Inference results are empty. Setting recognitions to an empty list.",
      );
      setState(() {
        _recognitions = [];
      });
    }

    // try to set the numResults to a custom value, if it's included in the pipeline YAML
    debugPrint(
      "Trying to set the numResults to a custom value, if it's included in the pipeline YAML.",
    );
    try {
      // look for posprocessing block with a map_labels step
      for (ProcessingBlock block
          in inferenceObject.modelPipeline!.postprocessing) {
        for (ProcessingStep step in block.steps) {
          if (step.step == 'map_labels') {
            numResults = step.params['top_k'];
          }
        }
      }
      debugPrint("numResults set to $numResults.");
    } catch (e) {
      debugPrint(
        "Error setting numResults, maybe it's not in the pipeline YAML. Using default value of 3.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _modelInitFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Model is still loading (or state was hot-reloaded before initState ran)
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          // Model failed to load
          return const Center(
            child: Text(
              "Model not loaded. Check logs.",
              style: TextStyle(color: Colors.orange, fontSize: 16),
            ),
          );
        }
        // Model loaded successfully, show the rest of your widget
        return _buildMainContent(context);
      },
    );
  }

  Widget _buildMainContent(BuildContext context) {
    // Get the size of the screen for calculating preview size
    final screenSize = MediaQuery.of(context).size;
    // Calculate a suitable size for the image preview, leaving padding
    final previewWidth = screenSize.width - 32.0; // 16 padding on each side
    // Maintain aspect ratio for height or set a max height
    // Ensure _imageSize.width is not zero to prevent division by zero
    final double aspectRatio =
        _imageSize.width > 0 ? _imageSize.height / _imageSize.width : 1.0;
    final previewHeight = Math.min(
      previewWidth * aspectRatio,
      screenSize.height * 0.5,
    ); // Max 50% screen height

    return Scaffold(
      appBar: AppBar(
        title: Text(
          inferenceObject.modelPipeline?.metadata[0].model_name ??
              'Object Detection',
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 20),
                  // --- Image Display Area with Stack for Overlays ---
                  Container(
                    constraints: BoxConstraints(
                      // Constrain the preview size
                      maxWidth: previewWidth,
                      maxHeight: previewHeight,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[200],
                    ),
                    child:
                        _selectedImage == null
                            ? const Center(child: Text('No image selected.'))
                            : ClipRRect(
                              // Clip contents to rounded border
                              borderRadius: BorderRadius.circular(11.0),
                              child: Stack(
                                key: ValueKey(_selectedImage?.path),
                                fit: StackFit.expand,
                                children: [
                                  // Base Image
                                  Image.file(
                                    _selectedImage!,
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Center(
                                              child: Text(
                                                'Error loading image',
                                              ),
                                            ),
                                  ),
                                  // Overlay Painter if results are available
                                  if (_recognitions != null &&
                                      _recognitions!.isNotEmpty &&
                                      _imageSize != Size.zero)
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        if (constraints.maxWidth.isFinite &&
                                            constraints.maxHeight.isFinite) {
                                          return CustomPaint(
                                            painter: DetectionBoxPainter(
                                              recognitions: _recognitions ?? [],
                                              originalImageSize: _imageSize,
                                              previewSize: constraints.biggest,
                                              boxColors: _boxColors,
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink(); // Don't paint if constraints are bad
                                      },
                                    ),
                                  if (_recognitions != null &&
                                      _recognitions!.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 12.0,
                                        bottom: 8.0,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Model inference failed.',
                                          style: TextStyle(
                                            color: const Color.fromARGB(
                                              255,
                                              247,
                                              57,
                                              57,
                                            ),
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                  ),
                  const SizedBox(height: 30),
                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Gallery'),
                        onPressed:
                            _isLoading
                                ? null
                                : () => _pickImage(ImageSource.gallery),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Camera'),
                        onPressed:
                            _isLoading
                                ? null
                                : () => _pickImage(ImageSource.camera),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  // // Display loading indicator or results summary/error
                  // _buildResultDisplay(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
          // Inference loading overlay
          if (_isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xAA000000),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Running model\u2026',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
