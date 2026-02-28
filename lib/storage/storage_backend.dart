/// Abstract storage interface for secure key management.
///
/// This abstraction allows swapping flutter_secure_storage for
/// an in-memory implementation in tests.
abstract class StorageBackend {
  /// Read a value by key. Returns null if not found.
  Future<String?> read(String key);

  /// Write a key-value pair.
  Future<void> write(String key, String value);

  /// Delete a key.
  Future<void> delete(String key);

  /// Check if a key exists.
  Future<bool> containsKey(String key);

  /// Read all key-value pairs.
  Future<Map<String, String>> readAll();

  /// Delete all stored values.
  Future<void> deleteAll();
}
