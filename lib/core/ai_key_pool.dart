/// A labeled API key entry in an [AIKeyPool].
///
/// Each key has a required [label] for identification and per-key
/// usage tracking.
///
/// ```dart
/// AIKeyEntry('sk-prod-key', label: 'premium')
/// AIKeyEntry('sk-free-key', label: 'free-tier')
/// ```
class AIKeyEntry {
  /// The API key value.
  final String key;

  /// Human-readable label for this key (e.g., `'premium'`, `'free-tier'`).
  final String label;

  const AIKeyEntry(this.key, {required this.label});
}

/// Per-key usage statistics tracked by [AIKeyPool].
class AIKeyUsage {
  /// The label of the key.
  final String label;

  /// Total number of API calls made with this key.
  int callCount = 0;

  /// Total input (prompt) tokens used.
  int inputTokens = 0;

  /// Total output (completion) tokens used.
  int outputTokens = 0;

  AIKeyUsage({required this.label});

  /// Total tokens across input and output.
  int get totalTokens => inputTokens + outputTokens;

  @override
  String toString() =>
      'AIKeyUsage($label: $callCount calls, '
      '$inputTokens in + $outputTokens out = $totalTokens tokens)';
}

/// Manages a pool of labeled API keys for a single provider.
///
/// Keys are selected **explicitly** by the caller — there is no automatic
/// rotation. One key is designated as the default (used when no label
/// is specified). Usage is tracked per key.
///
/// ```dart
/// final pool = AIKeyPool(
///   entries: [
///     AIKeyEntry('sk-free-key', label: 'free'),
///     AIKeyEntry('sk-premium-key', label: 'premium'),
///   ],
///   defaultLabel: 'free',
/// );
///
/// pool.resolve();               // 'sk-free-key' (default)
/// pool.resolve(label: 'premium'); // 'sk-premium-key'
///
/// pool.recordUsage('free', inputTokens: 100, outputTokens: 50);
/// print(pool.usage); // {free: AIKeyUsage(free: 1 calls, …)}
/// ```
class AIKeyPool {
  final Map<String, AIKeyEntry> _entries = {};
  final Map<String, AIKeyUsage> _usage = {};
  String _defaultLabel;

  /// Creates a key pool from labeled entries.
  ///
  /// [entries] must not be empty. [defaultLabel] must match one of the
  /// entry labels; if omitted, the first entry's label is used.
  AIKeyPool({required List<AIKeyEntry> entries, String? defaultLabel})
    : assert(entries.isNotEmpty, 'Key pool must have at least one entry'),
      _defaultLabel = defaultLabel ?? entries.first.label {
    for (final entry in entries) {
      _entries[entry.label] = entry;
      _usage[entry.label] = AIKeyUsage(label: entry.label);
    }
    assert(
      _entries.containsKey(_defaultLabel),
      'Default label "$_defaultLabel" not found in entries',
    );
  }

  /// The label of the currently-selected default key.
  String get defaultLabel => _defaultLabel;

  /// Change the default key by label.
  ///
  /// Throws [ArgumentError] if [label] doesn't exist.
  set defaultLabel(String label) {
    if (!_entries.containsKey(label)) {
      throw ArgumentError('Key label "$label" not found in pool');
    }
    _defaultLabel = label;
  }

  /// Resolve a key by label.
  ///
  /// If [label] is null, returns the default key.
  /// If [label] is specified but not found, returns the default key.
  String resolve({String? label}) {
    if (label != null && _entries.containsKey(label)) {
      return _entries[label]!.key;
    }
    return _entries[_defaultLabel]!.key;
  }

  /// Record usage for a key by label.
  ///
  /// Call this after each API response to track per-key consumption.
  void recordUsage(String label, {int inputTokens = 0, int outputTokens = 0}) {
    final usage = _usage[label];
    if (usage != null) {
      usage.callCount++;
      usage.inputTokens += inputTokens;
      usage.outputTokens += outputTokens;
    }
  }

  /// Per-key usage statistics (unmodifiable snapshot).
  Map<String, AIKeyUsage> get usage => Map.unmodifiable(_usage);

  /// Usage for a specific key label (or null).
  AIKeyUsage? usageFor(String label) => _usage[label];

  /// All available key labels.
  List<String> get labels => _entries.keys.toList();

  /// Number of keys in the pool.
  int get length => _entries.length;

  /// Reset usage counters for all keys.
  void resetUsage() {
    for (final usage in _usage.values) {
      usage.callCount = 0;
      usage.inputTokens = 0;
      usage.outputTokens = 0;
    }
  }
}
