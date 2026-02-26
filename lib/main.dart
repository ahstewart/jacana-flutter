import 'dart:async';

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

void main() {
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

// Widget containing the model tile list
class Models extends ConsumerWidget {
  const Models({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(supportedModelsProvider);

    return modelsAsync.when(
      data: (modelList) {
        if (modelList.isEmpty) {
          return const Center(child: Text('No supported models available'));
        }

        return Wrap(
          spacing: 16.0,
          runSpacing: 16.0,
          children: [
            for (MLModel model in modelList)
              SizedBox(
                width: 300,
                child: Card(
                  child: ListTile(
                    title: Text(model.name),
                    subtitle: Text(model.category),
                    leading: const Icon(Icons.model_training),
                    onTap: () {
                      ref.read(selectedModelProvider.notifier).state = model;
                      ref.read(selectedIndexProvider.notifier).state = 1;
                    },
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading models: $err')),
    );
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
      return const Center(child: Text('Select a model to view details!'));
    }

    // Fetch versions for the selected model
    final versionsAsync = ref.watch(modelVersionsProvider(selectedModel.id));

    return versionsAsync.when(
      data: (versions) {
        // Filter to only supported versions
        final supportedVersions =
            versions.where((v) => v.is_supported).toList();

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

  const VersionCard({
    required this.version,
    required this.modelName,
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
              'Version: ${version.version_name}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text('Status: ${version.status}'),
            Text('License: ${version.license_type}'),
            Text(
              'File Size: ${(version.file_size_bytes / 1024 / 1024).toStringAsFixed(2)} MB',
            ),
            Text('Downloads: ${version.download_count}'),
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
                    _showDownloadDialog(context, version, modelName);
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
    ModelVersion version,
    String modelName,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Download Model'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Model: $modelName'),
                Text('Version: ${version.version_name}'),
                const SizedBox(height: 12),
                const Text('Download includes:'),
                const SizedBox(height: 8),
                Text('• TFLite Model: ${version.assets.tflite}'),
                if (version.assets.labels != null)
                  Text('• Labels: ${version.assets.labels}'),
                if (version.assets.anchors != null)
                  Text('• Anchors: ${version.assets.anchors}'),
                const SizedBox(height: 12),
                const Text('Pipeline Config:'),
                const SizedBox(height: 8),
                if (version.pipeline_spec != null)
                  Text(
                    '${version.pipeline_spec!.preprocessing.length} preprocessing step(s)\n${version.pipeline_spec!.postprocessing.length} postprocessing step(s)',
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Implement download logic here
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Download started... (To be implemented)'),
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Download'),
              ),
            ],
          ),
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
    pages = [Models(), ModelRange(), Profile()];
  }

  @override
  Widget build(BuildContext context) {
    var _selectedIndex = ref.watch(selectedIndexProvider);
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
            Expanded(child: pages[_selectedIndex]),

            // This is the nav bar
            SafeArea(
              child: NavigationBar(
                destinations: [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.science),
                    label: 'Range',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
                selectedIndex: _selectedIndex,
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
