/// The type of LLM provider.
enum AIProviderType {
  openAI,
  gemini,
  openRouter,
}

/// Configuration for a single provider instance.
class AIProviderConfig {
  /// Unique identifier for this provider configuration.
  final String id;

  /// The provider type.
  final AIProviderType providerType;

  /// API key (loaded at runtime from secure storage).
  final String apiKey;

  /// Optional custom base URL (for proxies or custom endpoints).
  final String? baseUrl;

  /// Whether this is the default provider.
  final bool isDefault;

  /// Provider-specific headers.
  final Map<String, String>? extraHeaders;

  const AIProviderConfig({
    required this.id,
    required this.providerType,
    required this.apiKey,
    this.baseUrl,
    this.isDefault = false,
    this.extraHeaders,
  });

  /// Returns the effective base URL for this provider.
  String get effectiveBaseUrl {
    if (baseUrl != null) return baseUrl!;
    return switch (providerType) {
      AIProviderType.openAI => 'https://api.openai.com',
      AIProviderType.gemini => 'https://generativelanguage.googleapis.com',
      AIProviderType.openRouter => 'https://openrouter.ai/api',
    };
  }
}
