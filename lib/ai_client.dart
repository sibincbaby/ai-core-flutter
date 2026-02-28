import 'ai_provider_registry.dart';
import 'core/ai_provider_adapter.dart';
import 'core/capability_validator.dart';
import 'core/middleware.dart';
import 'models/ai_embedding.dart';
import 'models/ai_message.dart';
import 'models/ai_model.dart';
import 'models/ai_request.dart';
import 'models/ai_response.dart';
import 'models/ai_stream_chunk.dart';

/// The main entry point for the AI Core SDK.
///
/// Provides a provider-agnostic API for generating text, streaming,
/// and listing models. Uses [AIProviderRegistry] to resolve adapters
/// and [CapabilityValidator] to enforce model capability checks.
class AIClient {
  final AIProviderRegistry _registry;
  final CapabilityValidator _validator;
  final MiddlewarePipeline _middleware;

  AIClient({
    AIProviderRegistry? registry,
    CapabilityValidator? validator,
    MiddlewarePipeline? middleware,
  }) : _registry = registry ?? AIProviderRegistry(),
       _validator = validator ?? const CapabilityValidator(),
       _middleware = middleware ?? MiddlewarePipeline();

  /// Access the registry for registration/configuration.
  AIProviderRegistry get registry => _registry;

  /// Access the middleware pipeline for adding/removing middleware.
  MiddlewarePipeline get middleware => _middleware;

  /// Generate a non-streaming response.
  ///
  /// [providerId] defaults to the default provider if null.
  /// Set [validateCapabilities] to false to skip validation.
  Future<AIResponse> generate(
    AIRequest request, {
    String? providerId,
    bool validateCapabilities = true,
  }) async {
    final adapter = _registry.resolve(providerId);

    if (validateCapabilities) {
      _validateRequest(request, adapter);
    }

    final handler = _middleware.wrapGenerate((req) => adapter.generate(req));
    return handler(request);
  }

  /// Generate a streaming response.
  Stream<AIStreamChunk> stream(
    AIRequest request, {
    String? providerId,
    bool validateCapabilities = true,
  }) async* {
    final adapter = _registry.resolve(providerId);

    if (validateCapabilities) {
      _validateRequest(request, adapter);
    }

    final handler = _middleware.wrapStream((req) => adapter.stream(req));
    yield* handler(request);
  }

  /// Convenience: generate text from a simple prompt string.
  Future<String> generateText(
    String prompt, {
    required String model,
    String? providerId,
    double? temperature,
    int? maxTokens,
  }) async {
    final request = AIRequest(
      messages: [AIMessage.user(prompt)],
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    final response = await generate(request, providerId: providerId);
    return response.text;
  }

  /// Fetch available models from a provider.
  ///
  /// Results are cached in the registry for capability validation.
  Future<List<AIModel>> getModels({String? providerId}) async {
    final adapter = _registry.resolve(providerId);
    final models = await adapter.fetchModels();
    _registry.cacheModels(models);
    return models;
  }

  /// Generate text embeddings.
  ///
  /// [providerId] defaults to the default provider if null.
  /// Throws [UnimplementedError] if the provider does not support embeddings.
  Future<AIEmbeddingResponse> embed(
    AIEmbeddingRequest request, {
    String? providerId,
  }) {
    final adapter = _registry.resolve(providerId);
    return adapter.embed(request);
  }

  /// Validate request against cached model capabilities.
  void _validateRequest(AIRequest request, AIProviderAdapter adapter) {
    final model = _registry.getCachedModel(adapter.providerId, request.model);

    if (model != null) {
      _validator.validate(request, model);
    }
    // If model is not cached, skip validation (fail-open).
    // Users can call getModels() first to populate the cache.
  }

  /// Dispose all resources.
  void dispose() {
    _registry.disposeAll();
  }
}
