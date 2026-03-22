import 'package:json_annotation/json_annotation.dart';

part 'api_models.g.dart';

// ==========================================
// ASSET POINTERS
// ==========================================
@JsonSerializable()
class AssetPointers {
  final String tflite;
  final String? labels;
  final String? tokenizer;
  final String? vocab;
  final String? anchors;

  AssetPointers({
    required this.tflite,
    this.labels,
    this.tokenizer,
    this.vocab,
    this.anchors,
  });

  factory AssetPointers.fromJson(Map<String, dynamic> json) =>
      _$AssetPointersFromJson(json);

  Map<String, dynamic> toJson() => _$AssetPointersToJson(this);
}

// ==========================================
// PIPELINE CONFIG DATA MODELS
// ==========================================
@JsonSerializable()
class MetadataBlock {
  final String schema_version;
  final String model_name;
  final String model_version;
  final String model_task;
  final String framework;
  final String? source_repository;

  MetadataBlock({
    required this.schema_version,
    required this.model_name,
    required this.model_version,
    required this.model_task,
    required this.framework,
    this.source_repository,
  });

  factory MetadataBlock.fromJson(Map<String, dynamic> json) =>
      _$MetadataBlockFromJson(json);

  Map<String, dynamic> toJson() => _$MetadataBlockToJson(this);
}

@JsonSerializable()
class TensorDefinition {
  final String name;
  final List<int> shape;
  final String dtype;

  TensorDefinition({
    required this.name,
    required this.shape,
    required this.dtype,
  });

  factory TensorDefinition.fromJson(Map<String, dynamic> json) =>
      _$TensorDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$TensorDefinitionToJson(this);
}

@JsonSerializable()
class PreprocessStep {
  final String step;
  final Map<String, dynamic> params;

  PreprocessStep({required this.step, required this.params});

  factory PreprocessStep.fromJson(Map<String, dynamic> json) =>
      _$PreprocessStepFromJson(json);

  Map<String, dynamic> toJson() => _$PreprocessStepToJson(this);
}

@JsonSerializable()
class PostprocessStep {
  final String step;
  final Map<String, dynamic> params;

  PostprocessStep({required this.step, required this.params});

  factory PostprocessStep.fromJson(Map<String, dynamic> json) =>
      _$PostprocessStepFromJson(json);

  Map<String, dynamic> toJson() => _$PostprocessStepToJson(this);
}

@JsonSerializable()
class PreprocessBlock {
  final String input_name;
  final String expects_type;
  final List<PreprocessStep> steps;

  PreprocessBlock({
    required this.input_name,
    required this.expects_type,
    required this.steps,
  });

  factory PreprocessBlock.fromJson(Map<String, dynamic> json) =>
      _$PreprocessBlockFromJson(json);

  Map<String, dynamic> toJson() => _$PreprocessBlockToJson(this);
}

@JsonSerializable()
class PostprocessBlock {
  final String output_name;
  final String interpretation;
  final List<String> source_tensors;
  final String? coordinate_format;
  final List<PostprocessStep> steps;

  PostprocessBlock({
    required this.output_name,
    required this.interpretation,
    required this.source_tensors,
    this.coordinate_format,
    required this.steps,
  });

  factory PostprocessBlock.fromJson(Map<String, dynamic> json) =>
      _$PostprocessBlockFromJson(json);

  Map<String, dynamic> toJson() => _$PostprocessBlockToJson(this);
}

@JsonSerializable()
class PipelineConfig {
  final List<MetadataBlock> metadata;
  final List<TensorDefinition> inputs;
  final List<TensorDefinition> outputs;
  final List<PreprocessBlock> preprocessing;
  final List<PostprocessBlock> postprocessing;

  PipelineConfig({
    required this.metadata,
    required this.inputs,
    required this.outputs,
    required this.preprocessing,
    required this.postprocessing,
  });

  factory PipelineConfig.fromJson(Map<String, dynamic> json) =>
      _$PipelineConfigFromJson(json);

  Map<String, dynamic> toJson() => _$PipelineConfigToJson(this);
}

// ==========================================
// MODEL VERSION
// ==========================================
@JsonSerializable()
class ModelVersion {
  final String id;
  final String model_id;
  final String version_name;
  final String commit_sha;
  final bool is_hosted_by_us;
  final AssetPointers assets;
  final String license_type;
  final bool is_commercial_safe;
  final bool requires_commercial_warning;
  final int file_size_bytes;
  final String status;
  final String? changelog;
  final PipelineConfig? pipeline_spec;
  final String published_at;
  final int download_count;
  final int num_ratings;
  final double rating_avg;
  final String? unsupported_reason;

  ModelVersion({
    required this.id,
    required this.model_id,
    required this.version_name,
    required this.commit_sha,
    required this.is_hosted_by_us,
    required this.assets,
    required this.license_type,
    required this.is_commercial_safe,
    required this.requires_commercial_warning,
    required this.file_size_bytes,
    required this.status,
    this.changelog,
    this.pipeline_spec,
    required this.published_at,
    required this.download_count,
    required this.num_ratings,
    required this.rating_avg,
    this.unsupported_reason,
  });

  /// True if this version has a runnable pipeline (verified or pending verification).
  bool get isUsable => status == 'verified' || status == 'pending';

  factory ModelVersion.fromJson(Map<String, dynamic> json) =>
      _$ModelVersionFromJson(json);

  Map<String, dynamic> toJson() => _$ModelVersionToJson(this);
}

// ==========================================
// ML MODEL
// ==========================================
@JsonSerializable()
class MLModel {
  final String id;
  final String author_id;
  final String name;
  final String? slug;
  final String description;
  final String category;
  final String? task;
  final List<String> tags;
  final int total_download_count;
  final int total_ratings;
  final double rating_weighted_avg;
  final String created_at;
  final int version_count;
  final int file_size_bytes;
  final String? best_version_status;
  final List<ModelVersion>?
  versions; // Optional, for when versions are included

  MLModel({
    required this.id,
    required this.author_id,
    required this.name,
    this.slug,
    required this.description,
    required this.category,
    this.task,
    required this.tags,
    required this.total_download_count,
    required this.total_ratings,
    required this.rating_weighted_avg,
    required this.created_at,
    this.version_count = 0,
    this.file_size_bytes = 0,
    this.best_version_status,
    this.versions,
  });

  factory MLModel.fromJson(Map<String, dynamic> json) =>
      _$MLModelFromJson(json);

  Map<String, dynamic> toJson() => _$MLModelToJson(this);

  /// Check if this model has at least one supported version
  bool get hasSupported =>
      versions != null && versions!.any((v) => v.isUsable);
}
