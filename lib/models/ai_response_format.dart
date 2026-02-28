/// Controls the format of the model's output.
///
/// Use factory constructors for common formats.
class AIResponseFormat {
  /// The format type identifier.
  final String type;

  /// Optional JSON Schema for structured output
  /// (only used with [AIResponseFormat.jsonSchema]).
  final AIJsonSchema? jsonSchema;

  const AIResponseFormat._({required this.type, this.jsonSchema});

  /// The model outputs plain text (default behavior).
  static const text = AIResponseFormat._(type: 'text');

  /// The model outputs valid JSON.
  ///
  /// No schema enforcement — the model chooses the structure.
  static const json = AIResponseFormat._(type: 'json_object');

  /// The model outputs JSON conforming to the given schema.
  ///
  /// Supported by OpenAI (gpt-4o and later) and Gemini.
  ///
  /// Example:
  /// ```dart
  /// AIResponseFormat.jsonSchema(
  ///   name: 'weather_result',
  ///   schema: {
  ///     'type': 'object',
  ///     'properties': {
  ///       'temperature': {'type': 'number'},
  ///       'condition': {'type': 'string'},
  ///     },
  ///     'required': ['temperature', 'condition'],
  ///   },
  /// )
  /// ```
  factory AIResponseFormat.jsonSchema({
    required String name,
    required Map<String, dynamic> schema,
    String? description,
    bool strict = true,
  }) => AIResponseFormat._(
    type: 'json_schema',
    jsonSchema: AIJsonSchema(
      name: name,
      schema: schema,
      description: description,
      strict: strict,
    ),
  );
}

/// Describes a JSON schema for structured output.
class AIJsonSchema {
  /// The name of the schema (used for OpenAI's structured output).
  final String name;

  /// The JSON Schema definition.
  final Map<String, dynamic> schema;

  /// Optional human-readable description.
  final String? description;

  /// Whether to enforce strict schema adherence.
  final bool strict;

  const AIJsonSchema({
    required this.name,
    required this.schema,
    this.description,
    this.strict = true,
  });
}
