import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIClient', () {
    late AIClient client;

    setUp(() {
      client = AIClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('generate resolves provider and delegates', () async {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
        response: const AIResponse(text: 'Hello!', raw: {}),
      );
      client.registry.register(adapter);

      final response = await client.generate(
        AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
      );

      expect(response.text, 'Hello!');
    });

    test('generate with explicit providerId', () async {
      final adapter1 = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'provider-a',
          providerType: AIProviderType.openAI,
          apiKey: 'key1',
          isDefault: true,
        ),
        response: const AIResponse(text: 'From A', raw: {}),
      );
      final adapter2 = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'provider-b',
          providerType: AIProviderType.gemini,
          apiKey: 'key2',
        ),
        response: const AIResponse(text: 'From B', raw: {}),
      );
      client.registry.register(adapter1);
      client.registry.register(adapter2);

      final response = await client.generate(
        AIRequest(messages: [AIMessage.user('Hi')], model: 'gemini-1.5-pro'),
        providerId: 'provider-b',
      );

      expect(response.text, 'From B');
    });

    test('generate validates capabilities when model is cached', () async {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
        response: const AIResponse(text: 'ok', raw: {}),
      );
      client.registry.register(adapter);

      // Cache a text-only model.
      client.registry.cacheModel(
        const AIModel(
          id: 'text-only',
          providerId: 'test',
          displayName: 'Text Only',
          capabilities: AIModelCapabilities(supportsImageInput: false),
        ),
      );

      // Request with image content should be blocked.
      expect(
        () => client.generate(
          AIRequest(
            messages: [
              AIMessage(
                role: AIRole.user,
                content: [AIContentBlock.imageUrl('https://img.com/x.png')],
              ),
            ],
            model: 'text-only',
          ),
        ),
        throwsA(isA<AIUnsupportedInputException>()),
      );
    });

    test('generate skips validation when model is not cached', () async {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
        response: const AIResponse(text: 'ok', raw: {}),
      );
      client.registry.register(adapter);

      // No model cached, so validation is skipped.
      final response = await client.generate(
        AIRequest(
          messages: [
            AIMessage(
              role: AIRole.user,
              content: [AIContentBlock.imageUrl('https://img.com/x.png')],
            ),
          ],
          model: 'unknown-model',
        ),
      );

      expect(response.text, 'ok');
    });

    test(
      'generate skips validation when validateCapabilities is false',
      () async {
        final adapter = _FakeAdapter(
          config: const AIProviderConfig(
            id: 'test',
            providerType: AIProviderType.openAI,
            apiKey: 'key',
            isDefault: true,
          ),
          response: const AIResponse(text: 'ok', raw: {}),
        );
        client.registry.register(adapter);

        // Cache a text-only model.
        client.registry.cacheModel(
          const AIModel(
            id: 'text-only',
            providerId: 'test',
            displayName: 'Text Only',
            capabilities: AIModelCapabilities(supportsImageInput: false),
          ),
        );

        // With validation disabled, image content is allowed.
        final response = await client.generate(
          AIRequest(
            messages: [
              AIMessage(
                role: AIRole.user,
                content: [AIContentBlock.imageUrl('https://img.com/x.png')],
              ),
            ],
            model: 'text-only',
          ),
          validateCapabilities: false,
        );

        expect(response.text, 'ok');
      },
    );

    test('stream yields chunks from adapter', () async {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
        response: const AIResponse(text: '', raw: {}),
        streamChunks: [
          const AIStreamChunk(textDelta: 'Hello'),
          const AIStreamChunk(textDelta: ' World'),
          AIStreamChunk.done(finishReason: 'stop'),
        ],
      );
      client.registry.register(adapter);

      final chunks = await client
          .stream(AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'))
          .toList();

      expect(chunks.length, 3);
      expect(chunks[0].textDelta, 'Hello');
      expect(chunks[1].textDelta, ' World');
      expect(chunks[2].isDone, isTrue);
    });

    test('generateText convenience method', () async {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
        response: const AIResponse(text: 'Hello!', raw: {}),
      );
      client.registry.register(adapter);

      final text = await client.generateText(
        'Hi',
        model: 'gpt-4o',
        temperature: 0.5,
      );

      expect(text, 'Hello!');
    });

    test('getModels fetches and caches models', () async {
      final adapter = _FakeAdapter(
        config: const AIProviderConfig(
          id: 'test',
          providerType: AIProviderType.openAI,
          apiKey: 'key',
          isDefault: true,
        ),
        response: const AIResponse(text: '', raw: {}),
        modelList: [
          const AIModel(
            id: 'gpt-4o',
            providerId: 'test',
            displayName: 'GPT-4o',
            capabilities: AIModelCapabilities(supportsImageInput: true),
          ),
        ],
      );
      client.registry.register(adapter);

      final models = await client.getModels();
      expect(models.length, 1);
      expect(models.first.id, 'gpt-4o');

      // Model should be cached.
      final cached = client.registry.getCachedModel('test', 'gpt-4o');
      expect(cached, isNotNull);
    });

    test('throws when no provider registered', () {
      expect(
        () => client.generate(
          AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
        ),
        throwsA(isA<AIException>()),
      );
    });
  });
}

class _FakeAdapter implements AIProviderAdapter {
  @override
  final AIProviderConfig config;
  final AIResponse response;
  final List<AIStreamChunk> streamChunks;
  final List<AIModel> modelList;

  _FakeAdapter({
    required this.config,
    required this.response,
    this.streamChunks = const [],
    this.modelList = const [],
  });

  @override
  String get providerId => config.id;

  @override
  Future<AIResponse> generate(AIRequest request) async => response;

  @override
  Stream<AIStreamChunk> stream(AIRequest request) =>
      Stream.fromIterable(streamChunks);

  @override
  Future<List<AIModel>> fetchModels() async => modelList;

  @override
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
