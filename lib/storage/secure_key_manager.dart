import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage_backend.dart';
import '../models/ai_provider_config.dart';

/// [StorageBackend] implementation using flutter_secure_storage.
class FlutterSecureStorageBackend implements StorageBackend {
  final FlutterSecureStorage _storage;

  FlutterSecureStorageBackend({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Manages API keys for AI providers using secure storage.
class SecureKeyManager {
  static const String _keyPrefix = 'ai_core_api_key_';

  final StorageBackend _storage;

  SecureKeyManager({required StorageBackend storage}) : _storage = storage;

  /// Convenience constructor using flutter_secure_storage.
  factory SecureKeyManager.secure({FlutterSecureStorage? storage}) =>
      SecureKeyManager(
        storage: FlutterSecureStorageBackend(storage: storage),
      );

  /// Store an API key for a provider.
  Future<void> storeKey(String providerId, String apiKey) =>
      _storage.write('$_keyPrefix$providerId', apiKey);

  /// Retrieve an API key for a provider.
  Future<String?> retrieveKey(String providerId) =>
      _storage.read('$_keyPrefix$providerId');

  /// Delete an API key for a provider.
  Future<void> deleteKey(String providerId) =>
      _storage.delete('$_keyPrefix$providerId');

  /// Check if a key exists for a provider.
  Future<bool> hasKey(String providerId) =>
      _storage.containsKey('$_keyPrefix$providerId');

  /// Build an [AIProviderConfig] by loading the API key from storage.
  ///
  /// Throws [StateError] if no key is stored for this provider.
  Future<AIProviderConfig> buildConfig({
    required String id,
    required AIProviderType providerType,
    String? baseUrl,
    bool isDefault = false,
    Map<String, String>? extraHeaders,
  }) async {
    final apiKey = await retrieveKey(id);
    if (apiKey == null) {
      throw StateError(
        'No API key stored for provider "$id". Call storeKey() first.',
      );
    }
    return AIProviderConfig(
      id: id,
      providerType: providerType,
      apiKey: apiKey,
      baseUrl: baseUrl,
      isDefault: isDefault,
      extraHeaders: extraHeaders,
    );
  }
}
