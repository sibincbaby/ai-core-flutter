/// Cost/pricing tracking for AI API usage.
///
/// Provides built-in pricing tables for common models and supports
/// custom pricing. All prices are in USD per 1 million tokens.

/// Per-million-token pricing for a model.
class AIModelPricing {
  /// Cost per 1 M input (prompt) tokens in USD.
  final double inputPerMillion;

  /// Cost per 1 M output (completion) tokens in USD.
  final double outputPerMillion;

  /// Optional cost per 1 M embedding tokens.
  final double? embeddingPerMillion;

  /// Optional cost per 1 M cached/context-cached input tokens.
  final double? cachedInputPerMillion;

  const AIModelPricing({
    required this.inputPerMillion,
    required this.outputPerMillion,
    this.embeddingPerMillion,
    this.cachedInputPerMillion,
  });
}

/// The calculated cost of an API call.
class AICostEstimate {
  /// Input (prompt) token cost in USD.
  final double inputCost;

  /// Output (completion) token cost in USD.
  final double outputCost;

  /// Total cost in USD.
  final double totalCost;

  /// The model used for this cost calculation.
  final String model;

  /// Number of input tokens.
  final int inputTokens;

  /// Number of output tokens.
  final int outputTokens;

  /// The pricing table used for calculation.
  final AIModelPricing pricing;

  const AICostEstimate({
    required this.inputCost,
    required this.outputCost,
    required this.totalCost,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.pricing,
  });

  @override
  String toString() =>
      'AICostEstimate(\$$totalCost — '
      '$inputTokens in @ \$${pricing.inputPerMillion}/M, '
      '$outputTokens out @ \$${pricing.outputPerMillion}/M)';
}

/// Cumulative cost tracking across multiple requests.
class AICostTracker {
  final List<AICostEstimate> _history = [];

  /// All recorded cost estimates.
  List<AICostEstimate> get history => List.unmodifiable(_history);

  /// Total accumulated cost in USD.
  double get totalCost => _history.fold(0.0, (sum, e) => sum + e.totalCost);

  /// Total input tokens across all tracked calls.
  int get totalInputTokens => _history.fold(0, (sum, e) => sum + e.inputTokens);

  /// Total output tokens across all tracked calls.
  int get totalOutputTokens =>
      _history.fold(0, (sum, e) => sum + e.outputTokens);

  /// Number of tracked API calls.
  int get callCount => _history.length;

  /// Record a cost estimate.
  void record(AICostEstimate estimate) => _history.add(estimate);

  /// Clear all recorded history.
  void clear() => _history.clear();

  /// Cost breakdown grouped by model.
  Map<String, double> get costByModel {
    final map = <String, double>{};
    for (final e in _history) {
      map[e.model] = (map[e.model] ?? 0.0) + e.totalCost;
    }
    return map;
  }
}

/// Calculates the cost of an API call based on token usage and model pricing.
///
/// Ships with built-in pricing for popular models. Custom pricing can be
/// provided via [customPricing] in the constructor or registered later
/// with [setPricing].
///
/// Usage:
/// ```dart
/// final calculator = AICostCalculator();
/// final response = await client.generate(request);
/// final cost = calculator.estimate(model: 'gpt-4.1', usage: response.usage!);
/// print(cost); // AICostEstimate($0.00123 …)
/// ```
class AICostCalculator {
  final Map<String, AIModelPricing> _pricing;

  /// Creates a calculator with built-in pricing plus any [customPricing].
  ///
  /// Custom entries override built-in pricing for the same model key.
  AICostCalculator({Map<String, AIModelPricing>? customPricing})
    : _pricing = {
        ..._builtInPricing,
        if (customPricing != null) ...customPricing,
      };

  /// Register or update pricing for a model.
  void setPricing(String modelId, AIModelPricing pricing) {
    _pricing[modelId] = pricing;
  }

  /// Remove pricing for a model (falls back to built-in if available).
  void removePricing(String modelId) {
    _pricing.remove(modelId);
  }

  /// Get the pricing entry for [modelId], or `null` if unknown.
  ///
  /// Supports prefix matching: e.g., 'gpt-4.1-2025-04-14' matches 'gpt-4.1'.
  AIModelPricing? getPricing(String modelId) {
    // Exact match first.
    if (_pricing.containsKey(modelId)) return _pricing[modelId];

    // Prefix match (longest prefix wins).
    String? bestKey;
    for (final key in _pricing.keys) {
      if (modelId.startsWith(key)) {
        if (bestKey == null || key.length > bestKey.length) {
          bestKey = key;
        }
      }
    }
    return bestKey != null ? _pricing[bestKey] : null;
  }

  /// Estimate the cost for a generate/chat call.
  ///
  /// [model] is the model identifier (e.g. `'gpt-4.1'`).
  /// [inputTokens] and [outputTokens] are the token counts from [AIUsage].
  ///
  /// Returns `null` if no pricing is available for the model.
  AICostEstimate? estimate({
    required String model,
    required int inputTokens,
    required int outputTokens,
  }) {
    final pricing = getPricing(model);
    if (pricing == null) return null;

    final inputCost = (inputTokens / 1000000) * pricing.inputPerMillion;
    final outputCost = (outputTokens / 1000000) * pricing.outputPerMillion;

    return AICostEstimate(
      inputCost: inputCost,
      outputCost: outputCost,
      totalCost: inputCost + outputCost,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      pricing: pricing,
    );
  }

  /// Estimate cost for an embedding request.
  ///
  /// Returns `null` if no pricing or no embedding pricing is available.
  AICostEstimate? estimateEmbedding({
    required String model,
    required int tokens,
  }) {
    final pricing = getPricing(model);
    if (pricing == null || pricing.embeddingPerMillion == null) return null;

    final cost = (tokens / 1000000) * pricing.embeddingPerMillion!;

    return AICostEstimate(
      inputCost: cost,
      outputCost: 0,
      totalCost: cost,
      model: model,
      inputTokens: tokens,
      outputTokens: 0,
      pricing: pricing,
    );
  }

  /// All known model IDs with pricing.
  Set<String> get knownModels => _pricing.keys.toSet();

  // ── Built-in pricing tables (USD per 1 M tokens, as of mid-2025) ──

  static const Map<String, AIModelPricing> _builtInPricing = {
    // ── OpenAI ────────────────────────────────────────────────
    'gpt-4.1': AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
    'gpt-4.1-mini': AIModelPricing(
      inputPerMillion: 0.40,
      outputPerMillion: 1.60,
    ),
    'gpt-4.1-nano': AIModelPricing(
      inputPerMillion: 0.10,
      outputPerMillion: 0.40,
    ),
    'gpt-4o': AIModelPricing(inputPerMillion: 2.50, outputPerMillion: 10.0),
    'gpt-4o-mini': AIModelPricing(
      inputPerMillion: 0.15,
      outputPerMillion: 0.60,
    ),
    'o3': AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
    'o3-mini': AIModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40),
    'o4-mini': AIModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40),
    'o1': AIModelPricing(inputPerMillion: 15.0, outputPerMillion: 60.0),
    'o1-mini': AIModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40),
    'gpt-4-turbo': AIModelPricing(
      inputPerMillion: 10.0,
      outputPerMillion: 30.0,
    ),
    'gpt-4': AIModelPricing(inputPerMillion: 30.0, outputPerMillion: 60.0),

    // ── OpenAI Embeddings ────────────────────────────────────
    'text-embedding-3-small': AIModelPricing(
      inputPerMillion: 0.02,
      outputPerMillion: 0,
      embeddingPerMillion: 0.02,
    ),
    'text-embedding-3-large': AIModelPricing(
      inputPerMillion: 0.13,
      outputPerMillion: 0,
      embeddingPerMillion: 0.13,
    ),

    // ── Google Gemini ────────────────────────────────────────
    'gemini-2.5-pro': AIModelPricing(
      inputPerMillion: 1.25,
      outputPerMillion: 10.0,
    ),
    'gemini-2.5-flash': AIModelPricing(
      inputPerMillion: 0.15,
      outputPerMillion: 0.60,
    ),
    'gemini-2.0-flash': AIModelPricing(
      inputPerMillion: 0.10,
      outputPerMillion: 0.40,
    ),
    'gemini-2.0-flash-lite': AIModelPricing(
      inputPerMillion: 0.075,
      outputPerMillion: 0.30,
    ),
    'gemini-1.5-pro': AIModelPricing(
      inputPerMillion: 1.25,
      outputPerMillion: 5.0,
    ),
    'gemini-1.5-flash': AIModelPricing(
      inputPerMillion: 0.075,
      outputPerMillion: 0.30,
    ),

    // ── Gemini Embeddings ────────────────────────────────────
    'text-embedding-004': AIModelPricing(
      inputPerMillion: 0.0,
      outputPerMillion: 0.0,
      embeddingPerMillion: 0.0, // Free tier
    ),
  };
}
