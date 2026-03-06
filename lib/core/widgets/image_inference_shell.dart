import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shared scaffold for every image-based inference screen.
///
/// Handles:
///   - Model init state (loading spinner / error) via [initFuture]
///   - Gallery and Camera picker buttons
///   - Full-screen "Running model…" overlay while [isRunning]
///
/// The caller supplies:
///   - [imageArea]  — the image display widget (with any task-specific overlay)
///   - [results]    — task-specific result content shown below the buttons
///   - [onImagePicked] — called with the chosen [ImageSource]
class ImageInferenceShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: initFuture,
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
          appBar: AppBar(title: Text(title)),
          body: Stack(
            children: [
              SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        imageArea,
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Gallery'),
                              onPressed: isRunning
                                  ? null
                                  : () => onImagePicked(ImageSource.gallery),
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Camera'),
                              onPressed: isRunning
                                  ? null
                                  : () => onImagePicked(ImageSource.camera),
                            ),
                          ],
                        ),
                        if (results != null) ...[
                          const SizedBox(height: 20),
                          results!,
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
              if (isRunning)
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
      },
    );
  }
}
