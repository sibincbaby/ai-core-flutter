import 'core/ai_provider_adapter.dart';
import 'models/ai_model.dart';
import 'errors/ai_exception.dart';

/// Registry that holds provider adapters and resolves them by ID.
class AIProviderRegistry {
  final Map<String, AIProviderAdapter> _adapters = {};
  final Map<String, AIModel> _modelCache = {};
  String? _defaultProviderId;

  /// Register a provider adapter.
  void register(AIProviderAdapter adapter) {
    final id = adapter.providerId;
    _adapters[id] = adapter;
    if (adapter.config.isDefault) {
      _defaultProviderId = id;
    }
  }

  /// Unregister a provider and dispose its adapter.
  void unregister(String providerId) {
    final adapter = _adapters.remove(providerId);
    adapter?.dispose();
    if (_defaultProviderId == providerId) {
      _defaultProviderId =
          _adapters.keys.isNotEmpty ? _adapters.keys.first : null;
    }
  }

  /// Resolve an adapter by provider ID.
  ///
  /// If [providerId] is null, returns the default provider.
  AIProviderAdapter resolve(String? providerId) {
    final id = providerId ?? _defaultProviderId;
    if (id == null) {
      throw const AIException(
        type: AIErrorType.unknown,
        message: 'No provider registered. Call register() first.',
      );
    }
    final adapter = _adapters[id];
    if (adapter == null) {
      throw AIException(
        type: AIErrorType.unknown,
        message: 'Provider "$id" is not registered.',
      );
    }
    return adapter;
  }

  /// All registered provider IDs.
  List<String> get providerIds => _adapters.keys.toList();

  /// The default provider ID, if any.
  String? get defaultProviderId => _defaultProviderId;

  /// Set the default provider.
  void setDefault(String providerId) {
    if (!_adapters.containsKey(providerId)) {
      throw AIException(
        type: AIErrorType.unknown,
        message:
            'Cannot set default: provider "$providerId" is not registered.',
      );
    }
    _defaultProviderId = providerId;
  }

  /// Cache a model for capability lookups.
  void cacheModel(AIModel model) {
    _modelCache['${model.providerId}:${model.id}'] = model;
  }

  /// Retrieve a cached model.
  AIModel? getCachedModel(String providerId, String modelId) {
    return _modelCache['$providerId:$modelId'];
  }

  /// Cache multiple models.
  void cacheModels(List<AIModel> models) {
    for (final model in models) {
      cacheModel(model);
    }
  }

  /// Dispose all adapters and clear caches.
  void disposeAll() {
    for (final adapter in _adapters.values) {
      adapter.dispose();
    }
    _adapters.clear();
    _modelCache.clear();
    _defaultProviderId = null;
  }
}
