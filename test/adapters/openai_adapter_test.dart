import 'dart:convert';

import 'package:ai_core/ai_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_dio_adapter.dart';

void main() {
  group('OpenAIAdapter', () {
    late Dio dio;
    late MockDioAdapter mockAdapter;
    late OpenAIAdapter adapter;

    setUp(() {
      dio = Dio();
      mockAdapter = MockDioAdapter();
      dio.httpClientAdapter = mockAdapter;
      adapter = OpenAIAdapter(
        config: const AIProviderConfig(
          id: 'test-openai',
          providerType: AIProviderType.openAI,
          apiKey: 'sk-test',
        ),
        dio: dio,
      );
    });

    tearDown(() {
      adapter.dispose();
    });

    group('generate', () {
      test('sends correct request and parses response', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'id': 'chatcmpl-123',
              'object': 'chat.completion',
              'model': 'gpt-4o',
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': 'Hello!'},
                  'finish_reason': 'stop',
                },
              ],
              'usage': {
                'prompt_tokens': 10,
                'completion_tokens': 5,
                'total_tokens': 15,
              },
            },
          ),
        );

        final response = await adapter.generate(
          AIRequest(
            messages: [AIMessage.user('Hi')],
            model: 'gpt-4o',
            temperature: 0.7,
            maxTokens: 100,
          ),
        );

        expect(response.text, 'Hello!');
        expect(response.model, 'gpt-4o');
        expect(response.finishReason, 'stop');
        expect(response.usage?.promptTokens, 10);
        expect(response.usage?.completionTokens, 5);
        expect(response.usage?.totalTokens, 15);

        // Verify request body.
        final capturedRequest = mockAdapter.capturedRequests.first;
        expect(capturedRequest.path, contains('/v1/chat/completions'));
        final body = capturedRequest.data as Map<String, dynamic>;
        expect(body['model'], 'gpt-4o');
        expect(body['temperature'], 0.7);
        expect(body['max_tokens'], 100);
        expect(body['stream'], isNull);
      });

      test('text-only message uses string content shorthand', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
            },
          ),
        );

        await adapter.generate(
          AIRequest(messages: [AIMessage.user('Hello')], model: 'gpt-4o'),
        );

        final body =
            mockAdapter.capturedRequests.first.data as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final firstMsg = messages[0] as Map<String, dynamic>;
        // String shorthand, not array.
        expect(firstMsg['content'], isA<String>());
        expect(firstMsg['content'], 'Hello');
      });

      test('multimodal message uses array content format', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
            },
          ),
        );

        await adapter.generate(
          AIRequest(
            messages: [
              AIMessage(
                role: AIRole.user,
                content: [
                  AIContentBlock.text('Describe this'),
                  AIContentBlock.imageUrl('https://example.com/img.png'),
                ],
              ),
            ],
            model: 'gpt-4o',
          ),
        );

        final body =
            mockAdapter.capturedRequests.first.data as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final firstMsg = messages[0] as Map<String, dynamic>;
        // Array format for multimodal.
        expect(firstMsg['content'], isA<List>());
        final parts = firstMsg['content'] as List<dynamic>;
        expect(parts.length, 2);
        expect((parts[0] as Map<String, dynamic>)['type'], 'text');
        expect((parts[1] as Map<String, dynamic>)['type'], 'image_url');
      });

      test('handles 401 error', () async {
        mockAdapter.enqueue(
          MockResponse(
            statusCode: 401,
            body: {
              'error': {
                'message': 'Invalid API key',
                'type': 'invalid_api_key',
              },
            },
          ),
        );

        expect(
          () => adapter.generate(
            AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
          ),
          throwsA(
            isA<AIException>().having(
              (e) => e.type,
              'type',
              AIErrorType.unauthorized,
            ),
          ),
        );
      });

      test('handles 429 rate limit error', () async {
        mockAdapter.enqueue(
          MockResponse(
            statusCode: 429,
            body: {
              'error': {'message': 'Rate limit exceeded'},
            },
          ),
        );

        expect(
          () => adapter.generate(
            AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
          ),
          throwsA(
            isA<AIException>().having(
              (e) => e.type,
              'type',
              AIErrorType.rateLimited,
            ),
          ),
        );
      });
    });

    group('stream', () {
      test('parses SSE chunks correctly', () async {
        final sseEvents = [
          jsonEncode({
            'choices': [
              {
                'delta': {'role': 'assistant'},
                'finish_reason': null,
              },
            ],
            'model': 'gpt-4o',
          }),
          jsonEncode({
            'choices': [
              {
                'delta': {'content': 'Hello'},
                'finish_reason': null,
              },
            ],
            'model': 'gpt-4o',
          }),
          jsonEncode({
            'choices': [
              {
                'delta': {'content': ' world'},
                'finish_reason': null,
              },
            ],
            'model': 'gpt-4o',
          }),
          jsonEncode({
            'choices': [
              {'delta': {}, 'finish_reason': 'stop'},
            ],
            'model': 'gpt-4o',
          }),
          '[DONE]',
        ];

        mockAdapter.enqueue(MockResponse.sse(sseEvents));

        final chunks = await adapter
            .stream(
              AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
            )
            .toList();

        // Filter to chunks with actual content.
        final contentChunks = chunks
            .where((c) => c.textDelta.isNotEmpty || c.isDone)
            .toList();

        expect(contentChunks.length, greaterThanOrEqualTo(2));
        expect(contentChunks.first.textDelta, 'Hello');

        // Last chunk should be done.
        expect(chunks.last.isDone, isTrue);
      });
    });

    group('fetchModels', () {
      test('fetches and filters chat models', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'data': [
                {'id': 'gpt-4o', 'object': 'model'},
                {'id': 'gpt-3.5-turbo', 'object': 'model'},
                {'id': 'dall-e-3', 'object': 'model'},
                {'id': 'whisper-1', 'object': 'model'},
                {'id': 'o1-mini', 'object': 'model'},
              ],
            },
          ),
        );

        final models = await adapter.fetchModels();

        final ids = models.map((m) => m.id).toList();
        expect(ids, contains('gpt-4o'));
        expect(ids, contains('gpt-3.5-turbo'));
        expect(ids, contains('o1-mini'));
        // Non-chat models filtered out.
        expect(ids, isNot(contains('dall-e-3')));
        expect(ids, isNot(contains('whisper-1')));

        // Verify capabilities.
        final gpt4o = models.firstWhere((m) => m.id == 'gpt-4o');
        expect(gpt4o.capabilities.supportsImageInput, isTrue);

        final gpt35 = models.firstWhere((m) => m.id == 'gpt-3.5-turbo');
        expect(gpt35.capabilities.supportsImageInput, isFalse);
      });

      test('exclusion filter includes unknown model families', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'data': [
                {'id': 'gpt-6-turbo', 'object': 'model'},
                {'id': 'nova-1', 'object': 'model'},
                {'id': 'text-embedding-3-small', 'object': 'model'},
                {'id': 'tts-1', 'object': 'model'},
              ],
            },
          ),
        );

        final models = await adapter.fetchModels();
        final ids = models.map((m) => m.id).toList();

        // New/unknown chat families should be included by default.
        expect(ids, contains('gpt-6-turbo'));
        expect(ids, contains('nova-1'));
        // Non-chat models still excluded.
        expect(ids, isNot(contains('text-embedding-3-small')));
        expect(ids, isNot(contains('tts-1')));
      });

      test('unknown gpt model gets family-inferred capabilities', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'data': [
                {'id': 'gpt-6-turbo', 'object': 'model'},
              ],
            },
          ),
        );

        final models = await adapter.fetchModels();
        final model = models.first;

        expect(model.id, 'gpt-6-turbo');
        expect(model.capabilities.supportsImageInput, isTrue);
        expect(model.capabilities.supportsToolCalling, isTrue);
        expect(model.capabilities.supportsJsonMode, isTrue);
      });

      test(
        'unknown o-series model gets family-inferred capabilities',
        () async {
          mockAdapter.enqueue(
            MockResponse(
              body: {
                'data': [
                  {'id': 'o5-pro', 'object': 'model'},
                ],
              },
            ),
          );

          final models = await adapter.fetchModels();
          final model = models.first;

          expect(model.id, 'o5-pro');
          expect(model.capabilities.supportsImageInput, isTrue);
          expect(model.capabilities.supportsToolCalling, isTrue);
          expect(model.capabilities.supportsJsonMode, isTrue);
        },
      );

      test('completely unknown model gets text-only fallback', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'data': [
                {'id': 'nova-1', 'object': 'model'},
              ],
            },
          ),
        );

        final models = await adapter.fetchModels();
        final model = models.first;

        expect(model.id, 'nova-1');
        expect(model.capabilities.supportsImageInput, isFalse);
        expect(model.capabilities.supportsToolCalling, isFalse);
        expect(model.capabilities.supportsJsonMode, isFalse);
      });

      test('dated model ID matches known prefix', () async {
        mockAdapter.enqueue(
          MockResponse(
            body: {
              'data': [
                {'id': 'gpt-4o-2025-08-06', 'object': 'model'},
              ],
            },
          ),
        );

        final models = await adapter.fetchModels();
        final model = models.first;

        // Should match 'gpt-4o' via prefix, inheriting its capabilities.
        expect(model.capabilities.supportsImageInput, isTrue);
        expect(model.capabilities.supportsToolCalling, isTrue);
        expect(model.capabilities.supportsJsonMode, isTrue);
      });
    });
  });
}
