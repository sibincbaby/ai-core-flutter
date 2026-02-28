import '../core/ai_key_pool.dart';

/// The type of LLM provider.
enum AIProviderType { openAI, gemini, openRouter }

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

  /// Optional pool of labeled API keys for per-request key selection
  /// and usage tracking.
  ///
  /// When provided, the adapter resolves the key for each request from
  /// the pool based on the request's [AIRequest.keyTag]. If no tag is
  /// specified, the pool's default key is used.
  ///
  /// The [apiKey] field serves as the initial Dio default. When a pool
  /// is configured, it takes precedence per-request.
  ///
  /// ```dart
  /// final config = AIProviderConfig(
  ///   id: 'openai',
  ///   providerType: AIProviderType.openAI,
  ///   apiKey: 'sk-default',
  ///   keyPool: AIKeyPool(
  ///     entries: [
  ///       AIKeyEntry('sk-free-key', label: 'free'),
  ///       AIKeyEntry('sk-prod-key', label: 'premium'),
  ///     ],
  ///     defaultLabel: 'free',
  ///   ),
  /// );
  /// ```
  final AIKeyPool? keyPool;

  const AIProviderConfig({
    required this.id,
    required this.providerType,
    required this.apiKey,
    this.baseUrl,
    this.isDefault = false,
    this.extraHeaders,
    this.keyPool,
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
