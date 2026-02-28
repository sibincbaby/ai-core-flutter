import 'package:dio/dio.dart';

import '../core/ai_provider_adapter.dart';
import '../core/retry_interceptor.dart';
import '../models/ai_embedding.dart';
import '../models/ai_model.dart';
import '../models/ai_provider_config.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../models/ai_stream_chunk.dart';
import 'openai_compatible_mixin.dart';

/// OpenRouter API adapter.
///
/// OpenRouter is wire-compatible with the OpenAI Chat Completions API,
/// so this adapter uses [OpenAICompatibleMixin] for request/response logic
/// and only overrides model fetching (which returns richer metadata).
class OpenRouterAdapter
    with OpenAICompatibleMixin
    implements AIProviderAdapter {
  @override
  final AIProviderConfig config;

  final Dio _dio;

  /// Optional retry configuration for automatic retry with backoff.
  final RetryConfig? retryConfig;

  /// Optional site URL for OpenRouter ranking headers.
  final String? siteUrl;

  /// Optional app name for OpenRouter ranking headers.
  final String? appName;

  OpenRouterAdapter({
    required this.config,
    Dio? dio,
    this.retryConfig,
    this.siteUrl,
    this.appName,
  }) : _dio = dio ?? Dio() {
    _configureDio();
  }

  void _configureDio() {
    _dio.options.baseUrl = config.effectiveBaseUrl;
    _dio.options.headers = {
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
      if (siteUrl != null) 'HTTP-Referer': siteUrl!,
      if (appName != null) 'X-Title': appName!,
      ...?config.extraHeaders,
    };
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);

    if (retryConfig != null) {
      _dio.interceptors.add(RetryInterceptor(dio: _dio, config: retryConfig!));
    }
  }

  @override
  String get providerId => config.id;

  @override
  Future<AIResponse> generate(AIRequest request) async {
    try {
      final body = buildOpenAIRequestBody(request, streamOverride: false);
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/chat/completions',
        data: body,
      );
      return parseOpenAIResponse(response.data!);
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  @override
  Stream<AIStreamChunk> stream(AIRequest request) async* {
    try {
      final body = buildOpenAIRequestBody(request, streamOverride: true);
      final response = await _dio.post<ResponseBody>(
        '/v1/chat/completions',
        data: body,
        options: Options(responseType: ResponseType.stream),
      );

      yield* parseOpenAIStream(response.data!.stream);
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  @override
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) {
    throw UnimplementedError(
      'OpenRouter does not support the embeddings API directly',
    );
  }

  @override
  Future<List<AIModel>> fetchModels() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/models');
      final data = response.data!['data'] as List<dynamic>;

      return data.map((m) {
        final modelMap = m as Map<String, dynamic>;
        final id = modelMap['id'] as String;
        final name = modelMap['name'] as String? ?? id;

        // Parse capabilities from architecture field.
        final architecture = modelMap['architecture'] as Map<String, dynamic>?;
        final inputModalities =
            (architecture?['input_modalities'] as List<dynamic>?)
                ?.cast<String>() ??
            ['text'];

        final capabilities = AIModelCapabilities(
          supportsText: inputModalities.contains('text'),
          supportsImageInput: inputModalities.contains('image'),
          supportsAudioInput: inputModalities.contains('audio'),
        );

        return AIModel(
          id: id,
          providerId: providerId,
          displayName: name,
          capabilities: capabilities,
          contextWindow: modelMap['context_length'] as int?,
        );
      }).toList();
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  @override
  void dispose() {
    _dio.close();
  }
}
