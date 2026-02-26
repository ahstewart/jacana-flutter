import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data_models/api_models.dart';

class ApiService {
  // TODO: Update this to your actual backend URL
  static const String baseUrl =
      'http://10.0.2.2:8000/api/v1'; // Change this to your backend URL

  final http.Client _httpClient;

  ApiService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  // ==========================================
  // MODELS API
  // ==========================================

  /// Fetch all models, optionally filtered by task or supported status
  Future<List<MLModel>> getModels({
    int skip = 0,
    int limit = 1000,
    String? task,
    bool supportedOnly = false,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/models').replace(
        queryParameters: {
          'skip': skip.toString(),
          'limit': limit.toString(),
          if (task != null) 'task': task,
          if (supportedOnly) 'supported_only': 'true',
        },
      );

      final response = await _httpClient.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) => MLModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load models: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in getModels: $e');
      rethrow;
    }
  }

  /// Fetch a specific model by ID
  Future<MLModel> getModel(String modelId) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/models/$modelId'),
      );

      if (response.statusCode == 200) {
        return MLModel.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load model: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in getModel: $e');
      rethrow;
    }
  }

  // ==========================================
  // MODEL VERSIONS API
  // ==========================================

  /// Fetch all versions for a specific model
  Future<List<ModelVersion>> getModelVersions(String modelId) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/models/$modelId/versions'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) => ModelVersion.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load versions: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in getModelVersions: $e');
      rethrow;
    }
  }

  /// Fetch a specific model version by ID
  Future<ModelVersion> getModelVersion(String versionId) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/versions/$versionId'),
      );

      if (response.statusCode == 200) {
        return ModelVersion.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load version: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in getModelVersion: $e');
      rethrow;
    }
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  /// Download file from URL and return bytes
  Future<List<int>> downloadFile(String url) async {
    try {
      final response = await _httpClient.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error downloading file: $e');
      rethrow;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
