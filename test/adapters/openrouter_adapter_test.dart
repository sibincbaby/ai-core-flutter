import 'dart:convert';

import 'package:ai_core/ai_core.dart';
import 'package:ai_core/models/openrouter_options.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_dio_adapter.dart';

void main() {
  group('OpenRouterAdapter', () {
    late Dio dio;
    late MockDioAdapter mockAdapter;
    late OpenRouterAdapter adapter;

    setUp(() {
      dio = Dio();
      mockAdapter = MockDioAdapter();
      dio.httpClientAdapter = mockAdapter;
      adapter = OpenRouterAdapter(
        config: const AIProviderConfig(
          id: 'test-openrouter',
          providerType: AIProviderType.openRouter,
          apiKey: 'or-test-key',
        ),
        dio: dio,
        siteUrl: 'https://myapp.com',
        appName: 'MyApp',
      );
    });

    tearDown(() {
      adapter.dispose();
    });

    test('sets X-OpenRouter-Title header', () {
      expect(dio.options.headers['X-OpenRouter-Title'], 'MyApp');
      expect(dio.options.headers['HTTP-Referer'], 'https://myapp.com');
    });

    group('generate', () {
      test('uses OpenAI-compatible format', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'Hello!'},
                  'finish_reason': 'stop',
                },
              ],
              'model': 'openai/gpt-4o',
              'usage': {
                'prompt_tokens': 5,
                'completion_tokens': 3,
                'total_tokens': 8,
              },
            },
          ),
        );

        final response = await adapter.generate(
          AIRequest(messages: [AIMessage.user('Hi')], model: 'openai/gpt-4o'),
        );

        expect(response.text, 'Hello!');
        expect(response.model, 'openai/gpt-4o');
        expect(response.finishReason, 'stop');

        final captured = mockAdapter.capturedRequests.first;
        expect(captured.path, contains('/v1/chat/completions'));
      });
    });

    group('stream', () {
      test('parses SSE chunks like OpenAI', () async {
        final sseEvents = [
          jsonEncode({
            'choices': [
              {
                'delta': {'content': 'Hello'},
                'finish_reason': null,
              },
            ],
            'model': 'openai/gpt-4o',
          }),
          jsonEncode({
            'choices': [
              {'delta': {}, 'finish_reason': 'stop'},
            ],
            'model': 'openai/gpt-4o',
          }),
          '[DONE]',
        ];

        mockAdapter.enqueue(MockResponse.sse(sseEvents));

        final chunks = await adapter
            .stream(
              AIRequest(
                messages: [AIMessage.user('Hi')],
                model: 'openai/gpt-4o',
              ),
            )
            .toList();

        final contentChunks = chunks
            .where((c) => c.textDelta.isNotEmpty)
            .toList();
        expect(contentChunks.first.textDelta, 'Hello');
        expect(chunks.last.isDone, isTrue);
      });
    });

    group('fetchModels', () {
      test('parses OpenRouter model format with capabilities', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'data': [
                {
                  'id': 'openai/gpt-4o',
                  'name': 'OpenAI: GPT-4o',
                  'context_length': 128000,
                  'architecture': {
                    'modality': 'text+image->text',
                    'input_modalities': ['text', 'image'],
                    'output_modalities': ['text'],
                  },
                  'supported_parameters': [
                    'tools',
                    'response_format',
                    'temperature',
                    'max_tokens',
                  ],
                },
                {
                  'id': 'anthropic/claude-3.5-sonnet',
                  'name': 'Anthropic: Claude 3.5 Sonnet',
                  'context_length': 200000,
                  'architecture': {
                    'modality': 'text+image->text',
                    'input_modalities': ['text', 'image'],
                    'output_modalities': ['text'],
                  },
                  'supported_parameters': ['tools', 'structured_outputs'],
                },
                {
                  'id': 'meta-llama/llama-3-70b',
                  'name': 'Meta: Llama 3 70B',
                  'context_length': 8192,
                  'architecture': {
                    'modality': 'text->text',
                    'input_modalities': ['text'],
                    'output_modalities': ['text'],
                  },
                },
              ],
            },
          ),
        );

        final models = await adapter.fetchModels();

        expect(models.length, 3);

        final gpt4o = models.firstWhere((m) => m.id == 'openai/gpt-4o');
        expect(gpt4o.displayName, 'OpenAI: GPT-4o');
        expect(gpt4o.contextWindow, 128000);
        expect(gpt4o.capabilities.supportsText, isTrue);
        expect(gpt4o.capabilities.supportsImageInput, isTrue);
        expect(gpt4o.capabilities.supportsAudioInput, isFalse);
        expect(gpt4o.capabilities.supportsToolCalling, isTrue);
        expect(gpt4o.capabilities.supportsJsonMode, isTrue);

        final claude = models.firstWhere(
          (m) => m.id == 'anthropic/claude-3.5-sonnet',
        );
        expect(claude.capabilities.supportsToolCalling, isTrue);
        expect(claude.capabilities.supportsJsonMode, isTrue);

        final llama = models.firstWhere(
          (m) => m.id == 'meta-llama/llama-3-70b',
        );
        expect(llama.capabilities.supportsText, isTrue);
        expect(llama.capabilities.supportsImageInput, isFalse);
        expect(llama.capabilities.supportsToolCalling, isFalse);
        expect(llama.capabilities.supportsJsonMode, isFalse);
      });

      test('caches capabilities for capabilitiesFor lookup', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'data': [
                {
                  'id': 'openai/gpt-4o',
                  'name': 'GPT-4o',
                  'context_length': 128000,
                  'architecture': {
                    'input_modalities': ['text', 'image'],
                    'output_modalities': ['text'],
                  },
                  'supported_parameters': ['tools', 'response_format'],
                },
              ],
            },
          ),
        );

        // Before fetchModels, capabilitiesFor returns defaults.
        final before = adapter.capabilitiesFor('openai/gpt-4o');
        expect(before.supportsToolCalling, isFalse);

        await adapter.fetchModels();

        // After fetchModels, capabilitiesFor returns cached data.
        final after = adapter.capabilitiesFor('openai/gpt-4o');
        expect(after.supportsToolCalling, isTrue);
        expect(after.supportsJsonMode, isTrue);
        expect(after.supportsImageInput, isTrue);
        expect(after.maxContextWindow, 128000);
      });
    });

    group('OpenRouterOptions', () {
      test('generates correct extra map for provider preferences', () {
        final options = OpenRouterOptions(
          providerPreferences: ProviderPreferences(
            sort: 'throughput',
            order: ['anthropic', 'openai'],
            allowFallbacks: false,
            requireParameters: true,
            dataCollection: 'deny',
          ),
          user: 'user-123',
        );

        final map = options.toMap();
        final provider = map['provider'] as Map<String, dynamic>;

        expect(provider['sort'], 'throughput');
        expect(provider['order'], ['anthropic', 'openai']);
        expect(provider['allow_fallbacks'], isFalse);
        expect(provider['require_parameters'], isTrue);
        expect(provider['data_collection'], 'deny');
        expect(map['user'], 'user-123');
      });

      test('generates correct extra map for model fallbacks', () {
        final options = OpenRouterOptions(
          models: ['openai/gpt-5.1', 'anthropic/claude-sonnet-4.5'],
          route: 'fallback',
        );

        final map = options.toMap();
        expect(map['models'], [
          'openai/gpt-5.1',
          'anthropic/claude-sonnet-4.5',
        ]);
        expect(map['route'], 'fallback');
      });

      test('generates correct extra map for plugins', () {
        final options = OpenRouterOptions(
          plugins: [
            OpenRouterPlugin.web(maxResults: 3),
            OpenRouterPlugin.responseHealing(),
          ],
          transforms: ['middle-out'],
        );

        final map = options.toMap();
        final plugins = map['plugins'] as List<Map<String, dynamic>>;
        expect(plugins.length, 2);
        expect(plugins[0]['id'], 'web');
        expect(plugins[0]['max_results'], 3);
        expect(plugins[1]['id'], 'response-healing');
        expect(map['transforms'], ['middle-out']);
      });

      test('passes through to request body via extra', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'Hi'},
                  'finish_reason': 'stop',
                },
              ],
              'model': 'openai/gpt-5.1',
              'usage': {
                'prompt_tokens': 5,
                'completion_tokens': 2,
                'total_tokens': 7,
              },
            },
          ),
        );

        await adapter.generate(
          AIRequest(
            messages: [AIMessage.user('Hello')],
            model: 'openai/gpt-5.1',
            extra: OpenRouterOptions(
              providerPreferences: ProviderPreferences(sort: 'throughput'),
              plugins: [OpenRouterPlugin.web()],
              user: 'u-1',
            ).toMap(),
          ),
        );

        final captured = mockAdapter.capturedRequests.first;
        final body = captured.data as Map<String, dynamic>;
        expect(body['provider'], isA<Map<String, dynamic>>());
        expect((body['provider'] as Map)['sort'], 'throughput');
        expect(body['plugins'], isA<List>());
        expect(body['user'], 'u-1');
      });
    });
  });
}
