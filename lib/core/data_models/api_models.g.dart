// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AssetPointers _$AssetPointersFromJson(Map<String, dynamic> json) =>
    AssetPointers(
      tflite: json['tflite'] as String,
      labels: json['labels'] as String?,
      tokenizer: json['tokenizer'] as String?,
      vocab: json['vocab'] as String?,
      anchors: json['anchors'] as String?,
    );

Map<String, dynamic> _$AssetPointersToJson(AssetPointers instance) =>
    <String, dynamic>{
      'tflite': instance.tflite,
      'labels': instance.labels,
      'tokenizer': instance.tokenizer,
      'vocab': instance.vocab,
      'anchors': instance.anchors,
    };

MetadataBlock _$MetadataBlockFromJson(Map<String, dynamic> json) =>
    MetadataBlock(
      schema_version: json['schema_version'] as String,
      model_name: json['model_name'] as String,
      model_version: json['model_version'] as String,
      model_task: json['model_task'] as String,
      framework: json['framework'] as String,
      source_repository: json['source_repository'] as String?,
    );

Map<String, dynamic> _$MetadataBlockToJson(MetadataBlock instance) =>
    <String, dynamic>{
      'schema_version': instance.schema_version,
      'model_name': instance.model_name,
      'model_version': instance.model_version,
      'model_task': instance.model_task,
      'framework': instance.framework,
      'source_repository': instance.source_repository,
    };

TensorDefinition _$TensorDefinitionFromJson(Map<String, dynamic> json) =>
    TensorDefinition(
      name: json['name'] as String,
      shape:
          (json['shape'] as List<dynamic>)
              .map((e) => (e as num).toInt())
              .toList(),
      dtype: json['dtype'] as String,
    );

Map<String, dynamic> _$TensorDefinitionToJson(TensorDefinition instance) =>
    <String, dynamic>{
      'name': instance.name,
      'shape': instance.shape,
      'dtype': instance.dtype,
    };

PreprocessStep _$PreprocessStepFromJson(Map<String, dynamic> json) =>
    PreprocessStep(
      step: json['step'] as String,
      params: json['params'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$PreprocessStepToJson(PreprocessStep instance) =>
    <String, dynamic>{'step': instance.step, 'params': instance.params};

PostprocessStep _$PostprocessStepFromJson(Map<String, dynamic> json) =>
    PostprocessStep(
      step: json['step'] as String,
      params: json['params'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$PostprocessStepToJson(PostprocessStep instance) =>
    <String, dynamic>{'step': instance.step, 'params': instance.params};

PreprocessBlock _$PreprocessBlockFromJson(Map<String, dynamic> json) =>
    PreprocessBlock(
      input_name: json['input_name'] as String,
      expects_type: json['expects_type'] as String,
      steps:
          (json['steps'] as List<dynamic>)
              .map((e) => PreprocessStep.fromJson(e as Map<String, dynamic>))
              .toList(),
    );

Map<String, dynamic> _$PreprocessBlockToJson(PreprocessBlock instance) =>
    <String, dynamic>{
      'input_name': instance.input_name,
      'expects_type': instance.expects_type,
      'steps': instance.steps,
    };

PostprocessBlock _$PostprocessBlockFromJson(Map<String, dynamic> json) =>
    PostprocessBlock(
      output_name: json['output_name'] as String,
      interpretation: json['interpretation'] as String,
      source_tensors:
          (json['source_tensors'] as List<dynamic>)
              .map((e) => e as String)
              .toList(),
      coordinate_format: json['coordinate_format'] as String?,
      steps:
          (json['steps'] as List<dynamic>)
              .map((e) => PostprocessStep.fromJson(e as Map<String, dynamic>))
              .toList(),
    );

Map<String, dynamic> _$PostprocessBlockToJson(PostprocessBlock instance) =>
    <String, dynamic>{
      'output_name': instance.output_name,
      'interpretation': instance.interpretation,
      'source_tensors': instance.source_tensors,
      'coordinate_format': instance.coordinate_format,
      'steps': instance.steps,
    };

PipelineConfig _$PipelineConfigFromJson(Map<String, dynamic> json) =>
    PipelineConfig(
      metadata:
          (json['metadata'] as List<dynamic>)
              .map((e) => MetadataBlock.fromJson(e as Map<String, dynamic>))
              .toList(),
      inputs:
          (json['inputs'] as List<dynamic>)
              .map((e) => TensorDefinition.fromJson(e as Map<String, dynamic>))
              .toList(),
      outputs:
          (json['outputs'] as List<dynamic>)
              .map((e) => TensorDefinition.fromJson(e as Map<String, dynamic>))
              .toList(),
      preprocessing:
          (json['preprocessing'] as List<dynamic>)
              .map((e) => PreprocessBlock.fromJson(e as Map<String, dynamic>))
              .toList(),
      postprocessing:
          (json['postprocessing'] as List<dynamic>)
              .map((e) => PostprocessBlock.fromJson(e as Map<String, dynamic>))
              .toList(),
    );

Map<String, dynamic> _$PipelineConfigToJson(PipelineConfig instance) =>
    <String, dynamic>{
      'metadata': instance.metadata,
      'inputs': instance.inputs,
      'outputs': instance.outputs,
      'preprocessing': instance.preprocessing,
      'postprocessing': instance.postprocessing,
    };

ModelVersion _$ModelVersionFromJson(Map<String, dynamic> json) => ModelVersion(
  id: json['id'] as String,
  model_id: json['model_id'] as String,
  version_name: json['version_name'] as String,
  commit_sha: json['commit_sha'] as String,
  is_hosted_by_us: json['is_hosted_by_us'] as bool,
  assets: AssetPointers.fromJson(json['assets'] as Map<String, dynamic>),
  license_type: json['license_type'] as String,
  is_commercial_safe: json['is_commercial_safe'] as bool,
  requires_commercial_warning: json['requires_commercial_warning'] as bool,
  file_size_bytes: (json['file_size_bytes'] as num).toInt(),
  status: json['status'] as String,
  changelog: json['changelog'] as String?,
  pipeline_spec:
      json['pipeline_spec'] == null
          ? null
          : PipelineConfig.fromJson(
            json['pipeline_spec'] as Map<String, dynamic>,
          ),
  published_at: json['published_at'] as String,
  download_count: (json['download_count'] as num).toInt(),
  num_ratings: (json['num_ratings'] as num).toInt(),
  rating_avg: (json['rating_avg'] as num).toDouble(),
  unsupported_reason: json['unsupported_reason'] as String?,
);

Map<String, dynamic> _$ModelVersionToJson(ModelVersion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'model_id': instance.model_id,
      'version_name': instance.version_name,
      'commit_sha': instance.commit_sha,
      'is_hosted_by_us': instance.is_hosted_by_us,
      'assets': instance.assets,
      'license_type': instance.license_type,
      'is_commercial_safe': instance.is_commercial_safe,
      'requires_commercial_warning': instance.requires_commercial_warning,
      'file_size_bytes': instance.file_size_bytes,
      'status': instance.status,
      'changelog': instance.changelog,
      'pipeline_spec': instance.pipeline_spec,
      'published_at': instance.published_at,
      'download_count': instance.download_count,
      'num_ratings': instance.num_ratings,
      'rating_avg': instance.rating_avg,
      'unsupported_reason': instance.unsupported_reason,
    };

MLModel _$MLModelFromJson(Map<String, dynamic> json) => MLModel(
  id: json['id'] as String,
  author_id: json['author_id'] as String,
  name: json['name'] as String,
  slug: json['slug'] as String?,
  description: json['description'] as String,
  category: json['category'] as String,
  task: json['task'] as String?,
  tags: (json['tags'] as List<dynamic>).map((e) => e as String).toList(),
  total_download_count: (json['total_download_count'] as num).toInt(),
  total_ratings: (json['total_ratings'] as num).toInt(),
  rating_weighted_avg: (json['rating_weighted_avg'] as num).toDouble(),
  created_at: json['created_at'] as String,
  version_count: (json['version_count'] as num?)?.toInt() ?? 0,
  file_size_bytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
  best_version_status: json['best_version_status'] as String?,
  versions:
      (json['versions'] as List<dynamic>?)
          ?.map((e) => ModelVersion.fromJson(e as Map<String, dynamic>))
          .toList(),
);

Map<String, dynamic> _$MLModelToJson(MLModel instance) => <String, dynamic>{
  'id': instance.id,
  'author_id': instance.author_id,
  'name': instance.name,
  'slug': instance.slug,
  'description': instance.description,
  'category': instance.category,
  'task': instance.task,
  'tags': instance.tags,
  'total_download_count': instance.total_download_count,
  'total_ratings': instance.total_ratings,
  'rating_weighted_avg': instance.rating_weighted_avg,
  'created_at': instance.created_at,
  'version_count': instance.version_count,
  'file_size_bytes': instance.file_size_bytes,
  'best_version_status': instance.best_version_status,
  'versions': instance.versions,
};
