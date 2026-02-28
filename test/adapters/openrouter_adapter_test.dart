import 'dart:convert';

import 'package:ai_core/ai_core.dart';
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

    group('generate', () {
      test('uses OpenAI-compatible format', () async {
        mockAdapter.enqueue(MockResponse(
          body: {
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Hello!'},
                'finish_reason': 'stop',
              }
            ],
            'model': 'openai/gpt-4o',
            'usage': {
              'prompt_tokens': 5,
              'completion_tokens': 3,
              'total_tokens': 8,
            },
          },
        ));

        final response = await adapter.generate(AIRequest(
          messages: [AIMessage.user('Hi')],
          model: 'openai/gpt-4o',
        ));

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
              }
            ],
            'model': 'openai/gpt-4o',
          }),
          jsonEncode({
            'choices': [
              {
                'delta': {},
                'finish_reason': 'stop',
              }
            ],
            'model': 'openai/gpt-4o',
          }),
          '[DONE]',
        ];

        mockAdapter.enqueue(MockResponse.sse(sseEvents));

        final chunks = await adapter
            .stream(AIRequest(
              messages: [AIMessage.user('Hi')],
              model: 'openai/gpt-4o',
            ))
            .toList();

        final contentChunks =
            chunks.where((c) => c.textDelta.isNotEmpty).toList();
        expect(contentChunks.first.textDelta, 'Hello');
        expect(chunks.last.isDone, isTrue);
      });
    });

    group('fetchModels', () {
      test('parses OpenRouter model format with capabilities', () async {
        mockAdapter.enqueue(MockResponse(
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
        ));

        final models = await adapter.fetchModels();

        expect(models.length, 3);

        final gpt4o =
            models.firstWhere((m) => m.id == 'openai/gpt-4o');
        expect(gpt4o.displayName, 'OpenAI: GPT-4o');
        expect(gpt4o.contextWindow, 128000);
        expect(gpt4o.capabilities.supportsText, isTrue);
        expect(gpt4o.capabilities.supportsImageInput, isTrue);
        expect(gpt4o.capabilities.supportsAudioInput, isFalse);

        final llama = models
            .firstWhere((m) => m.id == 'meta-llama/llama-3-70b');
        expect(llama.capabilities.supportsText, isTrue);
        expect(llama.capabilities.supportsImageInput, isFalse);
      });
    });
  });
}
