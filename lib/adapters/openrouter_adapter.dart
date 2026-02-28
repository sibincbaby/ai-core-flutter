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
///
/// ### OpenRouter-specific features
///
/// Use [OpenRouterOptions] (via [AIRequest.extra]) to access provider
/// routing, model fallbacks, plugins, and more. See
/// `lib/models/openrouter_options.dart` for full documentation.
///
/// ```dart
/// import 'package:ai_core/ai_core.dart';
///
/// final response = await client.generate(AIRequest(
///   model: 'openai/gpt-5.1',
///   messages: [AIMessage.user('Hello')],
///   extra: OpenRouterOptions(
///     providerPreferences: ProviderPreferences(sort: 'throughput'),
///     plugins: [OpenRouterPlugin.web()],
///   ).toMap(),
/// ));
/// ```
class OpenRouterAdapter
    with OpenAICompatibleMixin
    implements AIProviderAdapter {
  @override
  final AIProviderConfig config;

  final Dio _dio;

  /// Optional retry configuration for automatic retry with backoff.
  final RetryConfig? retryConfig;

  /// Optional site URL for OpenRouter ranking / app attribution headers.
  ///
  /// Sent as the `HTTP-Referer` header so your app appears on the OpenRouter
  /// leaderboard.
  final String? siteUrl;

  /// Optional app name for OpenRouter ranking / app attribution headers.
  ///
  /// Sent as the `X-OpenRouter-Title` header.
  final String? appName;

  /// Cached model capabilities from the last [fetchModels] call, keyed by
  /// model ID.
  final Map<String, AIModelCapabilities> _capabilitiesCache = {};

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
      if (appName != null) 'X-OpenRouter-Title': appName!,
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

      final models = <AIModel>[];

      for (final m in data) {
        final modelMap = m as Map<String, dynamic>;
        final id = modelMap['id'] as String;
        final name = modelMap['name'] as String? ?? id;

        // Parse capabilities from architecture field.
        final architecture = modelMap['architecture'] as Map<String, dynamic>?;
        final inputModalities =
            (architecture?['input_modalities'] as List<dynamic>?)
                ?.cast<String>() ??
            ['text'];

        // Parse supported_parameters for tool calling, JSON mode, etc.
        final supportedParams =
            (modelMap['supported_parameters'] as List<dynamic>?)
                ?.cast<String>() ??
            [];

        final capabilities = AIModelCapabilities(
          supportsText: inputModalities.contains('text'),
          supportsImageInput: inputModalities.contains('image'),
          supportsAudioInput: inputModalities.contains('audio'),
          supportsVideoInput: inputModalities.contains('video'),
          supportsToolCalling: supportedParams.contains('tools'),
          supportsJsonMode:
              supportedParams.contains('structured_outputs') ||
              supportedParams.contains('response_format'),
          maxContextWindow: modelMap['context_length'] as int?,
        );

        // Cache for capabilitiesFor lookups.
        _capabilitiesCache[id] = capabilities;

        models.add(
          AIModel(
            id: id,
            providerId: providerId,
            displayName: name,
            capabilities: capabilities,
            contextWindow: modelMap['context_length'] as int?,
          ),
        );
      }

      return models;
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  /// Returns cached capabilities for [modelId].
  ///
  /// Results are populated by [fetchModels]. Returns default capabilities
  /// (text-only, streaming) if the model hasn't been fetched yet.
  AIModelCapabilities capabilitiesFor(String modelId) {
    // Return cached capabilities if available (populated by fetchModels).
    final cached = _capabilitiesCache[modelId];
    if (cached != null) return cached;

    // Fallback: assume text-only with streaming support.
    return const AIModelCapabilities();
  }

  @override
  void dispose() {
    _dio.close();
  }
}
