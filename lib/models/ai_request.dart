import 'ai_message.dart';
import 'ai_response_format.dart';
import 'ai_tool.dart';

/// A normalized request to be sent to any LLM provider.
class AIRequest {
  /// The conversation messages.
  final List<AIMessage> messages;

  /// The model identifier (e.g., 'gpt-4o', 'gemini-1.5-pro').
  final String model;

  /// Sampling temperature (0.0 to 2.0 typically).
  final double? temperature;

  /// Maximum tokens to generate.
  final int? maxTokens;

  /// Whether to stream the response.
  final bool stream;

  /// Optional stop sequences.
  final List<String>? stopSequences;

  /// Tools (functions) the model may call.
  final List<AITool>? tools;

  /// Controls how the model selects tools.
  final AIToolChoice? toolChoice;

  /// Controls the output format (text, JSON, or structured JSON schema).
  final AIResponseFormat? responseFormat;

  /// Provider-specific extra parameters (passed through as-is).
  final Map<String, dynamic>? extra;

  const AIRequest({
    required this.messages,
    required this.model,
    this.temperature,
    this.maxTokens,
    this.stream = false,
    this.stopSequences,
    this.tools,
    this.toolChoice,
    this.responseFormat,
    this.extra,
  });

  /// Creates a copy with overridden fields.
  AIRequest copyWith({
    List<AIMessage>? messages,
    String? model,
    double? temperature,
    int? maxTokens,
    bool? stream,
    List<String>? stopSequences,
    List<AITool>? tools,
    AIToolChoice? toolChoice,
    AIResponseFormat? responseFormat,
    Map<String, dynamic>? extra,
  }) => AIRequest(
    messages: messages ?? this.messages,
    model: model ?? this.model,
    temperature: temperature ?? this.temperature,
    maxTokens: maxTokens ?? this.maxTokens,
    stream: stream ?? this.stream,
    stopSequences: stopSequences ?? this.stopSequences,
    tools: tools ?? this.tools,
    toolChoice: toolChoice ?? this.toolChoice,
    responseFormat: responseFormat ?? this.responseFormat,
    extra: extra ?? this.extra,
  );
}
