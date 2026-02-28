import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_storage_backend.dart';

void main() {
  group('SecureKeyManager', () {
    late MockStorageBackend storage;
    late SecureKeyManager manager;

    setUp(() {
      storage = MockStorageBackend();
      manager = SecureKeyManager(storage: storage);
    });

    test('storeKey and retrieveKey round-trip', () async {
      await manager.storeKey('openai', 'sk-test-123');
      final key = await manager.retrieveKey('openai');
      expect(key, 'sk-test-123');
    });

    test('retrieveKey returns null for unknown provider', () async {
      final key = await manager.retrieveKey('unknown');
      expect(key, isNull);
    });

    test('deleteKey removes stored key', () async {
      await manager.storeKey('openai', 'sk-test-123');
      await manager.deleteKey('openai');
      final key = await manager.retrieveKey('openai');
      expect(key, isNull);
    });

    test('hasKey returns true for stored key', () async {
      await manager.storeKey('gemini', 'gem-key');
      expect(await manager.hasKey('gemini'), isTrue);
    });

    test('hasKey returns false for missing key', () async {
      expect(await manager.hasKey('missing'), isFalse);
    });

    test('buildConfig creates AIProviderConfig from stored key', () async {
      await manager.storeKey('my-openai', 'sk-secret');
      final config = await manager.buildConfig(
        id: 'my-openai',
        providerType: AIProviderType.openAI,
        isDefault: true,
      );

      expect(config.id, 'my-openai');
      expect(config.providerType, AIProviderType.openAI);
      expect(config.apiKey, 'sk-secret');
      expect(config.isDefault, isTrue);
      expect(config.baseUrl, isNull);
    });

    test('buildConfig throws StateError when no key stored', () async {
      expect(
        () => manager.buildConfig(
          id: 'missing',
          providerType: AIProviderType.openAI,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('multiple providers can be stored independently', () async {
      await manager.storeKey('openai', 'sk-openai');
      await manager.storeKey('gemini', 'gem-key');
      await manager.storeKey('openrouter', 'or-key');

      expect(await manager.retrieveKey('openai'), 'sk-openai');
      expect(await manager.retrieveKey('gemini'), 'gem-key');
      expect(await manager.retrieveKey('openrouter'), 'or-key');
    });
  });
}
