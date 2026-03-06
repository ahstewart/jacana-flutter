import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shared scaffold for every image-based inference screen.
///
/// Handles:
///   - Model init state (loading spinner / error) via [initFuture]
///   - Gallery and Camera picker buttons
///   - Full-screen "Running model…" overlay with elapsed timer while [isRunning]
///
/// The caller supplies:
///   - [imageArea]  — the image display widget (with any task-specific overlay)
///   - [results]    — task-specific result content shown below the buttons
///   - [onImagePicked] — called with the chosen [ImageSource]
class ImageInferenceShell extends StatefulWidget {
  final String title;
  final Future<void> initFuture;
  final bool isRunning;
  final void Function(ImageSource source) onImagePicked;
  final Widget imageArea;
  final Widget? results;

  const ImageInferenceShell({
    super.key,
    required this.title,
    required this.initFuture,
    required this.isRunning,
    required this.onImagePicked,
    required this.imageArea,
    this.results,
  });

  @override
  State<ImageInferenceShell> createState() => _ImageInferenceShellState();
}

class _ImageInferenceShellState extends State<ImageInferenceShell> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  @override
  void didUpdateWidget(ImageInferenceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !oldWidget.isRunning) {
      _stopwatch.reset();
      _stopwatch.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        setState(() {});
      });
    } else if (!widget.isRunning && oldWidget.isRunning) {
      _stopwatch.stop();
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  String get _elapsedLabel {
    final ms = _stopwatch.elapsedMilliseconds;
    if (ms < 60000) {
      return '${(ms / 1000).toStringAsFixed(1)}s';
    }
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: widget.initFuture,
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
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: Stack(
            children: [
              SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        widget.imageArea,
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Gallery'),
                              onPressed: widget.isRunning
                                  ? null
                                  : () => widget.onImagePicked(ImageSource.gallery),
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Camera'),
                              onPressed: widget.isRunning
                                  ? null
                                  : () => widget.onImagePicked(ImageSource.camera),
                            ),
                          ],
                        ),
                        if (widget.results != null) ...[
                          const SizedBox(height: 20),
                          widget.results!,
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.isRunning)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xAA000000),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 16),
                          const Text(
                            'Running model\u2026',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _elapsedLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
