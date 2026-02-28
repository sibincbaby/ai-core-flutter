import '../models/ai_embedding.dart';
import '../models/ai_model.dart';
import '../models/ai_provider_config.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../models/ai_stream_chunk.dart';

/// Abstract contract for all LLM provider adapters.
///
/// Each provider (OpenAI, Gemini, OpenRouter) implements this interface
/// to normalize their API into the shared SDK types.
abstract class AIProviderAdapter {
  /// The provider configuration.
  AIProviderConfig get config;

  /// The provider ID (delegates to config.id).
  String get providerId => config.id;

  /// Send a non-streaming generation request.
  Future<AIResponse> generate(AIRequest request);

  /// Send a streaming generation request.
  ///
  /// Returns a stream of [AIStreamChunk]. The final chunk has [isDone] = true.
  Stream<AIStreamChunk> stream(AIRequest request);

  /// Generate text embeddings.
  ///
  /// Not all providers support embeddings. Throws [UnimplementedError]
  /// by default. Override in adapters that support embeddings.
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) {
    throw UnimplementedError('$providerId does not support the embeddings API');
  }

  /// Fetch the list of models available from this provider.
  Future<List<AIModel>> fetchModels();

  /// Dispose of any resources (e.g., HTTP client).
  void dispose();
}
