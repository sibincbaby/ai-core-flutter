/// A single chunk from a streaming LLM response.
class AIStreamChunk {
  /// The text delta for this chunk.
  final String textDelta;

  /// Whether this is the final chunk.
  final bool isDone;

  /// The finish reason if this is the final chunk.
  final String? finishReason;

  /// The model that produced this chunk.
  final String? model;

  /// Incremental tool call data in this chunk.
  final List<AIToolCallDelta>? toolCallDeltas;

  /// Raw chunk data from the provider.
  final Map<String, dynamic>? raw;

  const AIStreamChunk({
    required this.textDelta,
    this.isDone = false,
    this.finishReason,
    this.model,
    this.toolCallDeltas,
    this.raw,
  });

  /// A sentinel chunk indicating the stream is complete.
  factory AIStreamChunk.done({String? finishReason, String? model}) =>
      AIStreamChunk(
        textDelta: '',
        isDone: true,
        finishReason: finishReason,
        model: model,
      );
}

/// Incremental tool call data received during streaming.
class AIToolCallDelta {
  /// The index of this tool call in the array.
  final int index;

  /// The tool call ID (only present in the first delta for this index).
  final String? id;

  /// The function name (only present in the first delta for this index).
  final String? functionName;

  /// Incremental argument string fragment.
  final String? argumentsDelta;

  const AIToolCallDelta({
    required this.index,
    this.id,
    this.functionName,
    this.argumentsDelta,
  });
}
