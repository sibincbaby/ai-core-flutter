/// Request for generating text embeddings.
class AIEmbeddingRequest {
  /// The text(s) to embed.
  final List<String> input;

  /// The embedding model to use (e.g., 'text-embedding-3-small').
  final String model;

  /// Optional: the number of dimensions for the embedding (if model supports it).
  final int? dimensions;

  const AIEmbeddingRequest({
    required this.input,
    required this.model,
    this.dimensions,
  });

  /// Convenience: embed a single text.
  factory AIEmbeddingRequest.single(
    String text, {
    required String model,
    int? dimensions,
  }) => AIEmbeddingRequest(input: [text], model: model, dimensions: dimensions);
}

/// A single embedding vector result.
class AIEmbedding {
  /// The index in the input list this embedding corresponds to.
  final int index;

  /// The embedding vector.
  final List<double> embedding;

  const AIEmbedding({required this.index, required this.embedding});
}

/// Response containing one or more embedding vectors.
class AIEmbeddingResponse {
  /// The embedding results.
  final List<AIEmbedding> embeddings;

  /// The model used.
  final String? model;

  /// Token usage.
  final int? totalTokens;

  /// The raw provider response.
  final Map<String, dynamic> raw;

  const AIEmbeddingResponse({
    required this.embeddings,
    this.model,
    this.totalTokens,
    required this.raw,
  });

  /// Get the first (or only) embedding vector.
  List<double> get firstVector => embeddings.first.embedding;
}
