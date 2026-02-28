import 'ai_tool.dart';

/// A normalized response from any LLM provider.
class AIResponse {
  /// The generated text content.
  final String text;

  /// The model that produced this response.
  final String? model;

  /// The finish reason (e.g., 'stop', 'length', 'content_filter', 'tool_calls').
  final String? finishReason;

  /// Tool calls requested by the model (non-empty when finishReason is 'tool_calls').
  final List<AIToolCall> toolCalls;

  /// Token usage information.
  final AIUsage? usage;

  /// The raw response map from the provider.
  final Map<String, dynamic> raw;

  const AIResponse({
    required this.text,
    this.model,
    this.finishReason,
    this.toolCalls = const [],
    this.usage,
    required this.raw,
  });

  /// Whether this response contains tool calls.
  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Token usage statistics.
class AIUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const AIUsage({this.promptTokens, this.completionTokens, this.totalTokens});
}
