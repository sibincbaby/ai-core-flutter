/// Typed helpers for OpenRouter-specific request parameters.
///
/// These parameters are passed via the [AIRequest.extra] field and are
/// only meaningful when using the OpenRouter adapter.
///
/// See https://openrouter.ai/docs/api-reference/overview for the full API
/// reference.
///
/// ```dart
/// final response = await client.generate(AIRequest(
///   model: 'openai/gpt-5.1',
///   messages: [AIMessage.user('Hello')],
///   extra: OpenRouterOptions(
///     providerPreferences: ProviderPreferences(
///       sort: 'throughput',
///       allowFallbacks: false,
///     ),
///     plugins: [OpenRouterPlugin.web()],
///     user: 'user-123',
///   ).toMap(),
/// ));
/// ```
class OpenRouterOptions {
  /// Provider routing preferences.
  final ProviderPreferences? providerPreferences;

  /// Fallback model list.
  ///
  /// When set, OpenRouter will try models in order if the primary (or first)
  /// model fails. Use with [route] set to `'fallback'`.
  final List<String>? models;

  /// Route mode. Set to `'fallback'` to enable [models] fallback chain.
  final String? route;

  /// Prompt transforms to apply.
  ///
  /// E.g. `['middle-out']` to compress long contexts.
  final List<String>? transforms;

  /// OpenRouter plugins (web search, PDF parsing, response healing).
  final List<OpenRouterPlugin>? plugins;

  /// A stable end-user identifier for abuse prevention.
  final String? user;

  const OpenRouterOptions({
    this.providerPreferences,
    this.models,
    this.route,
    this.transforms,
    this.plugins,
    this.user,
  });

  /// Converts to a `Map<String, dynamic>` suitable for [AIRequest.extra].
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};

    if (providerPreferences != null) {
      map['provider'] = providerPreferences!.toMap();
    }
    if (models != null && models!.isNotEmpty) {
      map['models'] = models;
    }
    if (route != null) map['route'] = route;
    if (transforms != null && transforms!.isNotEmpty) {
      map['transforms'] = transforms;
    }
    if (plugins != null && plugins!.isNotEmpty) {
      map['plugins'] = plugins!.map((p) => p.toMap()).toList();
    }
    if (user != null) map['user'] = user;

    return map;
  }
}

/// Provider routing preferences for OpenRouter.
///
/// Controls which providers are tried, in what order, and with what
/// constraints. See
/// https://openrouter.ai/docs/guides/routing/provider-selection
class ProviderPreferences {
  /// Sort strategy: `'price'`, `'throughput'`, or `'latency'`.
  ///
  /// Can also be a map with `by` and `partition` keys for advanced sorting:
  /// ```dart
  /// sort: {'by': 'throughput', 'partition': 'none'}
  /// ```
  final Object? sort;

  /// Ordered list of provider slugs to try first.
  final List<String>? order;

  /// List of provider slugs to **only** allow.
  final List<String>? only;

  /// List of provider slugs to skip.
  final List<String>? ignore;

  /// Whether to allow fallback to other providers. Defaults to `true`.
  final bool? allowFallbacks;

  /// Only use providers supporting all params in the request.
  final bool? requireParameters;

  /// Data collection policy: `'allow'` or `'deny'`.
  final String? dataCollection;

  /// Restrict to Zero Data Retention endpoints.
  final bool? zdr;

  /// Restrict to models allowing text distillation.
  final bool? enforceDistillableText;

  /// Quantization levels to filter by (e.g. `['fp8', 'int4']`).
  final List<String>? quantizations;

  /// Maximum pricing: `{'prompt': 1.0, 'completion': 2.0}`.
  final Map<String, double>? maxPrice;

  /// Preferred minimum throughput in tokens/sec.
  ///
  /// Can be a `double` (p50) or `Map<String, double>` for percentile cutoffs
  /// (`{'p50': 100, 'p90': 50}`).
  final Object? preferredMinThroughput;

  /// Preferred maximum latency in seconds.
  ///
  /// Can be a `double` (p50) or `Map<String, double>` for percentile cutoffs
  /// (`{'p50': 1, 'p90': 3}`).
  final Object? preferredMaxLatency;

  const ProviderPreferences({
    this.sort,
    this.order,
    this.only,
    this.ignore,
    this.allowFallbacks,
    this.requireParameters,
    this.dataCollection,
    this.zdr,
    this.enforceDistillableText,
    this.quantizations,
    this.maxPrice,
    this.preferredMinThroughput,
    this.preferredMaxLatency,
  });

  /// Converts to the JSON map sent in the `provider` field of the request.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};

    if (sort != null) map['sort'] = sort;
    if (order != null) map['order'] = order;
    if (only != null) map['only'] = only;
    if (ignore != null) map['ignore'] = ignore;
    if (allowFallbacks != null) map['allow_fallbacks'] = allowFallbacks;
    if (requireParameters != null) {
      map['require_parameters'] = requireParameters;
    }
    if (dataCollection != null) map['data_collection'] = dataCollection;
    if (zdr != null) map['zdr'] = zdr;
    if (enforceDistillableText != null) {
      map['enforce_distillable_text'] = enforceDistillableText;
    }
    if (quantizations != null) map['quantizations'] = quantizations;
    if (maxPrice != null) map['max_price'] = maxPrice;
    if (preferredMinThroughput != null) {
      map['preferred_min_throughput'] = preferredMinThroughput;
    }
    if (preferredMaxLatency != null) {
      map['preferred_max_latency'] = preferredMaxLatency;
    }

    return map;
  }
}

/// An OpenRouter plugin configuration.
///
/// See https://openrouter.ai/docs/guides/features/plugins
class OpenRouterPlugin {
  /// Plugin identifier: `'web'`, `'file-parser'`, or `'response-healing'`.
  final String id;

  /// Whether the plugin is enabled. Defaults to `true`.
  final bool? enabled;

  /// Extra plugin-specific options (e.g. `max_results` for web search).
  final Map<String, dynamic>? options;

  const OpenRouterPlugin({required this.id, this.enabled, this.options});

  /// Web search plugin — augments responses with real-time search results.
  ///
  /// [maxResults] limits the number of search results injected.
  factory OpenRouterPlugin.web({int? maxResults}) => OpenRouterPlugin(
    id: 'web',
    options: maxResults != null ? {'max_results': maxResults} : null,
  );

  /// Response healing plugin — automatically repairs malformed JSON output.
  factory OpenRouterPlugin.responseHealing() =>
      const OpenRouterPlugin(id: 'response-healing');

  /// File/PDF parser plugin.
  factory OpenRouterPlugin.fileParser() =>
      const OpenRouterPlugin(id: 'file-parser');

  /// Converts to JSON map for the `plugins` array.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'id': id};
    if (enabled != null) map['enabled'] = enabled;
    if (options != null) map.addAll(options!);
    return map;
  }
}
