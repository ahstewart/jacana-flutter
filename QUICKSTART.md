# 🚀 Quick Start Guide - Backend API Integration

## 1️⃣ Configure Your Backend URL

Open `lib/core/services/api_service.dart` and update:

```dart
static const String baseUrl = 'http://localhost:8000'; // ← Change this!
```

Change to your actual backend URL (e.g., `https://api.yourserver.com`)

## 2️⃣ Run Your Backend

```bash
cd model-service/backend
fastapi dev main.py
```

## 3️⃣ Run Your Flutter App

```bash
cd modelRange
flutter run
```

## 4️⃣ What You Should See

**Models Tab (Default):**
- Loading spinner while fetching models
- List of all models that have at least one supported version
- Each model shows name and category
- Tap to view details

**Range Tab (After selecting a model):**
- Model name, description, category, download count
- List of supported versions for that model
- For each version:
  - Version name and status
  - License info and file size
  - Pipeline configuration breakdown
  - Download button
  - "Use Model" button

**Profile Tab:**
- Currently shows placeholder text

## 🎯 Key Features

| Feature | Status | Location |
|---------|--------|----------|
| Fetch models from backend | ✅ | `supportedModelsProvider` |
| Filter by is_supported | ✅ | Auto-filtered in provider |
| Show model versions | ✅ | Tap model → view versions |
| Display pipeline config | ✅ | Shown in VersionCard |
| View assets/downloads | ✅ | In download dialog |
| Download models | 🔄 | Dialog UI ready, needs file save logic |
| Inference | 🔄 | "Use Model" button ready, needs InferenceService update |

## 🔧 Troubleshooting

**"Error loading models"?**
1. Check backend URL in `ApiService`
2. Verify backend is running: `http://localhost:8000/docs`
3. Check backend has models with `is_supported = true`

**Backend URL not working?**
1. Use `http://192.168.x.x:8000` instead of `localhost` if on physical device
2. Check firewall isn't blocking port 8000

**No models showing?**
1. Check backend logs for errors
2. Verify database has models seeded
3. Check if models have been processed by LLM generator

## 📚 Files Reference

| File | Purpose |
|------|---------|
| `lib/core/services/api_service.dart` | HTTP requests to backend |
| `lib/core/data_models/api_models.dart` | Data structures matching backend |
| `lib/core/providers/model_providers.dart` | State management & data fetching |
| `lib/main.dart` | UI widgets using the providers |

## 💡 Next: Implement Download & Inference

1. **Add dependencies:**
   ```bash
   cd modelRange
   flutter pub add path_provider permission_handler
   ```

2. **Implement file download** in `_showDownloadDialog()`

3. **Update InferenceService** to load from saved files

4. **Connect inference to "Use Model" button**

## 🎓 Learn More

- See `IMPLEMENTATION_SUMMARY.md` for architecture overview
- See `API_INTEGRATION_GUIDE.md` for detailed code examples
- Check `riverpod_annotation` docs for provider patterns
- Check `json_annotation` docs for serialization

---

**You're all set!** The backend integration is complete and ready for the next phase. 🎉
