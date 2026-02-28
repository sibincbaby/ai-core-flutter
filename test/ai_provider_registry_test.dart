import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIProviderRegistry', () {
    late AIProviderRegistry registry;

    setUp(() {
      registry = AIProviderRegistry();
    });

    tearDown(() {
      registry.disposeAll();
    });

    test('register and resolve adapter', () {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test-openai',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
        ),
      );
      registry.register(adapter);

      final resolved = registry.resolve('test-openai');
      expect(resolved, same(adapter));
    });

    test('resolve throws when no providers registered', () {
      expect(() => registry.resolve(null), throwsA(isA<AIException>()));
    });

    test('resolve throws for unknown provider ID', () {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
        ),
      );
      registry.register(adapter);

      expect(() => registry.resolve('unknown'), throwsA(isA<AIException>()));
    });

    test('default provider is set when isDefault is true', () {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'default-provider',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
      );
      registry.register(adapter);

      expect(registry.defaultProviderId, 'default-provider');

      // Resolve with null uses default.
      final resolved = registry.resolve(null);
      expect(resolved, same(adapter));
    });

    test('setDefault changes default provider', () {
      final adapter1 = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'p1',
          providerType: AIProviderType.openAI,
          apiKey: 'key1',
          isDefault: true,
        ),
      );
      final adapter2 = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'p2',
          providerType: AIProviderType.gemini,
          apiKey: 'key2',
        ),
      );
      registry.register(adapter1);
      registry.register(adapter2);

      registry.setDefault('p2');
      expect(registry.defaultProviderId, 'p2');
    });

    test('setDefault throws for unregistered provider', () {
      expect(() => registry.setDefault('unknown'), throwsA(isA<AIException>()));
    });

    test('unregister removes adapter and disposes', () {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'removable',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
        ),
      );
      registry.register(adapter);
      registry.unregister('removable');

      expect(adapter.disposed, isTrue);
      expect(() => registry.resolve('removable'), throwsA(isA<AIException>()));
    });

    test('providerIds returns all registered IDs', () {
      registry.register(
        _FakeAdapter(
          config: const AIProviderConfig(
            id: 'a',
            providerType: AIProviderType.openAI,
            apiKey: 'key',
          ),
        ),
      );
      registry.register(
        _FakeAdapter(
          config: const AIProviderConfig(
            id: 'b',
            providerType: AIProviderType.gemini,
            apiKey: 'key',
          ),
        ),
      );

      expect(registry.providerIds, containsAll(['a', 'b']));
    });

    test('model caching works', () {
      const model = AIModel(
        id: 'gpt-4o',
        providerId: 'openai',
        displayName: 'GPT-4o',
        capabilities: AIModelCapabilities(supportsImageInput: true),
      );

      registry.cacheModel(model);
      final cached = registry.getCachedModel('openai', 'gpt-4o');

      expect(cached, isNotNull);
      expect(cached!.id, 'gpt-4o');
      expect(cached.capabilities.supportsImageInput, isTrue);
    });

    test('getCachedModel returns null for uncached model', () {
      expect(registry.getCachedModel('openai', 'unknown'), isNull);
    });

    test('disposeAll clears everything', () {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
      );
      registry.register(adapter);
      registry.cacheModel(
        const AIModel(
          id: 'model',
          providerId: 'test',
          displayName: 'Model',
          capabilities: AIModelCapabilities(),
        ),
      );

      registry.disposeAll();

      expect(adapter.disposed, isTrue);
      expect(registry.providerIds, isEmpty);
      expect(registry.defaultProviderId, isNull);
      expect(registry.getCachedModel('test', 'model'), isNull);
    });
  });
}

/// Minimal fake adapter for registry tests.
class _FakeAdapter implements AIProviderAdapter {
  @override
  final AIProviderConfig config;
  bool disposed = false;

  _FakeAdapter({required this.config});

  @override
  String get providerId => config.id;

  @override
  Future<AIResponse> generate(AIRequest request) async =>
      const AIResponse(text: 'fake', raw: {});

  @override
  Stream<AIStreamChunk> stream(AIRequest request) =>
      Stream.value(AIStreamChunk.done());

  @override
  Future<List<AIModel>> fetchModels() async => [];

  @override
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) {
    throw UnimplementedError();
  }

  @override
  void dispose() => disposed = true;
}
