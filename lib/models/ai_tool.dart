/// Defines a tool (function) that can be called by the AI model.
class AITool {
  /// The type of tool. Currently only 'function' is supported.
  final String type;

  /// The function definition.
  final AIFunctionDefinition function;

  const AITool({this.type = 'function', required this.function});

  /// Convenience constructor for a function tool.
  factory AITool.function({
    required String name,
    required String description,
    required Map<String, dynamic> parameters,
  }) => AITool(
    function: AIFunctionDefinition(
      name: name,
      description: description,
      parameters: parameters,
    ),
  );
}

/// Describes a function that can be invoked by the AI model.
class AIFunctionDefinition {
  /// The name of the function (must match [a-zA-Z0-9_-]+).
  final String name;

  /// A description of what the function does.
  final String description;

  /// JSON Schema describing the function parameters.
  ///
  /// Example:
  /// ```dart
  /// {
  ///   'type': 'object',
  ///   'properties': {
  ///     'location': {
  ///       'type': 'string',
  ///       'description': 'The city name',
  ///     },
  ///   },
  ///   'required': ['location'],
  /// }
  /// ```
  final Map<String, dynamic> parameters;

  /// Whether the function should be called with strict schema adherence.
  final bool? strict;

  const AIFunctionDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.strict,
  });
}

/// Represents a tool call made by the AI model in its response.
class AIToolCall {
  /// The unique ID of this tool call (used to match results).
  final String id;

  /// The type of tool call (always 'function' currently).
  final String type;

  /// The name of the function to call.
  final String functionName;

  /// The JSON-encoded arguments for the function.
  final String arguments;

  const AIToolCall({
    required this.id,
    this.type = 'function',
    required this.functionName,
    required this.arguments,
  });
}

/// Controls how the model selects tools.
///
/// Use the factory constructors for common strategies.
class AIToolChoice {
  /// The strategy string or object.
  ///
  /// Values: 'auto', 'none', 'required', or a specific function spec.
  final Object value;

  const AIToolChoice._(this.value);

  /// Model decides whether to call a tool (default behavior).
  static const auto = AIToolChoice._('auto');

  /// Model must not call any tools.
  static const none = AIToolChoice._('none');

  /// Model must call at least one tool.
  static const required = AIToolChoice._('required');

  /// Force the model to call a specific function.
  factory AIToolChoice.function(String name) => AIToolChoice._({
    'type': 'function',
    'function': {'name': name},
  });
}
