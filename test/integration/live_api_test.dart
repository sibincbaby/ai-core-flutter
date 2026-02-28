import 'dart:io';

import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration tests that hit real provider APIs.
///
/// Requires a .env file at project root with:
///   OPENAI_API_KEY=...
///   GEMINI_API_KEY=...
///   OPENROUTER_API_KEY=...
///
/// Run with: flutter test test/integration/
void main() {
  late Map<String, String> env;

  setUpAll(() {
    final envFile = File('.env');
    if (!envFile.existsSync()) {
      fail('.env file not found. Create one with API keys.');
    }
    env = {};
    for (final line in envFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf('=');
      if (idx > 0) {
        env[trimmed.substring(0, idx)] = trimmed.substring(idx + 1);
      }
    }
  });

  group('OpenAI Integration', () {
    late AIClient client;

    setUp(() {
      final apiKey = env['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('OPENAI_API_KEY not set in .env');
      }
      client = AIClient();
      client.registry.register(OpenAIAdapter(
        config: AIProviderConfig(
          id: 'openai',
          providerType: AIProviderType.openAI,
          apiKey: apiKey,
          isDefault: true,
        ),
      ));
    });

    tearDown(() => client.dispose());

    test('generate text response', () async {
      final response = await client.generate(AIRequest(
        messages: [AIMessage.user('Say "hello" and nothing else.')],
        model: 'gpt-4o-mini',
        maxTokens: 10,
        temperature: 0,
      ));

      expect(response.text.toLowerCase(), contains('hello'));
      expect(response.finishReason, isNotNull);
      expect(response.usage, isNotNull);
      print('OpenAI generate: "${response.text}" '
          '(${response.usage?.totalTokens} tokens)');
    });

    test('stream text response', () async {
      final buffer = StringBuffer();
      var chunkCount = 0;
      var gotDone = false;

      await for (final chunk in client.stream(AIRequest(
        messages: [AIMessage.user('Count from 1 to 3.')],
        model: 'gpt-4o-mini',
        maxTokens: 30,
        temperature: 0,
      ))) {
        buffer.write(chunk.textDelta);
        chunkCount++;
        if (chunk.isDone) gotDone = true;
      }

      expect(buffer.toString(), isNotEmpty);
      expect(chunkCount, greaterThan(1));
      expect(gotDone, isTrue);
      print('OpenAI stream: "$buffer" ($chunkCount chunks)');
    });

    test('fetch models', () async {
      final models = await client.getModels();

      expect(models, isNotEmpty);
      final ids = models.map((m) => m.id).toList();
      expect(ids.any((id) => id.startsWith('gpt-')), isTrue);
      print('OpenAI models: ${ids.take(5).join(', ')}...');
    });

    test('generateText convenience', () async {
      final text = await client.generateText(
        'What is 2+2? Answer with just the number.',
        model: 'gpt-4o-mini',
        maxTokens: 5,
        temperature: 0,
      );

      expect(text, contains('4'));
      print('OpenAI generateText: "$text"');
    });
  });

  group('Gemini Integration', () {
    late AIClient client;

    setUp(() {
      final apiKey = env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('GEMINI_API_KEY not set in .env');
      }
      client = AIClient();
      client.registry.register(GeminiAdapter(
        config: AIProviderConfig(
          id: 'gemini',
          providerType: AIProviderType.gemini,
          apiKey: apiKey,
          isDefault: true,
        ),
      ));
    });

    tearDown(() => client.dispose());

    test('generate text response', () async {
      final response = await client.generate(AIRequest(
        messages: [AIMessage.user('Say "hello" and nothing else.')],
        model: 'gemini-2.0-flash',
        maxTokens: 10,
        temperature: 0,
      ));

      expect(response.text.toLowerCase(), contains('hello'));
      expect(response.finishReason, isNotNull);
      print('Gemini generate: "${response.text}"');
    });

    test('generate with system instruction', () async {
      final response = await client.generate(AIRequest(
        messages: [
          AIMessage.system('You only respond in uppercase.'),
          AIMessage.user('Say hi'),
        ],
        model: 'gemini-2.0-flash',
        maxTokens: 10,
        temperature: 0,
      ));

      // Should be uppercase due to system instruction.
      expect(response.text, isNotEmpty);
      print('Gemini system instruction: "${response.text}"');
    });

    test('stream text response', () async {
      final buffer = StringBuffer();
      var chunkCount = 0;

      await for (final chunk in client.stream(AIRequest(
        messages: [AIMessage.user('Count from 1 to 3.')],
        model: 'gemini-2.0-flash',
        maxTokens: 30,
        temperature: 0,
      ))) {
        buffer.write(chunk.textDelta);
        chunkCount++;
      }

      expect(buffer.toString(), isNotEmpty);
      expect(chunkCount, greaterThan(1));
      print('Gemini stream: "$buffer" ($chunkCount chunks)');
    });

    test('fetch models', () async {
      final models = await client.getModels();

      expect(models, isNotEmpty);
      final ids = models.map((m) => m.id).toList();
      expect(ids.any((id) => id.contains('gemini')), isTrue);
      print('Gemini models: ${ids.take(5).join(', ')}...');
    });
  });

  group('OpenRouter Integration', () {
    late AIClient client;

    setUp(() {
      final apiKey = env['OPENROUTER_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('OPENROUTER_API_KEY not set in .env');
      }
      client = AIClient();
      client.registry.register(OpenRouterAdapter(
        config: AIProviderConfig(
          id: 'openrouter',
          providerType: AIProviderType.openRouter,
          apiKey: apiKey,
          isDefault: true,
        ),
        appName: 'AI Core SDK Test',
      ));
    });

    tearDown(() => client.dispose());

    test('generate text response', () async {
      final response = await client.generate(AIRequest(
        messages: [AIMessage.user('Say "hello" and nothing else.')],
        model: 'openai/gpt-4o-mini',
        maxTokens: 10,
        temperature: 0,
      ));

      expect(response.text.toLowerCase(), contains('hello'));
      print('OpenRouter generate: "${response.text}"');
    });

    test('stream text response', () async {
      final buffer = StringBuffer();
      var chunkCount = 0;

      await for (final chunk in client.stream(AIRequest(
        messages: [AIMessage.user('Count from 1 to 3.')],
        model: 'openai/gpt-4o-mini',
        maxTokens: 30,
        temperature: 0,
      ))) {
        buffer.write(chunk.textDelta);
        chunkCount++;
      }

      expect(buffer.toString(), isNotEmpty);
      expect(chunkCount, greaterThan(1));
      print('OpenRouter stream: "$buffer" ($chunkCount chunks)');
    });

    test('fetch models', () async {
      final models = await client.getModels();

      expect(models, isNotEmpty);
      expect(models.length, greaterThan(10));

      // Check capability parsing.
      final hasImageModel = models.any((m) =>
          m.capabilities.supportsImageInput);
      expect(hasImageModel, isTrue);
      print('OpenRouter models: ${models.length} total');
    });
  });

  group('Multi-Provider Integration', () {
    late AIClient client;

    setUp(() {
      client = AIClient();

      final openaiKey = env['OPENAI_API_KEY'];
      final geminiKey = env['GEMINI_API_KEY'];

      if (openaiKey == null || geminiKey == null) {
        fail('Both OPENAI_API_KEY and GEMINI_API_KEY required');
      }

      client.registry.register(OpenAIAdapter(
        config: AIProviderConfig(
          id: 'openai',
          providerType: AIProviderType.openAI,
          apiKey: openaiKey,
          isDefault: true,
        ),
      ));

      client.registry.register(GeminiAdapter(
        config: AIProviderConfig(
          id: 'gemini',
          providerType: AIProviderType.gemini,
          apiKey: geminiKey,
        ),
      ));
    });

    tearDown(() => client.dispose());

    test('switch between providers', () async {
      // Default provider (OpenAI).
      final openaiResponse = await client.generate(AIRequest(
        messages: [AIMessage.user('Say "openai" and nothing else.')],
        model: 'gpt-4o-mini',
        maxTokens: 10,
        temperature: 0,
      ));
      expect(openaiResponse.text.toLowerCase(), contains('openai'));

      // Explicit Gemini.
      final geminiResponse = await client.generate(
        AIRequest(
          messages: [AIMessage.user('Say "gemini" and nothing else.')],
          model: 'gemini-2.0-flash',
          maxTokens: 10,
          temperature: 0,
        ),
        providerId: 'gemini',
      );
      expect(geminiResponse.text.toLowerCase(), contains('gemini'));

      print('Multi-provider: OpenAI="${openaiResponse.text}", '
          'Gemini="${geminiResponse.text}"');
    });

    test('capability validation blocks unsupported input', () async {
      // Fetch and cache models for OpenAI.
      await client.getModels(providerId: 'openai');

      // gpt-3.5-turbo doesn't support images (per our registry).
      // Cache it explicitly as text-only.
      client.registry.cacheModel(const AIModel(
        id: 'gpt-3.5-turbo',
        providerId: 'openai',
        displayName: 'GPT-3.5 Turbo',
        capabilities: AIModelCapabilities(
          supportsImageInput: false,
          supportsAudioInput: false,
        ),
      ));

      expect(
        () => client.generate(AIRequest(
          messages: [
            AIMessage(role: AIRole.user, content: [
              AIContentBlock.imageUrl('https://example.com/img.png'),
            ]),
          ],
          model: 'gpt-3.5-turbo',
        )),
        throwsA(isA<AIUnsupportedInputException>()),
      );

      print('Capability validation: correctly blocked image input for '
          'text-only model');
    });
  });

  group('Error Handling Integration', () {
    late AIClient client;

    setUp(() {
      client = AIClient();
      client.registry.register(OpenAIAdapter(
        config: const AIProviderConfig(
          id: 'bad-openai',
          providerType: AIProviderType.openAI,
          apiKey: 'sk-invalid-key-12345',
          isDefault: true,
        ),
      ));
    });

    tearDown(() => client.dispose());

    test('invalid API key throws unauthorized', () async {
      expect(
        () => client.generate(AIRequest(
          messages: [AIMessage.user('Hi')],
          model: 'gpt-4o-mini',
        )),
        throwsA(isA<AIException>().having(
          (e) => e.type,
          'type',
          AIErrorType.unauthorized,
        )),
      );

      print('Error handling: unauthorized correctly detected');
    });
  });
}
