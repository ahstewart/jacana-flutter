import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/data_models/inference_result_model.dart';
import '../../core/services/inferenceService.dart';
import '../../core/services/stats_service.dart';
import '../../core/providers/stats_providers.dart';

class AutomaticSpeechRecognitionWidget extends ConsumerStatefulWidget {
  final String modelName;
  final String pipelinePath;
  final bool isLocalFile;
  final String? localDir;
  final String? modelVersionId;
  final String? modelDisplayName;

  const AutomaticSpeechRecognitionWidget({
    super.key,
    required this.modelName,
    required this.pipelinePath,
    this.isLocalFile = false,
    this.localDir,
    this.modelVersionId,
    this.modelDisplayName,
  });

  @override
  ConsumerState<AutomaticSpeechRecognitionWidget> createState() =>
      _AutomaticSpeechRecognitionWidgetState();
}

class _AutomaticSpeechRecognitionWidgetState
    extends ConsumerState<AutomaticSpeechRecognitionWidget> {
  late final InferenceService _svc;
  late final Future<void> _initFuture;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isRunning = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  final Stopwatch _inferenceWatch = Stopwatch();
  Timer? _inferenceTimer;
  String? _transcription;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _svc = InferenceService(
      modelPath: widget.modelName,
      pipelinePath: widget.pipelinePath,
      isLocalFile: widget.isLocalFile,
      localDir: widget.localDir,
      modelVersionId: widget.modelVersionId,
      modelDisplayName: widget.modelDisplayName,
      statsService: widget.modelVersionId != null ? StatsService() : null,
    );
    _initFuture = _svc.initialize();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _inferenceTimer?.cancel();
    _recorder.dispose();
    _svc.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isRunning) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() => _errorMessage = 'Microphone permission denied.');
      return;
    }

    final dir = await Directory.systemTemp.createTemp('asr_rec_');
    final path = '${dir.path}/recording.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
      _transcription = null;
      _errorMessage = null;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path == null) {
      setState(() => _errorMessage = 'Recording failed — no output file.');
      return;
    }

    final bytes = await File(path).readAsBytes();
    await _runInference(bytes);
  }

  Future<void> _pickAudioFile() async {
    if (_isRecording || _isRunning) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    final bytes = await File(filePath).readAsBytes();
    await _runInference(bytes);
  }

  Future<void> _runInference(Uint8List audioBytes) async {
    if (!_svc.isReady) {
      setState(() => _errorMessage = 'Model not ready yet.');
      return;
    }

    setState(() {
      _isRunning = true;
      _transcription = null;
      _errorMessage = null;
    });

    _inferenceWatch
      ..reset()
      ..start();
    _inferenceTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });

    try {
      // Feed audio bytes to every audio-type input in the pipeline
      final inputMap = <String, dynamic>{};
      for (final input in _svc.modelPipeline!.inputs) {
        inputMap[input.name] = audioBytes;
      }

      final results = await _svc.performInference(inputMap);
      final firstResult = results.values.firstOrNull;

      if (firstResult is SpeechResult) {
        setState(() => _transcription = firstResult.transcription);
      } else if (firstResult is ErrorResult) {
        setState(() => _errorMessage = firstResult.errorMessage);
      } else if (firstResult != null) {
        setState(
          () =>
              _errorMessage =
                  'Unexpected result type: ${firstResult.runtimeType}',
        );
      } else {
        setState(() => _errorMessage = 'No output produced.');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ASR] Inference error: $e');
      setState(() => _errorMessage = 'Error: $e');
    } finally {
      _inferenceWatch.stop();
      _inferenceTimer?.cancel();
      _inferenceTimer = null;
      if (widget.modelVersionId != null) {
        ref
            .read(telemetryServiceProvider)
            .syncIfEligible(
              optedIn: ref.read(telemetryOptInProvider),
              authToken: null,
            )
            .ignore();
      }
      setState(() => _isRunning = false);
    }
  }

  String _formatDuration(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _formatElapsed() {
    final ms = _inferenceWatch.elapsedMilliseconds;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _svc.modelPipeline?.metadata.firstOrNull?.model_name ??
              'Speech Recognition',
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Mic icon
                  Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    size: 80,
                    color:
                        _isRecording ? colorScheme.error : colorScheme.primary,
                  ),
                  const SizedBox(height: 32),
                  // Record / Stop + Upload buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(
                          _isRecording ? Icons.stop : Icons.fiber_manual_record,
                        ),
                        label: Text(_isRecording ? 'Stop' : 'Record'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isRecording
                                  ? colorScheme.error
                                  : colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                        onPressed:
                            _isRunning
                                ? null
                                : (_isRecording
                                    ? _stopRecording
                                    : _startRecording),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Upload'),
                        onPressed:
                            (_isRunning || _isRecording)
                                ? null
                                : _pickAudioFile,
                      ),
                    ],
                  ),
                  // Recording timer
                  if (_isRecording) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Recording: ${_formatDuration(_recordingDuration)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  // Transcription result
                  if (_transcription != null) ...[
                    Text(
                      'Transcription',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: colorScheme.outline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _transcription!,
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Inference overlay
          if (_isRunning)
            ColoredBox(
              color: const Color(0xAA000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      'Transcribing\u2026',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatElapsed(),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
