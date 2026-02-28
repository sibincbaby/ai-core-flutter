import 'package:ai_core/storage/storage_backend.dart';

/// In-memory storage backend for testing.
class MockStorageBackend implements StorageBackend {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll() async => Map.from(_store);

  @override
  Future<void> deleteAll() async => _store.clear();
}
