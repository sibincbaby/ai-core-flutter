/// Capability flags for an AI model.
class AIModelCapabilities {
  final bool supportsText;
  final bool supportsImageInput;
  final bool supportsAudioInput;
  final bool supportsVideoInput;
  final bool supportsStreaming;

  /// Whether this model supports tool/function calling.
  final bool supportsToolCalling;

  /// Whether this model supports JSON / structured output mode.
  final bool supportsJsonMode;

  /// Maximum context window size in tokens (if known).
  ///
  /// Used for informational / validation purposes. null if unknown.
  final int? maxContextWindow;

  const AIModelCapabilities({
    this.supportsText = true,
    this.supportsImageInput = false,
    this.supportsAudioInput = false,
    this.supportsVideoInput = false,
    this.supportsStreaming = true,
    this.supportsToolCalling = false,
    this.supportsJsonMode = false,
    this.maxContextWindow,
  });
}

/// Represents a model available from a provider.
class AIModel {
  /// The model identifier as used in API requests.
  final String id;

  /// The provider this model belongs to.
  final String providerId;

  /// Human-readable display name.
  final String displayName;

  /// Capability flags.
  final AIModelCapabilities capabilities;

  /// Context window size in tokens (if known).
  final int? contextWindow;

  const AIModel({
    required this.id,
    required this.providerId,
    required this.displayName,
    required this.capabilities,
    this.contextWindow,
  });
}
