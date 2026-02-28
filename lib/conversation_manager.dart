import '../ai_client.dart';
import '../models/ai_message.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../models/ai_tool.dart';

/// A callback that resolves a tool call to a string result.
///
/// The callback receives the tool call and should return the result string.
typedef ToolExecutor = Future<String> Function(AIToolCall toolCall);

/// Manages a multi-turn conversation with automatic message history
/// and optional tool-call loop handling.
///
/// ```dart
/// final conversation = ConversationManager(
///   client: aiClient,
///   model: 'gpt-4o',
///   systemPrompt: 'You are a helpful assistant.',
/// );
///
/// final response = await conversation.send('Hello!');
/// print(response.text); // "Hello! How can I help?"
///
/// // History is maintained automatically
/// final followUp = await conversation.send('What did I just say?');
/// ```
class ConversationManager {
  final AIClient _client;
  final String model;
  final String? providerId;
  final List<AIMessage> _messages = [];

  /// Optional tools available in this conversation.
  final List<AITool>? tools;

  /// How the model selects tools.
  final AIToolChoice? toolChoice;

  /// Callback to execute tool calls. Required if [tools] is provided.
  final ToolExecutor? toolExecutor;

  /// Maximum number of tool-call round-trips per [send] call.
  /// Prevents infinite loops when models repeatedly call tools.
  final int maxToolRounds;

  /// Optional default temperature for all requests.
  final double? temperature;

  /// Optional default max tokens for all requests.
  final int? maxTokens;

  /// Whether to validate capabilities against cached models.
  final bool validateCapabilities;

  ConversationManager({
    required AIClient client,
    required this.model,
    this.providerId,
    String? systemPrompt,
    this.tools,
    this.toolChoice,
    this.toolExecutor,
    this.maxToolRounds = 10,
    this.temperature,
    this.maxTokens,
    this.validateCapabilities = true,
  }) : _client = client {
    if (systemPrompt != null) {
      _messages.add(AIMessage.system(systemPrompt));
    }
  }

  /// The current conversation history (read-only view).
  List<AIMessage> get messages => List.unmodifiable(_messages);

  /// The number of messages in the conversation (including system prompt).
  int get messageCount => _messages.length;

  /// Send a user message and get the assistant's response.
  ///
  /// If the model responds with tool calls and a [toolExecutor] is provided,
  /// the tool calls are executed and results fed back automatically until
  /// the model produces a text response or [maxToolRounds] is reached.
  Future<AIResponse> send(String userMessage) async {
    _messages.add(AIMessage.user(userMessage));
    return _generateWithToolLoop();
  }

  /// Send a user message with multimodal content.
  Future<AIResponse> sendMessage(AIMessage message) async {
    _messages.add(message);
    return _generateWithToolLoop();
  }

  /// Re-generate the last assistant response (useful for "try again").
  ///
  /// Removes the last assistant message(s) and any associated tool
  /// messages, then re-generates.
  Future<AIResponse> regenerate() {
    // Remove trailing assistant + tool messages.
    while (_messages.isNotEmpty) {
      final last = _messages.last;
      if (last.role == AIRole.assistant || last.role == AIRole.tool) {
        _messages.removeLast();
      } else {
        break;
      }
    }
    return _generateWithToolLoop();
  }

  /// Clear all messages (including system prompt).
  void clear() {
    _messages.clear();
  }

  /// Reset to just the system prompt (if one was provided originally).
  void reset({String? systemPrompt}) {
    _messages.clear();
    if (systemPrompt != null) {
      _messages.add(AIMessage.system(systemPrompt));
    }
  }

  /// Add a message to history without generating a response.
  ///
  /// Useful for injecting context or restoring previous conversations.
  void addMessage(AIMessage message) {
    _messages.add(message);
  }

  /// Add multiple messages to history without generating a response.
  void addMessages(List<AIMessage> messages) {
    _messages.addAll(messages);
  }

  Future<AIResponse> _generateWithToolLoop() async {
    for (var round = 0; round < maxToolRounds; round++) {
      final request = AIRequest(
        messages: List.of(_messages),
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
        tools: tools,
        toolChoice: toolChoice,
      );

      final response = await _client.generate(
        request,
        providerId: providerId,
        validateCapabilities: validateCapabilities,
      );

      // If the model wants to call tools and we have an executor, handle it.
      if (response.hasToolCalls && toolExecutor != null) {
        // Add the assistant's tool-call message to history.
        _messages.add(AIMessage.toolCalls(response.toolCalls));

        // Execute each tool call and add results.
        for (final toolCall in response.toolCalls) {
          final result = await toolExecutor!(toolCall);
          _messages.add(
            AIMessage.toolResult(toolCallId: toolCall.id, result: result),
          );
        }
        // Continue the loop — the model will see tool results and respond.
        continue;
      }

      // No tool calls (or no executor) — add assistant reply and return.
      if (response.text.isNotEmpty) {
        _messages.add(AIMessage.assistant(response.text));
      } else if (response.hasToolCalls) {
        // Tool calls but no executor — add the tool calls message anyway.
        _messages.add(AIMessage.toolCalls(response.toolCalls));
      }

      return response;
    }

    // Safety valve: if we've exhausted tool rounds, return the last response.
    final finalRequest = AIRequest(
      messages: List.of(_messages),
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      // Don't offer tools on the final round to force a text response.
    );

    final finalResponse = await _client.generate(
      finalRequest,
      providerId: providerId,
      validateCapabilities: validateCapabilities,
    );

    if (finalResponse.text.isNotEmpty) {
      _messages.add(AIMessage.assistant(finalResponse.text));
    }

    return finalResponse;
  }
}
