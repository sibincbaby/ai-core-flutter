import 'ai_content.dart';
import 'ai_tool.dart';

/// The role of a message participant.
enum AIRole {
  system,
  user,
  assistant,

  /// A tool/function result message.
  tool,
}

/// A single message in a conversation.
class AIMessage {
  final AIRole role;
  final List<AIContentBlock> content;

  /// Tool calls made by the assistant (only for [AIRole.assistant]).
  final List<AIToolCall>? toolCalls;

  /// The tool call ID this message is responding to (only for [AIRole.tool]).
  final String? toolCallId;

  const AIMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
  });

  /// Create a text-only message with the given role.
  factory AIMessage.text({required AIRole role, required String text}) =>
      AIMessage(role: role, content: [AIContentBlock.text(text)]);

  /// Create a user message with a text prompt.
  factory AIMessage.user(String text) =>
      AIMessage.text(role: AIRole.user, text: text);

  /// Create a system message.
  factory AIMessage.system(String text) =>
      AIMessage.text(role: AIRole.system, text: text);

  /// Create an assistant message.
  factory AIMessage.assistant(String text) =>
      AIMessage.text(role: AIRole.assistant, text: text);

  /// Create an assistant message that contains tool calls.
  factory AIMessage.toolCalls(List<AIToolCall> toolCalls, {String? text}) =>
      AIMessage(
        role: AIRole.assistant,
        content: text != null ? [AIContentBlock.text(text)] : [],
        toolCalls: toolCalls,
      );

  /// Create a tool result message.
  factory AIMessage.toolResult({
    required String toolCallId,
    required String result,
  }) => AIMessage(
    role: AIRole.tool,
    content: [AIContentBlock.text(result)],
    toolCallId: toolCallId,
  );

  /// Whether this message contains any non-text content.
  bool get hasMultiModalContent =>
      content.any((block) => block.type != AIContentType.text);

  /// The set of content types present in this message.
  Set<AIContentType> get contentTypes =>
      content.map((block) => block.type).toSet();
}
