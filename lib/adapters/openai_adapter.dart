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

/// OpenAI Chat Completions API adapter.
class OpenAIAdapter with OpenAICompatibleMixin implements AIProviderAdapter {
  @override
  final AIProviderConfig config;

  final Dio _dio;

  /// Optional retry configuration for automatic retry with backoff.
  final RetryConfig? retryConfig;

  /// Known OpenAI models with their capabilities (fallback registry).
  static const Map<String, AIModelCapabilities> knownModels = {
    // ── GPT-5 family (2025–2026) ─────────────────────────────
    'gpt-5.2': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 400000,
    ),
    'gpt-5.1': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 400000,
    ),
    'gpt-5': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 400000,
    ),
    'gpt-5-mini': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 400000,
    ),
    'gpt-5-nano': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 400000,
    ),

    // ── GPT-4.1 family ───────────────────────────────────────
    'gpt-4.1': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gpt-4.1-mini': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gpt-4.1-nano': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),

    // ── GPT-4o family ─────────────────────────────────────────
    'gpt-4o': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 128000,
    ),
    'gpt-4o-mini': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 128000,
    ),

    // ── o-series reasoning models ────────────────────────────
    'o4-mini': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 200000,
    ),
    'o3-pro': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 200000,
    ),
    'o3': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 200000,
    ),
    'o3-mini': AIModelCapabilities(
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 200000,
    ),

    // ── Legacy / deprecated ──────────────────────────────────
    'o1': AIModelCapabilities(
      supportsImageInput: true,
      maxContextWindow: 200000,
    ),
    'gpt-4-turbo': AIModelCapabilities(
      supportsImageInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 128000,
    ),
    'gpt-4': AIModelCapabilities(
      supportsToolCalling: true,
      maxContextWindow: 8192,
    ),
    'gpt-3.5-turbo': AIModelCapabilities(
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 16385,
    ),
  };

  OpenAIAdapter({required this.config, Dio? dio, this.retryConfig})
    : _dio = dio ?? Dio() {
    _configureDio();
  }

  void _configureDio() {
    _dio.options.baseUrl = config.effectiveBaseUrl;
    _dio.options.headers = {
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
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

  /// Resolves the Authorization header value for a request.
  ///
  /// If a [AIKeyPool] is configured, selects the key matching [keyTag]
  /// (or the default key). Otherwise uses [config.apiKey].
  Options _resolveKeyOptions(String? keyTag, {ResponseType? responseType}) {
    final pool = config.keyPool;
    if (pool != null) {
      final key = pool.resolve(label: keyTag);
      return Options(
        headers: {'Authorization': 'Bearer $key'},
        responseType: responseType,
      );
    }
    if (responseType != null) {
      return Options(responseType: responseType);
    }
    return Options();
  }

  /// Records token usage against the key pool entry (if configured).
  void _recordKeyUsage(String? keyTag, AIResponse response) {
    final pool = config.keyPool;
    if (pool == null) return;
    final label = keyTag ?? pool.defaultLabel;
    pool.recordUsage(
      label,
      inputTokens: response.usage?.promptTokens ?? 0,
      outputTokens: response.usage?.completionTokens ?? 0,
    );
  }

  @override
  Future<AIResponse> generate(AIRequest request) async {
    try {
      final body = buildOpenAIRequestBody(request, streamOverride: false);
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/chat/completions',
        data: body,
        options: _resolveKeyOptions(request.keyTag),
      );
      final aiResponse = parseOpenAIResponse(response.data!);
      _recordKeyUsage(request.keyTag, aiResponse);
      return aiResponse;
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
        options: _resolveKeyOptions(
          request.keyTag,
          responseType: ResponseType.stream,
        ),
      );

      yield* parseOpenAIStream(response.data!.stream);
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  @override
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) async {
    try {
      final body = <String, dynamic>{
        'model': request.model,
        'input': request.input,
        if (request.dimensions != null) 'dimensions': request.dimensions,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/embeddings',
        data: body,
        options: _resolveKeyOptions(null),
      );

      final data = response.data!;
      final embeddings = (data['data'] as List<dynamic>).map((e) {
        final item = e as Map<String, dynamic>;
        return AIEmbedding(
          index: item['index'] as int,
          embedding: (item['embedding'] as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList(),
        );
      }).toList();

      final usage = data['usage'] as Map<String, dynamic>?;

      return AIEmbeddingResponse(
        embeddings: embeddings,
        model: data['model'] as String?,
        totalTokens: usage?['total_tokens'] as int?,
        raw: data,
      );
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  @override
  Future<List<AIModel>> fetchModels() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/models');
      final data = response.data!['data'] as List<dynamic>;

      return data
          .where((m) {
            final id = (m as Map<String, dynamic>)['id'] as String;
            // Include chat/reasoning models, exclude embeddings/moderation/etc.
            // This is an exclusion filter so new model families are included
            // by default rather than silently dropped.
            return !id.startsWith('text-embedding') &&
                !id.startsWith('text-moderation') &&
                !id.startsWith('dall-e') &&
                !id.startsWith('tts-') &&
                !id.startsWith('whisper') &&
                !id.startsWith('davinci') &&
                !id.startsWith('babbage') &&
                !id.contains('instruct') &&
                !id.startsWith('chatgpt-');
          })
          .map((m) {
            final modelMap = m as Map<String, dynamic>;
            final id = modelMap['id'] as String;
            final capabilities = _resolveCapabilities(id);
            return AIModel(
              id: id,
              providerId: providerId,
              displayName: id,
              capabilities: capabilities,
            );
          })
          .toList();
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  /// Resolves capabilities for a model ID using the known models registry.
  ///
  /// Lookup order:
  /// 1. Exact match in [knownModels].
  /// 2. Prefix match (e.g. `gpt-4o-2024-08-06` → `gpt-4o`).
  /// 3. Family inference — unknown future models inherit from their family
  ///    (e.g. `gpt-6-turbo` inherits the modern GPT family defaults).
  /// 4. Bare minimum text-only fallback.
  AIModelCapabilities _resolveCapabilities(String modelId) {
    // Exact match first.
    if (knownModels.containsKey(modelId)) {
      return knownModels[modelId]!;
    }
    // Try prefix match (e.g., 'gpt-4o-2024-08-06' → 'gpt-4o').
    // Sort by key length descending so longest (most specific) prefix wins.
    final sortedKeys = knownModels.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      if (modelId.startsWith(key)) {
        return knownModels[key]!;
      }
    }
    // Family inference for unknown future models.
    return _inferFamilyCapabilities(modelId);
  }

  /// Infers capabilities for an unknown model based on its family prefix.
  ///
  /// This ensures that when OpenAI releases new models (e.g. gpt-6, o5),
  /// they get reasonable defaults without requiring a code update.
  static AIModelCapabilities _inferFamilyCapabilities(String modelId) {
    // Modern GPT models (gpt-X where X >= 4) support vision + tools + JSON.
    if (modelId.startsWith('gpt-')) {
      return const AIModelCapabilities(
        supportsImageInput: true,
        supportsToolCalling: true,
        supportsJsonMode: true,
      );
    }
    // o-series reasoning models support vision + tools + JSON.
    if (RegExp(r'^o\d').hasMatch(modelId)) {
      return const AIModelCapabilities(
        supportsImageInput: true,
        supportsToolCalling: true,
        supportsJsonMode: true,
      );
    }
    // Default: text-only with streaming.
    return const AIModelCapabilities();
  }

  @override
  void dispose() {
    _dio.close();
  }
}
