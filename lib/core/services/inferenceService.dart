import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:developer' as developer;
import 'package:yaml/yaml.dart';
import '../data_models/pipeline.dart';
import '../data_models/inference_result_model.dart';
import '../utils/list_extensions.dart';
import '../utils/data_types.dart';
import '../utils/math.dart';
import 'tokenizer_service.dart';

// inference class that contains methods for loading models, pre and post processing, and running the actual inference
class InferenceService {
  // initialize interpreter, pipeline (metadata), etc
  Interpreter? _interpreter;
  Pipeline? modelPipeline;

  List<String>? _labels;
  TokenizerService? _tokenizer;
  // Stores the preprocessed inputs from the last performInference call.
  // Used by the autoregressive 'generate' postprocessing step.
  Map<String, dynamic> _lastPreprocessedInputs = {};
  bool get isReady => _interpreter != null && modelPipeline != null;

  dynamic scoreTensor;

  final String modelPath;
  final String pipelinePath;
  // When true, modelPath and pipelinePath are filesystem paths (downloaded models).
  // When false (default), they are Flutter asset paths.
  final bool isLocalFile;
  // Directory containing the downloaded model assets (tflite, labels, etc.).
  // Required when isLocalFile is true.
  final String? localDir;

  InferenceService({
    required this.modelPath,
    required this.pipelinePath,
    this.isLocalFile = false,
    this.localDir,
  });

  // Call this to initialize
  Future<void> initialize() async {
    await loadPipeline(
      pipelinePath,
    ); // Load pipeline first to get model info if needed
    await loadModel(modelPath); // Load model
    await loadLabelsIfNeeded(); // Load labels if needed by any postprocessing step
    await loadTokenizerIfNeeded(); // Load tokenizer if any preprocessing block uses text input
  }

  // load model from model_path (AKA create an interpreter)
  Future<void> loadModel(
    String modelPath, {
    String modelFramework = "tflite",
  }) async {
    if (modelFramework == "tflite") {
      debugPrint("Loading TFLite model from $modelPath...");
      final options = InterpreterOptions()..threads = 4;

      try {
        _interpreter = isLocalFile
            ? Interpreter.fromFile(File(modelPath), options: options)
            : await Interpreter.fromAsset(modelPath, options: options);

        if (kDebugMode) {
          debugPrint(_interpreter?.getInputTensors().toString());
          debugPrint(_interpreter?.getOutputTensors().toString());
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint("Failed to load model: $e");
        }
      }
    }
  }

  // load pipeline from a pipeline_path, using the pipeline data model
  Future<void> loadPipeline(String pipelinePath) async {
    if (kDebugMode) {
      debugPrint("Loading model pipeline file...");
    }

    final Map<String, dynamic> pipelineMap;
    if (isLocalFile) {
      // Local files are stored as JSON (PipelineConfig schema, compatible with Pipeline.fromJson).
      final contents = await File(pipelinePath).readAsString();
      pipelineMap = jsonDecode(contents) as Map<String, dynamic>;
    } else {
      // Asset files are YAML.
      final contents = await rootBundle.loadString(pipelinePath);
      pipelineMap = _convertYamlToJson(loadYaml(contents)) as Map<String, dynamic>;
    }

    // create pipeline object from pipeline_map
    modelPipeline = Pipeline.fromJson(pipelineMap);

    if (kDebugMode) {
      debugPrint("Model pipeline file loaded successfully.");
    }
  }

  Future<void> loadLabelsIfNeeded() async {
    debugPrint("Loading labels if needed...");
    if (modelPipeline == null) return;
    String? labelsUrl;
    for (var block in modelPipeline!.postprocessing) {
      for (var step in block.steps) {
        if (step.step == 'map_labels') {
          labelsUrl = step.params['labels_url'] as String?;
          break;
        }
      }
      if (labelsUrl != null) break;
    }

    // For local models, load labels from the downloaded file regardless of the pipeline's labels_url.
    if (isLocalFile && localDir != null) {
      final labelsFile = File('$localDir/labels');
      if (await labelsFile.exists()) {
        final labelsData = await labelsFile.readAsString();
        _labels = labelsData
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        debugPrint('InferenceService: Labels loaded from local file: ${_labels?.length} labels');
      } else {
        _labels = [];
        debugPrint('InferenceService: No local labels file found.');
      }
      return;
    }

    if (labelsUrl != null) {
      try {
        final labelsData = await rootBundle.loadString(labelsUrl);
        _labels =
            labelsData
                .split('\n')
                .map((label) => label.trim())
                .where((label) => label.isNotEmpty)
                .toList();
        if (kDebugMode) {
          debugPrint(
            "InferenceService: Labels loaded from $labelsUrl: ${_labels?.length} labels",
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            "InferenceService: Failed to load labels from $labelsUrl: $e",
          );
        }
        _labels = []; // Default to empty on error
      }
    } else {
      _labels = [];
      if (kDebugMode) {
        debugPrint(
          "InferenceService: No 'labels_url' found in any 'map_labels' postprocessing step.",
        );
      }
    }
  }

  Future<void> loadTokenizerIfNeeded() async {
    if (modelPipeline == null) return;

    // Only load if at least one preprocessing block handles text input
    final hasTextInput = modelPipeline!.preprocessing.any(
      (b) => b.expects_type == 'text',
    );
    if (!hasTextInput) return;

    // Find optional explicit file references from the tokenize step params
    String? vocabFile;
    String? tokenizerFile;
    for (final block in modelPipeline!.preprocessing) {
      for (final step in block.steps) {
        if (step.step == 'tokenize') {
          vocabFile = step.params['vocab_file'] as String?;
          tokenizerFile = step.params['tokenizer_file'] as String?;
          break;
        }
      }
    }

    _tokenizer = await TokenizerService.load(
      vocabPath: vocabFile,
      tokenizerJsonPath: tokenizerFile,
      isLocalFile: isLocalFile,
      localDir: localDir,
    );

    if (_tokenizer == null) {
      debugPrint('[InferenceService] Warning: text input detected but no tokenizer could be loaded.');
    } else {
      debugPrint('[InferenceService] Tokenizer loaded successfully.');
    }
  }

  // helper method for converting YAML map to JSON
  dynamic _convertYamlToJson(dynamic yaml) {
    if (yaml is YamlMap) {
      return Map<String, dynamic>.fromEntries(
        yaml.entries.map(
          (e) => MapEntry(e.key.toString(), _convertYamlToJson(e.value)),
        ),
      );
    }
    if (yaml is YamlList) {
      return yaml.map(_convertYamlToJson).toList();
    }
    return yaml;
  }

  // the inference object needs to handle the preprocessing, inference, and postprocessing phase
  // preprocess will take a raw input, and based on the pipeline YAML, perform the preprocessing, and return a
  // tensor ready for inference
  Future<dynamic> preprocess(dynamic rawInput, String inputName) async {
    // first make sure model and pipeline are loaded
    if (!isReady) {
      if (kDebugMode) {
        debugPrint(
          "Cannot preprocess input, model or pipeline have not been successfully loaded.",
        );
      }
      return rawInput;
    }
    // then make sure pipeline includes preprocessing steps? if it doesn't, skip all of this and return rawInput
    if (modelPipeline!.preprocessing.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          "Pipeline is missing preprocessing block, returning raw input unchanged.",
        );
      }
      return rawInput;
    }

    debugPrint("Starting preprocessing...");
    // if preprocessing steps are included, then match the preprocessing step with an input using input_name
    int? inputIndex;
    int? preprocessBlockIndex;

    debugPrint("Matching given input name to input name in pipeline file.");
    // match _inputName to an input block
    for (var i = 0; i < modelPipeline!.inputs.length; i++) {
      if (modelPipeline!.inputs[i].name == inputName) {
        inputIndex = i;
        break;
      }
    }

    debugPrint(
      "Matching input name to a preprocessing block in pipeline file.",
    );
    // match _inputName to a preprocessing block
    for (var i = 0; i < modelPipeline!.preprocessing.length; i++) {
      if (modelPipeline!.preprocessing[i].input_name == inputName) {
        preprocessBlockIndex = i;
        break;
      }
    }

    // check if the input could not be matched to an input block or preprocessing block
    if (inputIndex == null || preprocessBlockIndex == null) {
      if (kDebugMode) {
        debugPrint(
          "Provided input name does not match input or preprocessing block in pipeline. Aborting preprocessing.",
        );
      }
      return rawInput;
    }

    // once the preprocessing step and input are matched, use the expects_type to validate the rawInput
    final String expectedType =
        modelPipeline!.preprocessing[preprocessBlockIndex].expects_type;

    debugPrint(
      "Validating that the raw input matches the 'expects_type' parameter in the pipeline file...",
    );
    switch (expectedType) {
      case 'image':
        if (rawInput is! img.Image) {
          if (kDebugMode) {
            debugPrint("Raw input type: ${rawInput.runtimeType.toString()}");
            throw ArgumentError(
              "This preprocessing block expects an image, but raw input is not an img.Image type. Aborting preprocessing.",
            );
          }
          return rawInput;
        }
        if (kDebugMode) {
          debugPrint(
            "Raw input type matches expected type. Proceeding with preprocessing.",
          );
        }
        break;
      case 'text':
        if (rawInput is! String) {
          if (kDebugMode) {
            debugPrint("Raw input type: ${rawInput.runtimeType.toString()}");
            throw ArgumentError(
              "This preprocessing block expects text, but raw input is not a String. Aborting preprocessing.",
            );
          }
          return rawInput;
        }
        if (kDebugMode) {
          debugPrint(
            "Raw input type match expected type. Proceeding with preprocessing.",
          );
        }
        break;
      case 'audio':
        if (rawInput is! Uint8List) {
          if (kDebugMode) {
            debugPrint("Raw input type: ${rawInput.runtimeType.toString()}");
            throw ArgumentError(
              "This preprocessing block expects a audio, but raw input is not a Uint8List type. Aborting preprocessing.",
            );
          }
          return rawInput;
        }
        if (kDebugMode) {
          debugPrint(
            "Raw input type match expected type. Proceeding with preprocessing.",
          );
        }
        break;
      // Add cases for other expected raw input types ('tensor', 'generic_list', etc.)
      default:
        throw UnimplementedError(
          "Unsupported 'expects_type' in pipeline: $expectedType",
        );
    }
    debugPrint("Raw input type validated.");

    // now that input is validated, start tracking the input with a variable
    // initialize it with the rawInput
    dynamic currentInput = rawInput;

    debugPrint(
      "Executing steps for preprocessing block ${modelPipeline!.preprocessing[preprocessBlockIndex].input_name}...",
    );
    // start looping through the preprocessing steps
    for (var preStep
        in modelPipeline!.preprocessing[preprocessBlockIndex].steps) {
      currentInput = await _performPreprocessingStep(
        currentInput,
        preStep,
        preprocessBlockIndex,
      );
      debugPrint(
        "Preprocessing step ${preStep.step} completed successfully...",
      );
    }

    debugPrint("Preprocessing complete.");

    // return final input tensor
    return currentInput;
  }

  // postprocess complete a postprocessing block and return a Map which will be the final inference result
  // the input to postprocess is the postprocessing block, the raw outputs map (source tensors), and the final result map
  Future<dynamic> postprocess(
    Map<String, dynamic> rawOutputs,
    int postprocessBlockIndex,
  ) async {
    debugPrint("Starting postprocessing...");

    // declare some variables to make things easier
    ProcessingBlock block =
        modelPipeline!.postprocessing[postprocessBlockIndex];
    String outputName = block.output_name;
    // declare a variable to track the current output
    dynamic currentResult = rawOutputs[block.source_tensors[0]];
    String interpretation = block.interpretation.toString().toLowerCase();

    debugPrint("Checking if the postprocessing block contains steps...");
    // make sure pipeline includes postprocessing steps? if it doesn't, skip all of this and return rawInput
    if (modelPipeline!.postprocessing.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          "Pipeline is missing postprocessing blocks, returning raw output unchanged.",
        );
      }
      return currentResult;
    }

    debugPrint("Postprocessing block contained steps.");

    debugPrint(
      "Checking if source tensors are present in all postprocessing blocks...",
    );
    // Autoregressive generate blocks produce their own output internally —
    // they don't read from rawOutputs, so skip the source tensor check.
    final bool isAutoregressiveBlock = block.steps.isNotEmpty &&
        block.steps.first.step == 'generate' &&
        (block.steps.first.params['mode'] as String?) == 'autoregressive';

    if (!isAutoregressiveBlock) {
      // check that all source tensors in the postprocessing block are present in the output map
      List<String> sourceTensors = block.source_tensors;
      for (var tensor in sourceTensors) {
        if (!rawOutputs.containsKey(tensor)) {
          if (kDebugMode) {
            debugPrint(
              "Output map does not contain source tensor: $tensor. Aborting postprocessing and returning raw output unchanged.",
            );
          }
          return currentResult;
        }
      }
    }

    debugPrint("Source tensors present in all postprocessing blocks.");

    debugPrint("Executing steps for ${block.output_name}...");
    // start looping through the postprocessing steps
    for (var postStep in block.steps) {
      currentResult = await _performPostprocessingStep(
        currentResult,
        rawOutputs,
        postStep,
      );
      if (currentResult == null && postStep != block.steps.last) {
        throw Exception(
          "Postprocessing block '$outputName', step '${postStep.step}' failed or returned null unexpectedly.",
        );
      }
      debugPrint(
        "Postprocessing step ${postStep.step} completed successfully...",
      );
    }

    if (kDebugMode) {
      debugPrint("Postprocessing complete.");
      developer.log(
        "Inspecting postprocessing result for block ${modelPipeline!.postprocessing[postprocessBlockIndex].output_name}",
      );
      developer.inspect(currentResult);
    }

    debugPrint(
      "Adding result from postprocess block ${modelPipeline!.postprocessing[postprocessBlockIndex].output_name} to the final results map.",
    );
    debugPrint(
      "Mapping postprocessed result to a sealed inference result class for interpretation $interpretation",
    );
    switch (interpretation) {
      case 'classification_logits':
      case 'classification_scores':
      case 'classification_probabilities':
        if (currentResult is List) {
          try {
            return ClassificationResult(
              currentResult.cast<Map<String, dynamic>>(),
            );
          } catch (e) {
            return ErrorResult(
              "Postprocessing for '$outputName' (classification) produced a List, but elements were not Map<String, dynamic>.",
            );
          }
        }
        return ErrorResult(
          "Postprocessing for '$outputName' (classification) did not produce a List. Got ${currentResult.runtimeType}",
        );
      case 'detection_boxes_scores_classes':
        if (currentResult is Map<int, List<Map<String, dynamic>>>) {
          try {
            return ErrorResult("test");
          } catch (e) {
            return ErrorResult(
              "Postprocessing for '$outputName' (detection) produced a Map<int, List<Map<String, dynamic>>> but failed to cast.",
            );
          }
        } else if (currentResult is List &&
            currentResult.isNotEmpty &&
            currentResult.first is Map<int, List<Map<String, dynamic>>>) {
          try {
            return DetectionResult(
              currentResult.first as Map<int, List<Map<String, dynamic>>>,
            );
          } catch (e) {
            return ErrorResult(
              "Postprocessing for '$outputName' (detection) produced a List, but elements were not Map<int, List<Map<String, dynamic>>>.",
            );
          }
        }
        return ErrorResult(
          "Postprocessing for '$outputName' (detection) did not produce a Map<int, List<Map<String, dynamic>>>. Got ${currentResult.runtimeType}",
        );
      case 'text_generation':
        if (currentResult is String) {
          return TextResult(currentResult);
        }
        return ErrorResult(
          "Postprocessing for '$outputName' (text) did not produce a String. Got ${currentResult.runtimeType}",
        );
      default:
        if (kDebugMode)
          debugPrint(
            "InferenceService: Warning: Unknown postprocessing interpretation '$interpretation' for output '$outputName'. Wrapping as GenericDataResult.",
          );
        return GenericDataResult(currentResult);
    }
  }

  // execute a preprocessing step, given the step and the input data
  Future<dynamic> _performPreprocessingStep(
    dynamic inputData,
    ProcessingStep step,
    int preprocessingBlockIndex,
  ) async {
    if (kDebugMode) {
      debugPrint("Executing preprocessing step: ${step.step}");
    }

    switch (step.step) {
      // resizing an image, input is img.Image
      case 'resize_image':
        try {
          // resize image to sizes defined in the model metadata schema (MMS)
          img.Image resizedImage = img.copyResize(
            inputData,
            width: step.params['width'],
            height: step.params['height'],
          );
          return resizedImage;
        } catch (e) {
          if (kDebugMode) {
            debugPrint("Error resizing image: $e");
            debugPrint("Returning input image with size unchanged.");
          }
          return inputData;
        }

      // normalize image, input is either img.Image or U8intList
      case 'normalize':
        debugPrint("Normalizing image...");
        String? method = step.params['method'];
        String normalizeColorSpace = step.params['color_space'] ?? "RGB";

        try {
          debugPrint("Checking input type. Normalization requires U8intList.");
          // check the input type. if it's img.Image, convert to U8intList
          if (inputData.runtimeType == img.Image) {
            try {
              debugPrint("Input data is img.Image, converting to Uint8List...");
              // Convert to RGB bytes
              inputData = imgToBytes(inputData, normalizeColorSpace);
              inputData = Uint8List.fromList(inputData);
              debugPrint("Converted image to Uint8List.");
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Error converting image to bytes: $e');
              }
              throw Exception(
                'Normalization error: Failed to convert image to bytes',
              );
            }
          } else {
            debugPrint("Input data type is ${inputData.runtimeType}");
          }
          var normBytes = Float32List(inputData.length);
          // first try the 'mean_stddev' method, which first normalizes the image pixel between 0 and 1 by dividing by 255,
          // then applies the mean and stddev normalization for each channel. This method requires the mean and stddev parameters
          // to be lists with a length equal to the number of channels in the inputImage
          debugPrint("Executing normalization using the $method method...");
          if (method == "mean_stddev") {
            List mean =
                step.params['mean'] ??
                List.filled(normalizeColorSpace.length, 0.456);
            List stddev =
                step.params['stddev'] ??
                List.filled(normalizeColorSpace.length, 0.224);
            for (var i = 0; i < inputData.length; i += 3) {
              normBytes[i] = ((inputData[i] / 255) - mean[0]) / stddev[0];
              normBytes[i++] = ((inputData[i++] / 255) - mean[1]) / stddev[1];
              normBytes[i++] = ((inputData[i++] / 255) - mean[2]) / stddev[2];
            }
            // final normImage = normBytes.reshape([1, inputImage.width, inputImage.height, inputImage.numChannels]);
            return normBytes;
          }
          // uniform normalization, instead of applying a per-channel norm, apply a singular mean and stddev value to all
          // pixel normalizations
          else if (method == "normalize_uniform") {
            var mean = step.params['mean'] ?? 127.5;
            var stddev = step.params['stddev'] ?? 127.5;
            for (var i = 0; i < inputData.length; i++) {
              normBytes[i] = (inputData[i] - mean) / stddev;
            }
            // final normImage = normBytes.reshape([1, inputImage.width, inputImage.height, inputImage.numChannels]);
            return normBytes;
          }
          // uniform scaling - simply normalize all pixels to be between 0 and 1, based on a given scale_param (usually 255)
          else if (method == "scale_div") {
            var value = step.params['value'] ?? 255.0;
            for (var i = 0; i < inputData.length; i++) {
              normBytes[i] = inputData[i] / value;
            }
            // final normImage = normBytes.reshape([1, inputImage.width, inputImage.height, inputImage.numChannels]);
            return normBytes;
          } else {
            if (kDebugMode) {
              debugPrint("Error normalizing image: Invalid 'method' parameter");
            }
          }
          debugPrint("Normalized image successfully.");
          return inputData; // return input image bytes if normalization didn't take place
        } catch (e) {
          if (kDebugMode) {
            debugPrint("Error normalizing image: $e");
            debugPrint("Returning input unchanged.");
          }
          return inputData;
        }

      // reformat preprocessed data to match input requirements
      case 'format':
        dynamic finalData = inputData;
        String targetDtype = step.params['target_dtype'];
        String inputColorSpace = step.params['color_space'];
        String dataLayout = step.params['data_layout'].toLowerCase();

        // first format data type and color space. supports 2 types of conversions: float32 and uint8
        // color space formatting is done with the imgToBytes helper method
        if (targetDtype == 'float32' && inputData is! Float32List) {
          if (inputData is img.Image) {
            var imageBytes = imgToBytes(inputData, inputColorSpace);
            finalData = Float32List.fromList(
              imageBytes.map((e) => e / 255.0).toList(),
            );
          } else {
            throw Exception("Cannot format unsupported type to float32");
          }
        } else if (targetDtype == 'uint8' && inputData is! Uint8List) {
          if (inputData is img.Image) {
            finalData = imgToBytes(inputData, inputColorSpace);
          } else {
            throw Exception("Cannot format unsupported type to uint8");
          }
        }

        // get finalData shape for further processing
        List<int> finaldataShape;
        debugPrint("finalData runtime type = ${finalData.runtimeType}");
        if (finalData is Float32List || finalData is Uint8List) {
          finaldataShape = [1, finalData.length];
        } else {
          finaldataShape = finalData.shape;
        }

        /*
        // then check data layout (ex: NHWC)
        // if target layout is NHWC, convert to NHWC if not already there, can only take NCHW as input
        if (dataLayout == 'nhwc' && !isNHWC(inputData.shape)) {
          if (isNCHW(inputData.shape)) {
            finalData = nchwToNhwc(inputData);
          }
          else {
            throw Exception("Only NCHW layouts can be converted to NHWC.");
          }
        }
        // if target layout is NCHW, convert to NCHW if not already there, can only take NHWC as input
        if (dataLayout == 'nchw' && !isNCHW(inputData.shape)) {
          if (isNHWC(inputData.shape)) {
            finalData = nhwcToNchw(inputData);
          }
          else {
            throw Exception("Only NHWC layouts can be converted to NCHW.");
          }
        }
        */

        // lastly, check that the shape is identical to the shape parameter of the input object
        List<int> targetInputShape = [];
        String preprocessingBlockInputName =
            modelPipeline!.preprocessing[preprocessingBlockIndex].input_name;
        for (var inputs in modelPipeline!.inputs) {
          if (inputs.name == preprocessingBlockInputName) {
            targetInputShape = inputs.shape;
            break;
          }
        }

        if (finaldataShape != targetInputShape) {
          if (kDebugMode) {
            debugPrint(
              "Final formatted data shape $finaldataShape does not match target input shape $targetInputShape",
            );
            debugPrint(
              "Attempting to convert final data to target input shape",
            );
          }

          try {
            switch (targetDtype.toLowerCase()) {
              case 'float32':
                return (finalData as Float32List).reshape(targetInputShape);
              //case 'uint8':
              //  return (finalData as Uint8List).reshape(targetInputShape);
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                "Reshape error: $e. Input shape: $finaldataShape, Target shape: $targetInputShape",
              );
            }
            return finalData;
          }
        }

        return finalData;

      // tokenize text input to a tensor of token IDs
      case 'tokenize':
        if (_tokenizer == null) {
          throw StateError(
            "Preprocessing step 'tokenize' requires a tokenizer, but none was loaded. "
            "Ensure the model has a tokenizer.json or vocab.txt asset.",
          );
        }
        if (inputData is! String) {
          throw ArgumentError(
            "Step 'tokenize' expects a String input, got ${inputData.runtimeType}.",
          );
        }
        final int paramMaxLength = (step.params['max_length'] as num?)?.toInt() ?? 512;
        // Use the interpreter's actual input tensor shape — the pipeline-declared
        // max_length may have been incorrectly generated (e.g. from n_ctx in config.json
        // rather than the TFLite model's baked-in positional embedding size).
        final int maxLength = _getModelInputSeqLen(fallback: paramMaxLength);
        if (kDebugMode && maxLength != paramMaxLength) {
          debugPrint('[InferenceService] tokenize: pipeline max_length=$paramMaxLength overridden by actual model input shape=$maxLength.');
        }
        final bool padding = step.params['padding'] as bool? ?? true;
        final bool truncation = step.params['truncation'] as bool? ?? true;
        final bool addSpecialTokens = step.params['add_special_tokens'] as bool? ?? true;

        final List<int> tokenIds = _tokenizer!.encode(
          inputData,
          maxLength: maxLength,
          padding: padding,
          truncation: truncation,
          addSpecialTokens: addSpecialTokens,
        );
        if (kDebugMode) {
          debugPrint('[InferenceService] Tokenized to ${tokenIds.length} token IDs.');
        }
        // Wrap in an outer list to match shape [1, sequenceLength]
        return [tokenIds];

      default:
        if (kDebugMode) {
          debugPrint("Warning: Unsupported preprocessing step: ${step.step}");
        }
        return inputData;
    }
  }

  // perform inference given inputs and target output buffers
  // order of inferenceInputs will be mapped directly to the order of the pipeline inputs, so they must match
  // on the Flutter screen implementation
  // inferenceInputs is map keyed by the input name, so that the given input
  Future<Map<String, InferenceResult>> performInference(
    Map<String, dynamic> inferenceInputs,
  ) async {
    // check that the inputs provided match the inputs expected based on the pipeline file
    if (inferenceInputs.length != modelPipeline!.inputs.length) {
      throw ArgumentError(
        "Provided number of inputs (${inferenceInputs.length}) and expected number of inputs ($modelPipeline!.inputs.length}) do not match, cannot proceed with inference.",
      );
    }

    // preprocess inputs and construct the final input list for inference
    _lastPreprocessedInputs = {};
    List<Object> processedInputs = [];
    for (var input in inferenceInputs.entries) {
      var tempInput = input.value;
      // check if a preprocessing step exists for the given input
      for (var preprocessBlock in modelPipeline!.preprocessing) {
        if (input.key == preprocessBlock.input_name) {
          tempInput = await preprocess(input.value, input.key);
        }
        break;
      }
      // store for use by the autoregressive generate step
      _lastPreprocessedInputs[input.key] = tempInput;
      // add input to the final processInputs list
      processedInputs.add(tempInput);
    }

    // Create output buffers for EVERY model output tensor.
    // tflite_flutter's runForMultipleInputs asserts outputs[i] != null for all
    // interpreter tensors, so we must cover any extra tensors beyond the pipeline.
    List<IO> outputs = modelPipeline!.outputs;

    // Skip the initial inference pass for autoregressive pipelines — the
    // 'generate' postprocessing step runs its own loop from _lastPreprocessedInputs
    // and ignores this output entirely, so running it here is wasted work.
    final bool isAutoregressive = modelPipeline!.postprocessing.any(
      (block) => block.steps.any((s) => s.step == 'generate' && (s.params['mode'] as String?) == 'autoregressive'),
    );

    Map<String, dynamic> inferenceOutputs = {};
    if (!isAutoregressive) {
      Map<int, Object> outputBuffers = _buildOutputBuffers(outputs);
      if (kDebugMode) {
        debugPrint("Running inference on model.");
      }
      _interpreter?.runForMultipleInputs(processedInputs, outputBuffers);
      debugPrint("Inference completed.");
      if (kDebugMode) {
        developer.log("Inspecting outputBuffers variable from the TFLite inference.");
        developer.inspect(outputBuffers);
      }
      for (int i = 0; i < outputs.length; i++) {
        inferenceOutputs[outputs[i].name] = outputBuffers[i];
      }
    } else {
      if (kDebugMode) {
        debugPrint("Autoregressive pipeline — skipping initial inference pass.");
      }
    }

    // define the final results map, which will contain the final output from the model inference
    // the map is keyed by each postprocessing block's name and final output
    Map<String, InferenceResult> finalResults = {};

    // check if any postprocessing blocks exist
    if (modelPipeline!.postprocessing.isNotEmpty) {
      // loop through the postprocessing blocks and run the postprocess method
      for (int i = 0; i < modelPipeline!.postprocessing.length; i++) {
        String blockName = modelPipeline!.postprocessing[i].output_name;
        finalResults[blockName] = await postprocess(inferenceOutputs, i);
        if (kDebugMode) {
          debugPrint(
            "Postprocessing block ${modelPipeline!.postprocessing[i].output_name} completed.",
          );
        }
      }
    } else {
      if (kDebugMode) {
        debugPrint(
          "No postprocessing blocks found in pipeline, returning raw output.",
        );
      }
      finalResults = inferenceOutputs.map(
        (key, value) => MapEntry(key, GenericDataResult(value)),
      );
    }

    if (kDebugMode) {
      developer.log(
        "Postprocessing complete, inspecting the finalResults output...",
      );
      developer.inspect(finalResults);
    }

    // return the final results map
    return finalResults;
  }

  // method to dispose of the inference objects from memory
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    modelPipeline = null;
    if (kDebugMode) {
      debugPrint("Inference Object disposed.");
    }
  }

  /// Converts a tflite_flutter [TensorType] to the dtype string used by the pipeline schema.
  String _tensorTypeToDtype(TensorType type) {
    switch (type) {
      case TensorType.float32: return 'float32';
      case TensorType.int32:   return 'int32';
      case TensorType.uint8:   return 'uint8';
      case TensorType.int8:    return 'int8';
      default:                 return 'float32';
    }
  }

  /// Builds the output buffer map for [runForMultipleInputs].
  ///
  /// tflite_flutter iterates over ALL interpreter output tensors and asserts
  /// each map entry is non-null. If the pipeline declares fewer outputs than
  /// the model has, the missing indices would crash with a null check error.
  /// This method creates a buffer for every actual output tensor.
  Map<int, Object> _buildOutputBuffers(List<IO> pipelineOutputs) {
    final actualTensors = _interpreter!.getOutputTensors();
    final buffers = <int, Object>{};
    for (int i = 0; i < actualTensors.length; i++) {
      final List<int> shape;
      final String dtype;
      if (i < pipelineOutputs.length) {
        shape = _getActualOutputShape(i, pipelineOutputs[i].shape);
        dtype = pipelineOutputs[i].dtype;
      } else {
        // Extra model output not declared in the pipeline — infer from the tensor.
        shape = List<int>.from(actualTensors[i].shape);
        dtype = _tensorTypeToDtype(actualTensors[i].type);
      }
      buffers[i] = _createOutputBuffer(shape, dtype);
    }
    return buffers;
  }

  // helper method to create an output buffer, given an output shape and data type
  dynamic _createOutputBuffer(List<int> shape, String dtype) {
    int totalElements = shape.reduce((a, b) => a * b);
    switch (dtype.toLowerCase()) {
      case 'float32':
        return ListShape(List.filled(totalElements, 0.0)).reshape(shape);
      case 'uint8':
      case 'int8':
        return ListShape(List.filled(totalElements, 0)).reshape(shape);
      case 'int32':
        // TFLite Flutter represents int32 tensors as List<int>
        return ListShape(List.filled(totalElements, 0)).reshape(shape);
      default:
        throw Exception("Unsupported output dtype: $dtype");
    }
  }

  // perform a postprocessing step, given a postprocessing block step object
  Future<dynamic> _performPostprocessingStep(
    dynamic processedOutput,
    Map<String, dynamic> outputTensors,
    ProcessingStep step,
  ) async {
    if (kDebugMode) {
      debugPrint("Executing postprocessing step: ${step.step}");
    }

    switch (step.step.toLowerCase()) {
      // applies an activation function to a list of values
      case 'apply_activation':
        // check that the current processed data is a List
        if (processedOutput is! List) {
          throw FormatException(
            "Processed output is not a List, cannot apply activation function.",
          );
        }
        // run activation function on input data based on function name
        String function = step.params["function"];
        switch (function) {
          case 'softmax':
            processedOutput = applySoftmax(processedOutput);
          //case 'sigmoid':
          //  return processedOutput.map((x) => 1 / (1 + Math.exp(-x))).toList();
          //case 'relu':
          //  return processedOutput.map((x) => x < 0 ? 0 : x).toList();
          default:
            if (kDebugMode) {
              debugPrint(
                "Warning: Unsupported activation function: $function, returning input data unchanged.",
              );
            }
        }

        if (kDebugMode) {
          debugPrint("Finished ${step.step} postprocessing step.");
          developer.log(
            "Inspecting ${step.step} postprocessing output:n processedOutput",
          );
          developer.inspect(processedOutput);
        }

      // map raw or activated outputs to a set of labels for classification
      case 'map_labels':
        // check that labels are loaded
        if (_labels == null) {
          debugPrint("Labels not loaded, cannot map labels to output.");
          return processedOutput;
        }

        // check whether task is classification or object detection
        // image classification map_labels takes a List of floats as input
        // object detection map_labels takes a Map<int, List<Map<String, dynamic>>>

        if (processedOutput is Map) {
          debugPrint("Mapping labels assuming object detection task.");

          // grabbing detection class index tensor for label mapping
          String detectionClassTensorName = step.params['class_tensor'];
          dynamic detectionClassTensor =
              outputTensors[detectionClassTensorName];
          if (kDebugMode) {
            developer.log("Inspecting detection class tensor...");
            developer.inspect(detectionClassTensor);
          }

          // loop through detection batches
          for (int i = 0; i < processedOutput.length; i++) {
            int detectionCount = 1;
            // loop through detections
            for (var detectionMap in processedOutput[i]!) {
              debugPrint(
                "Mapping label ${_labels?[detectionMap['original_index']]} to detection $detectionCount",
              );
              detectionMap['label'] =
                  _labels?[detectionClassTensor[0][detectionMap['original_index']]
                      .toInt()];
              detectionCount++;
            }
          }
        } else if (processedOutput is List) {
          debugPrint("Mapping labels assuming image classification task");
          // create recognitions, which is a list of labels mapped to a value in the raw output tensor
          List<Map<String, dynamic>> recognitions = [];
          // declare tempOutput
          List<dynamic> tempOutput = [];
          // grabbing classification class index tensor for label mapping
          String classTensorName = step.params['class_tensor'];
          dynamic classTensor = outputTensors[classTensorName];
          if (kDebugMode) {
            developer.log("Inspecting classification class tensor...");
            developer.inspect(classTensor);
          }
          // check if processedOutput is a nested list
          debugPrint(
            "Checking if processedOutput type = ${processedOutput.runtimeType} is a nested list.",
          );
          if (isNestedList(processedOutput)) {
            debugPrint("Flattening processedOutput nested List.");
            List<dynamic> flattenedProcessedOutput =
                processedOutput.expand((x) => x).toList();
            tempOutput = flattenedProcessedOutput;
          } else {
            tempOutput = processedOutput;
          }
          debugPrint(
            "Map label debug message: tempOutput type = ${tempOutput.runtimeType}",
          );
          for (int i = 0; i < tempOutput.length; i++) {
            recognitions.add({
              "index": i,
              "label": _labels![i],
              "confidence": tempOutput[i],
            });
          }
          // set the processed output to the recognition list
          processedOutput = recognitions;
          // filters object detections by some threshold
          // expects a tensor, or a List<dynamic> in Dart
        }
        if (kDebugMode) {
          debugPrint("Finished ${step.step} postprocessing step.");
          developer.log(
            "Inspecting ${step.step} postprocessing output: processedOutput",
          );
          developer.inspect(processedOutput);
        }

      // filters object detections by some threshold
      // expects a tensor, or a List<dynamic> in Dart
      case 'filter_by_score':
        // find raw output using score_tensor param
        String scoreTensorName = step.params['score_tensor'];
        scoreTensor = outputTensors[scoreTensorName];
        String numDetectionsTensorName = step.params['num_detections_tensor'];
        dynamic numDetectionsTensor = outputTensors[numDetectionsTensorName];
        final int numDetections =
            (numDetectionsTensor is List
                    ? numDetectionsTensor[0] as num
                    : numDetectionsTensor as num)
                .toInt();

        // set threshold according to YAML file, default to 0.5 if none found
        double threshold =
            (step.params['threshold'] as num?)?.toDouble() ?? 0.5;
        Map<int, List<int>> filteredDetectionIndices = {};
        debugPrint(
          "Filtering ${scoreTensor[0].length} detections with threshold $threshold...",
        );

        // loop through each batch of score tensors
        for (int i = 0; i < scoreTensor.length; i++) {
          filteredDetectionIndices[i] =
              <int>[]; // Initialize the list for each batch
          for (int j = 0; j < numDetections; j++) {
            debugPrint("scoreTensor[$i][$j] = ${scoreTensor[i][j]}");
            debugPrint("threshold = $threshold");
            debugPrint(
              "scoreTensor[$i][$j] > threshold = ${scoreTensor[i][j] > threshold}",
            );
            if (scoreTensor[i][j] > threshold) {
              filteredDetectionIndices[i]!.add(j);
            }
          }
        }

        debugPrint(
          "InferenceService: Filtered ${filteredDetectionIndices[0]!.length} detections above threshold $threshold",
        );
        if (kDebugMode) {
          developer.log(
            "Inspecting ${step.step} postprocessing variable: filteredDetectionIndices",
          );
          developer.inspect(filteredDetectionIndices);
        }
        // This step's output (filteredIndices) becomes processedData for the next step.
        processedOutput = filteredDetectionIndices;

        if (kDebugMode) {
          debugPrint("Finished ${step.step} postprocessing step.");
          developer.log(
            "Inspecting ${step.step} postprocessing output: processedOutput",
          );
          developer.inspect(processedOutput);
        }

      // uses filtered indices and later on the coordinate format config to construct the final detection tensors
      // expected a Map of filtered indices as input, from 'filter_by_score'
      case 'decode_boxes':
        // Expects processedOutput (from previous step) to be the list of filtered indices
        if (processedOutput is! Map<int, List<int>>) {
          throw FormatException(
            "Step 'decode_boxes' expects Map<int, List<int>> (filtered indices) input. Got ${processedOutput.runtimeType}",
          );
        }
        final params = step.params;
        final boxTensorName = params['box_tensor'] as String?;
        if (boxTensorName == null ||
            !outputTensors.containsKey(boxTensorName)) {
          throw Exception(
            "decode_boxes requires a valid 'box_tensor' param pointing to a raw output.",
          );
        }
        // define raw box Map, generalizing for multiple batch detection box tensors
        final Map<int, List<List<dynamic>>> boxesRaw = {};
        debugPrint("Building boxesRaw map...");
        for (int i = 0; i < outputTensors[boxTensorName].length; i++) {
          boxesRaw[i] = outputTensors[boxTensorName][i];
        }
        debugPrint("BoxesRaw map built successfully. \n $boxesRaw");
        debugPrint("Starting box decoding...");
        Map<int, List<Map<String, dynamic>>> decodedData = {};
        for (int i = 0; i < processedOutput.length; i++) {
          debugPrint("Decoding boxes for batch $i...");
          decodedData[i] = []; // Initialize the list for each batch
          for (int index in processedOutput[i]!) {
            debugPrint("Decoding box $index for batch $i...");
            if (index < boxesRaw[i]!.length) {
              // initialize the map for each detection
              // Convert box coordinates to double
              final box =
                  boxesRaw[i]?[index]
                      .map((val) => (val as num).toDouble())
                      .toList();
              if (box?.length == 4) {
                // Basic validation
                debugPrint("Adding box coordinates: $box");
                decodedData[i]!.add({
                  "original_index":
                      index, // Preserve original index for later mapping
                  "score": scoreTensor[i]?[index],
                  "raw_box":
                      box, // Pass raw normalized box [ymin, xmin, ymax, xmax] or other format
                });
              } else {
                debugPrint(
                  "InferenceService: Warning: Box at index $index does not have 4 coordinates in decode_boxes.",
                );
              }
            } else {
              debugPrint(
                "InferenceService: Warning: Index $index out of bounds for boxesRaw (length ${boxesRaw.length}) in decode_boxes.",
              );
            }
          }
        }

        if (kDebugMode) {
          developer.log(
            "Inspecting ${step.step} postprocessing variable: decodedData",
          );
          developer.inspect(decodedData);
        }
        // This map of a list of maps becomes processedData for the next step
        processedOutput = decodedData;

        if (kDebugMode) {
          debugPrint("Finished ${step.step} postprocessing step.");
          developer.log(
            "Inspecting ${step.step} postprocessing output: processedOutput",
          );
          developer.inspect(processedOutput);
        }

      // autoregressive decode loop or single-pass pass-through
      case 'generate':
        final String mode = step.params['mode'] as String? ?? 'single_pass';
        if (mode == 'single_pass') {
          // Single-pass: model already ran, output tensor is the token ID sequence.
          // Nothing to do here — decode_tokens handles the rest.
          break;
        }

        // Autoregressive: run the model in a loop, appending one token at a time.
        if (_interpreter == null || modelPipeline == null) {
          throw StateError("Cannot run autoregressive generation: interpreter not ready.");
        }
        if (_tokenizer == null) {
          throw StateError("Cannot run autoregressive generation: tokenizer not loaded.");
        }

        final int maxNewTokens = (step.params['max_new_tokens'] as num?)?.toInt() ?? 128;
        final double temperature = (step.params['temperature'] as num?)?.toDouble() ?? 0.8;
        final bool doSample = step.params['do_sample'] as bool? ?? true;
        final int? eosTokenId = (step.params['eos_token_id'] as num?)?.toInt();
        final double repetitionPenalty = (step.params['repetition_penalty'] as num?)?.toDouble() ?? 1.3;

        // Get initial token IDs from the preprocessed input (first text input).
        // _lastPreprocessedInputs is keyed by input tensor name; value is [List<int>].
        List<int> currentIds = [];
        for (final entry in _lastPreprocessedInputs.entries) {
          final val = entry.value;
          if (val is List && val.isNotEmpty && val.first is List) {
            currentIds = List<int>.from((val.first as List).map((e) => (e as num).toInt()));
          } else if (val is List<int>) {
            currentIds = List<int>.from(val);
          }
          if (currentIds.isNotEmpty) break;
        }

        if (currentIds.isEmpty) {
          throw StateError("Autoregressive generation: could not extract input token IDs.");
        }

        // Trim padding from initial input before generating
        final int padId = _tokenizer!.padId;
        currentIds = currentIds.where((id) => id != padId).toList();

        final int expectedSeqLen = _getModelInputSeqLen(fallback: currentIds.length);

        if (kDebugMode) {
          debugPrint('[Generate] Dispatching to background isolate: '
              'promptLen=${currentIds.length}, maxNewTokens=$maxNewTokens, '
              'eosId=$eosTokenId, padId=$padId, seqLen=$expectedSeqLen');
          debugPrint('[Generate] Prompt decoded: "${_tokenizer!.decode(currentIds, skipSpecialTokens: false)}"');
        }

        if (!isLocalFile) {
          throw StateError(
            'Autoregressive generation requires a local model file. '
            'Asset-bundled models are not supported for autoregressive text generation.',
          );
        }

        // Run the generate loop in a background Dart isolate so the main
        // thread — and Flutter's rendering loop — are never blocked.
        final List<int> generatedTokens = await compute(
          _runGenerateIsolate,
          _GenerateRequest(
            modelPath: modelPath,
            inputIds: currentIds,
            seqLen: expectedSeqLen,
            padId: padId,
            eosTokenId: eosTokenId,
            maxNewTokens: maxNewTokens,
            temperature: temperature,
            doSample: doSample,
            repetitionPenalty: repetitionPenalty,
          ),
        );

        processedOutput = generatedTokens;
        if (kDebugMode) {
          debugPrint('[Generate] Done: ${generatedTokens.length} tokens. '
              'First 20 IDs: ${generatedTokens.take(20).toList()}');
        }

      // decode a list of token IDs back to a string
      case 'decode_tokens':
        if (_tokenizer == null) {
          throw StateError(
            "Postprocessing step 'decode_tokens' requires a tokenizer, but none was loaded.",
          );
        }
        final bool skipSpecial = step.params['skip_special_tokens'] as bool? ?? true;

        // Flatten nested lists to a flat List<int>
        List<int> ids = _flattenToIntList(processedOutput);
        processedOutput = _tokenizer!.decode(ids, skipSpecialTokens: skipSpecial);

        if (kDebugMode) {
          debugPrint("[InferenceService] Decoded ${ids.length} token IDs to text.");
        }

      default:
        if (kDebugMode) {
          debugPrint("Warning: Unsupported postprocessing step: ${step.step}");
        }
    }

    return processedOutput;
  }

  /// Returns the actual output tensor shape from the TFLite interpreter for [index].
  /// Falls back to [fallbackShape] if the interpreter is unavailable.
  List<int> _getActualOutputShape(int index, List<int> fallbackShape) {
    if (_interpreter != null) {
      try {
        final tensors = _interpreter!.getOutputTensors();
        if (index < tensors.length) {
          return List<int>.from(tensors[index].shape);
        }
      } catch (_) {}
    }
    return fallbackShape;
  }

  /// Returns the actual input sequence length from the TFLite interpreter.
  /// Falls back to the pipeline-declared shape, then to [fallback].
  int _getModelInputSeqLen({int fallback = 512}) {
    if (_interpreter != null) {
      try {
        final tensors = _interpreter!.getInputTensors();
        if (tensors.isNotEmpty && tensors[0].shape.length >= 2) {
          return tensors[0].shape[1];
        }
      } catch (_) {}
    }
    if (modelPipeline != null &&
        modelPipeline!.inputs.isNotEmpty &&
        modelPipeline!.inputs[0].shape.length >= 2) {
      return modelPipeline!.inputs[0].shape[1];
    }
    return fallback;
  }

  // Flatten any nested list structure to a flat List<int>
  List<int> _flattenToIntList(dynamic value) {
    if (value is List<int>) return value;
    if (value is List) {
      final result = <int>[];
      for (final item in value) {
        result.addAll(_flattenToIntList(item));
      }
      return result;
    }
    if (value is num) return [value.toInt()];
    return [];
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate support for autoregressive generation
// ─────────────────────────────────────────────────────────────────────────────

/// All data needed to run the generate loop in a background isolate.
/// Only sendable types (primitives + integer lists) so it can cross isolate boundaries.
class _GenerateRequest {
  final String modelPath;
  final List<int> inputIds;
  final int seqLen;
  final int padId;
  final int? eosTokenId;
  final int maxNewTokens;
  final double temperature;
  final bool doSample;
  final double repetitionPenalty;

  const _GenerateRequest({
    required this.modelPath,
    required this.inputIds,
    required this.seqLen,
    required this.padId,
    this.eosTokenId,
    required this.maxNewTokens,
    required this.temperature,
    required this.doSample,
    required this.repetitionPenalty,
  });
}

/// Top-level function executed by [compute()].
///
/// Creates a fresh Interpreter inside the background isolate — native objects
/// cannot be shared across isolate boundaries. Runs the full autoregressive
/// loop, closes the interpreter, and returns the generated token IDs.
List<int> _runGenerateIsolate(_GenerateRequest req) {
  // Bounded exp helper — avoids float overflow in softmax.
  double boundedExp(double x) {
    if (x > 88) return 1.5e38;
    if (x < -88) return 0.0;
    return math.exp(x);
  }

  // Build output buffers from the interpreter's actual tensor metadata.
  Map<int, Object> buildBuffers(Interpreter interp) {
    final tensors = interp.getOutputTensors();
    final buffers = <int, Object>{};
    for (int i = 0; i < tensors.length; i++) {
      final shape = List<int>.from(tensors[i].shape);
      final total = shape.reduce((a, b) => a * b);
      buffers[i] = tensors[i].type == TensorType.float32
          ? ListShape(List<double>.filled(total, 0.0)).reshape(shape)
          : ListShape(List<int>.filled(total, 0)).reshape(shape);
    }
    return buffers;
  }

  final options = InterpreterOptions()..threads = 4;
  final interpreter = Interpreter.fromFile(File(req.modelPath), options: options);

  List<int> currentIds = List<int>.from(req.inputIds);
  final List<int> generatedTokens = [];

  for (int step = 0; step < req.maxNewTokens; step++) {
    // Sliding window: keep the most recent seqLen tokens.
    final List<int> contextIds = currentIds.length > req.seqLen
        ? currentIds.sublist(currentIds.length - req.seqLen)
        : currentIds;

    // Right-pad so real tokens are at the front; causal attention means pad
    // positions at the back cannot influence earlier positions' outputs.
    final List<int> paddedIds = contextIds.length < req.seqLen
        ? [...contextIds, ...List.filled(req.seqLen - contextIds.length, req.padId)]
        : List<int>.from(contextIds);

    final Map<int, Object> buffers = buildBuffers(interpreter);
    interpreter.runForMultipleInputs([[paddedIds]], buffers);

    // logits shape: [1, seqLen, vocabSize] or [1, vocabSize]
    final dynamic raw = buffers[0];
    final int lastRealPos = contextIds.length - 1;
    List<dynamic> lastLogits;
    if (raw is List && raw.isNotEmpty) {
      final batch = raw[0] as List;
      lastLogits = (batch.isNotEmpty && batch[0] is List)
          ? batch[lastRealPos] as List<dynamic>
          : batch.cast<dynamic>();
    } else {
      break;
    }

    // Repetition penalty (HuggingFace convention).
    List<double> logits = lastLogits.map((v) => (v as num).toDouble()).toList();
    if (req.repetitionPenalty != 1.0) {
      final seen = <int>{...currentIds, ...generatedTokens};
      for (final id in seen) {
        if (id >= 0 && id < logits.length) {
          logits[id] = logits[id] > 0
              ? logits[id] / req.repetitionPenalty
              : logits[id] * req.repetitionPenalty;
        }
      }
    }

    // Greedy argmax or temperature sampling.
    int nextToken;
    if (!req.doSample || req.temperature <= 0.0) {
      nextToken = 0;
      double best = logits[0];
      for (int i = 1; i < logits.length; i++) {
        if (logits[i] > best) { best = logits[i]; nextToken = i; }
      }
    } else {
      final scaled = logits.map((v) => v / req.temperature).toList();
      final maxVal = scaled.reduce((a, b) => a > b ? a : b);
      final exps = scaled.map((v) => boundedExp(v - maxVal)).toList();
      final sum = exps.reduce((a, b) => a + b);
      final probs = exps.map((v) => v / sum).toList();
      double r = math.Random().nextDouble();
      nextToken = probs.length - 1;
      for (int i = 0; i < probs.length; i++) {
        r -= probs[i];
        if (r <= 0) { nextToken = i; break; }
      }
    }

    generatedTokens.add(nextToken);
    if (req.eosTokenId != null && nextToken == req.eosTokenId) break;
    currentIds = [...currentIds, nextToken];
  }

  interpreter.close();
  return generatedTokens;
}











/* 
class imagePreprocessing {
  final String step;
  const imagePreprocessing({required this.step,});

  preprocessImage(img.Image image, Map metadata) {
    var preprocessingPhases = metadata['preprocessing'];
    int phase_count = 0;
    for (var phase in preprocessingPhases) {
      int step_count = 0;
      for (var step in phase['steps']) {
        if (step['step'] == 'resize_image') {
            image = resizeImage(image, step['params']['width'], step['params']['height']);
        }
        else if (step['step'] == 'normalize') {
          var imageBytes = image.getBytes(order: img.ChannelOrder.rgb);
          imageBytes = normalizeImage(imageBytes, step['params']['method']);
        }
        else if (step['step'] == 'format') {
          var imageBytes = image.getBytes(order: img.ChannelOrder.rgb);
          normalizeImage(imageBytes, step['params']['method']);
        }
      }
    }

  }


  // method to resize an image
  // takes a decoded image as input
  img.Image resizeImage(img.Image inputImage, int inputWidth, int inputHeight) {
    try {
      // resize image to sizes defined in the model metadata schema (MMS)
      img.Image resizedImage = img.copyResize(inputImage, width: inputWidth, height: inputHeight);
      return resizedImage;
    }
    catch (e) {
      if (kDebugMode) {
        debugPrint("Error resizing image: $e");
        debugPrint("Returning input image with size unchanged.");
      }
      return inputImage;
    }
  }

  // method to normalize an image
  // takes a decoded image represented as bytes as input
  // valid normalization methods are "mean_stddev", "normalize_uniform", "scale_uniform"
  // outputs a normalized float 32 list
  List<dynamic> normalizeImage(List<dynamic> inputImageBytes, String method, 
                                {List<double>? mean = const [0.485, 0.456, 0.406], 
                                List<double>? stddev = const [0.229, 0.224, 0.225], 
                                double? scaleParam = 255.0}) {
    try {
      // var imageBytes = inputImage.getBytes(order: img.ChannelOrder.rgb);
      var normBytes = Float32List(inputImageBytes.length);
      // first try the 'mean_stddev' method, which first normalizes the image pixel between 0 and 1 by dividing by 255,
      // then applies the mean and stddev normalization for each channel. This method requires the mean and stddev parameters 
      // to be lists with a length equal to the number of channels in the inputImage
      if (method == "mean_stddev") {
        for (var i = 0; i < inputImageBytes.length; i += 3) {
          normBytes[i] = ((inputImageBytes[i] / 255) - mean?[0]) / stddev?[0];
          normBytes[i++] = ((inputImageBytes[i++] / 255) - mean?[1]) / stddev?[1];
          normBytes[i++] = ((inputImageBytes[i++] / 255) - mean?[2]) / stddev?[2];
        }
        // final normImage = normBytes.reshape([1, inputImage.width, inputImage.height, inputImage.numChannels]);
        return normBytes;
      }
      // uniform normalization, instead of applying a per-channel norm, apply a singular mean and stddev value to all
      // pixel normalizations
      else if (method == "normalize_uniform") {
        for (var i = 0; i < inputImageBytes.length; i += 3) {
          normBytes[i] = (inputImageBytes[i] - mean?[0]) / stddev?[0];
          normBytes[i++] = (inputImageBytes[i++] - mean?[0]) / stddev?[0];
          normBytes[i++] = (inputImageBytes[i++] - mean?[0]) / stddev?[0];
        }
        // final normImage = normBytes.reshape([1, inputImage.width, inputImage.height, inputImage.numChannels]);
        return normBytes;
      }
      // uniform scaling - simply normalize all pixels to be between 0 and 1, based on a given scale_param (usually 255)
      else if (method == "normalize_uniform") {
        for (var i = 0; i < inputImageBytes.length; i += 3) {
          normBytes[i] = inputImageBytes[i] / scaleParam;
          normBytes[i++] = inputImageBytes[i++] / scaleParam;
          normBytes[i++] = inputImageBytes[i++] / scaleParam;
        }
        // final normImage = normBytes.reshape([1, inputImage.width, inputImage.height, inputImage.numChannels]);
        return normBytes;
      }
      else {
        if (kDebugMode) {
          debugPrint("Error normalizing image: Invalid 'method' parameter");
        }
      }
      return inputImageBytes; // return input image bytes if normalization didn't take place
    }
    catch (e) {
      if (kDebugMode) {
        debugPrint("Error resizing image: $e");
        debugPrint("Returning input image with size unchanged.");
      }
      return inputImageBytes;
    }
  }


  /// Converts a Float32List from NHWC format to NCHW format
  /// Parameters:
  ///   input: Float32List in NHWC format
  ///   height: height of the image
  ///   width: width of the image
  ///   channels: number of channels (typically 3 for RGB)
  Float32List nhwcToNchw(Float32List input, int height, int width, int channels) {
    final int batchSize = input.length ~/ (height * width * channels);
    var output = Float32List(input.length);
    
    for (int b = 0; b < batchSize; b++) {
      for (int h = 0; h < height; h++) {
        for (int w = 0; w < width; w++) {
          for (int c = 0; c < channels; c++) {
            // Convert from NHWC [b, h, w, c] to NCHW [b, c, h, w]
            final nhwcIndex = b * height * width * channels + 
                            h * width * channels + 
                            w * channels + 
                            c;
            
            final nchwIndex = b * channels * height * width + 
                            c * height * width + 
                            h * width + 
                            w;
                            
            output[nchwIndex] = input[nhwcIndex];
          }
        }
      }
    }
    
    return output;
  }


  // format image to 

} */