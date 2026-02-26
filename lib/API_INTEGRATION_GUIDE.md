# Flutter Backend API Integration Guide

## Overview
Your Flutter app now has full backend API integration with the following features:
- ✅ Fetch all models with supported versions
- ✅ Filter to show only models with at least one supported version
- ✅ View model version details including pipeline configuration
- ✅ Download model binaries and assets
- ✅ View pipeline specs (preprocessing/postprocessing steps)

## Configuration

### 1. Set Your Backend URL
In `lib/core/services/api_service.dart`, update the `baseUrl`:

```dart
static const String baseUrl = 'http://localhost:8000'; // Change to your backend URL
```

For production, change to your actual backend server URL (e.g., `https://api.example.com`)

## Architecture

### Data Flow
```
Backend API
    ↓
ApiService (HTTP Client) 
    ↓
Riverpod Providers (State Management)
    ↓
UI Widgets (Models, ModelRange, VersionCard, etc.)
```

### Key Files

#### 1. **Data Models** (`lib/core/data_models/api_models.dart`)
Defines the structure of data from your backend:
- `MLModel` - Top-level model information
- `ModelVersion` - Model version with pipeline config
- `AssetPointers` - URLs to model assets
- `PipelineConfig` - Complete pipeline configuration

#### 2. **API Service** (`lib/core/services/api_service.dart`)
Handles all HTTP requests:
- `getModels()` - Fetch all models
- `getModelVersions(modelId)` - Fetch versions for a model
- `getModelVersion(versionId)` - Fetch specific version details
- `downloadFile(url)` - Download binary files

#### 3. **Riverpod Providers** (`lib/core/providers/model_providers.dart`)
Manages state and data fetching:

**Data Providers:**
- `allModelsProvider` - All models from backend
- `supportedModelsProvider` - Filtered to only supported models
- `modelVersionsProvider(modelId)` - Versions for a model
- `supportedVersionsProvider(modelId)` - Only supported versions

**State Providers:**
- `selectedModelProvider` - Currently selected model
- `selectedModelVersionProvider` - Currently selected version

**Action Providers:**
- `downloadModelFileProvider` - Download model binary
- `downloadAssetFileProvider` - Download asset files

## Usage Examples

### Fetching Models in Your UI
```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final modelsAsync = ref.watch(supportedModelsProvider);
  
  return modelsAsync.when(
    data: (models) {
      // Render your models list
    },
    loading: () => CircularProgressIndicator(),
    error: (err, stack) => Text('Error: $err'),
  );
}
```

### Selecting a Model
```dart
ref.read(selectedModelProvider.notifier).state = model;
```

### Getting Model Versions
```dart
final versionsAsync = ref.watch(modelVersionsProvider(modelId));

versionsAsync.when(
  data: (versions) {
    final supportedOnly = versions.where((v) => v.is_supported).toList();
    // Display versions
  },
  // ...
);
```

### Accessing Pipeline Configuration
```dart
if (version.pipeline_spec != null) {
  final config = version.pipeline_spec!;
  
  // Access components
  config.metadata;      // Model metadata
  config.inputs;        // Input tensor definitions
  config.outputs;       // Output tensor definitions
  config.preprocessing; // Preprocessing blocks
  config.postprocessing; // Postprocessing blocks
}
```

## Implementation Details

### How It Works

1. **Models Tab**: Fetches all models and shows only those with at least one supported version
   - Uses `supportedModelsProvider` which fetches all models, then filters by checking each model's versions
   - Shows a loading spinner while fetching
   - Displays error message if fetch fails

2. **Model Details Tab**: Shows version information for the selected model
   - Fetches versions using `modelVersionsProvider`
   - Displays pipeline configuration visually
   - Provides download button with details preview

3. **Version Download**: 
   - Shows what will be downloaded (model, labels, etc.)
   - Uses `downloadModelFileProvider` to fetch binary data
   - In the dialog, you can implement actual file saving logic

## Next Steps

### To Implement Model Download & Usage:
1. Add a dependency for local file storage (e.g., `path_provider`, `permission_handler`)
2. In the download dialog, implement:
   ```dart
   // Save downloaded files locally
   final bytes = await ref.read(downloadModelFileProvider(url).future);
   // Write to app documents directory
   final file = File('${appDir.path}/model.tflite');
   await file.writeAsBytes(bytes);
   ```

3. Update `InferenceService` to load from downloaded files instead of assets

### To Use Downloaded Models:
1. Once models are saved locally, you can instantiate `InferenceService` with local paths
2. Update the model selection flow to initialize inference when "Use Model" is tapped
3. Add inference results display in a new tab or screen

## Error Handling

The UI components include error handling:
- Network errors show user-friendly messages
- Empty states are properly handled
- Loading states show progress indicators

## Testing

You can test the integration by:
1. Starting your FastAPI backend: `fastapi dev main.py`
2. Running the Flutter app
3. The app will attempt to fetch models from your backend
4. If models aren't showing, check:
   - Backend is running on the correct URL
   - Backend has models with `is_supported = true`
   - Check browser console/app logs for detailed errors

## Troubleshooting

**Models not showing?**
- Verify backend URL is correct in `ApiService`
- Check that your backend has models with supported versions
- Check app logs for network errors

**Pipeline config is null?**
- The LLM generation may not have completed
- Check backend logs for generation status
- Manually trigger generation via backend API if needed

**Build runner not generating files?**
- Clean build: `flutter clean && flutter pub get`
- Rebuild: `cd modelRange && dart run build_runner build --delete-conflicting-outputs`

