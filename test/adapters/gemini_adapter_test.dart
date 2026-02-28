import 'dart:convert';

import 'package:ai_core/ai_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_dio_adapter.dart';

void main() {
  group('GeminiAdapter', () {
    late Dio dio;
    late MockDioAdapter mockAdapter;
    late GeminiAdapter adapter;

    setUp(() {
      dio = Dio();
      mockAdapter = MockDioAdapter();
      dio.httpClientAdapter = mockAdapter;
      adapter = GeminiAdapter(
        config: const AIProviderConfig(
          id: 'test-gemini',
          providerType: AIProviderType.gemini,
          apiKey: 'gem-test-key',
        ),
        dio: dio,
      );
    });

    tearDown(() {
      adapter.dispose();
    });

    group('generate', () {
      test('sends correct Gemini request format', () async {
        mockAdapter.enqueue(MockResponse(
          body: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Hello from Gemini!'},
                  ],
                  'role': 'model',
                },
                'finishReason': 'STOP',
              }
            ],
            'usageMetadata': {
              'promptTokenCount': 5,
              'candidatesTokenCount': 10,
              'totalTokenCount': 15,
            },
          },
        ));

        final response = await adapter.generate(AIRequest(
          messages: [
            AIMessage.system('You are helpful'),
            AIMessage.user('Hi'),
          ],
          model: 'gemini-1.5-pro',
          temperature: 0.5,
          maxTokens: 200,
        ));

        expect(response.text, 'Hello from Gemini!');
        expect(response.finishReason, 'stop');
        expect(response.usage?.promptTokens, 5);
        expect(response.usage?.completionTokens, 10);

        // Verify request.
        final captured = mockAdapter.capturedRequests.first;
        expect(
          captured.path,
          contains('/v1beta/models/gemini-1.5-pro:generateContent'),
        );
        final body = captured.data as Map<String, dynamic>;

        // System message extracted to systemInstruction.
        expect(body['systemInstruction'], isNotNull);
        final systemParts =
            body['systemInstruction']['parts'] as List<dynamic>;
        expect(
          (systemParts[0] as Map<String, dynamic>)['text'],
          'You are helpful',
        );

        // Contents should only have user message.
        final contents = body['contents'] as List<dynamic>;
        expect(contents.length, 1);
        expect(
          (contents[0] as Map<String, dynamic>)['role'],
          'user',
        );

        // Generation config present.
        final genConfig =
            body['generationConfig'] as Map<String, dynamic>;
        expect(genConfig['temperature'], 0.5);
        expect(genConfig['maxOutputTokens'], 200);
      });

      test('maps assistant role to model', () async {
        mockAdapter.enqueue(MockResponse(
          body: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'response'},
                  ],
                  'role': 'model',
                },
                'finishReason': 'STOP',
              }
            ],
          },
        ));

        await adapter.generate(AIRequest(
          messages: [
            AIMessage.user('Hi'),
            AIMessage.assistant('Hello'),
            AIMessage.user('How are you?'),
          ],
          model: 'gemini-1.5-pro',
        ));

        final body =
            mockAdapter.capturedRequests.first.data as Map<String, dynamic>;
        final contents = body['contents'] as List<dynamic>;
        expect(
          (contents[1] as Map<String, dynamic>)['role'],
          'model',
        );
      });

      test('handles safety-blocked prompt', () async {
        mockAdapter.enqueue(MockResponse(
          body: {
            'promptFeedback': {
              'blockReason': 'SAFETY',
            },
          },
        ));

        expect(
          () => adapter.generate(AIRequest(
            messages: [AIMessage.user('blocked content')],
            model: 'gemini-1.5-pro',
          )),
          throwsA(isA<AIException>().having(
            (e) => e.message,
            'message',
            contains('safety filter'),
          )),
        );
      });

      test('handles empty candidates', () async {
        mockAdapter.enqueue(MockResponse(
          body: {
            'candidates': <dynamic>[],
          },
        ));

        expect(
          () => adapter.generate(AIRequest(
            messages: [AIMessage.user('Hi')],
            model: 'gemini-1.5-pro',
          )),
          throwsA(isA<AIException>()),
        );
      });

      test('maps finish reasons correctly', () async {
        for (final entry in {
          'STOP': 'stop',
          'MAX_TOKENS': 'length',
          'SAFETY': 'content_filter',
        }.entries) {
          mockAdapter.enqueue(MockResponse(
            body: {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'response'},
                    ],
                  },
                  'finishReason': entry.key,
                }
              ],
            },
          ));

          final response = await adapter.generate(AIRequest(
            messages: [AIMessage.user('Hi')],
            model: 'gemini-1.5-pro',
          ));

          expect(response.finishReason, entry.value);
        }
      });
    });

    group('stream', () {
      test('parses Gemini SSE chunks', () async {
        final sseEvents = [
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Hello'},
                  ],
                  'role': 'model',
                },
              }
            ],
          }),
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': ' World'},
                  ],
                  'role': 'model',
                },
              }
            ],
          }),
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '!'},
                  ],
                  'role': 'model',
                },
                'finishReason': 'STOP',
              }
            ],
          }),
        ];

        mockAdapter.enqueue(MockResponse.sse(sseEvents));

        final chunks = await adapter
            .stream(AIRequest(
              messages: [AIMessage.user('Hi')],
              model: 'gemini-1.5-pro',
            ))
            .toList();

        expect(chunks.length, greaterThanOrEqualTo(3));
        expect(chunks[0].textDelta, 'Hello');
        expect(chunks[1].textDelta, ' World');
        expect(chunks[2].textDelta, '!');
        expect(chunks[2].isDone, isTrue);
        expect(chunks[2].finishReason, 'stop');
      });
    });

    group('fetchModels', () {
      test('fetches and parses Gemini models', () async {
        mockAdapter.enqueue(MockResponse(
          body: {
            'models': [
              {
                'name': 'models/gemini-1.5-pro',
                'displayName': 'Gemini 1.5 Pro',
                'inputTokenLimit': 1000000,
              },
              {
                'name': 'models/gemini-1.5-flash',
                'displayName': 'Gemini 1.5 Flash',
                'inputTokenLimit': 1000000,
              },
              {
                'name': 'models/text-bison-001',
                'displayName': 'Text Bison',
              },
            ],
          },
        ));

        final models = await adapter.fetchModels();

        // Only gemini models returned.
        final ids = models.map((m) => m.id).toList();
        expect(ids, contains('gemini-1.5-pro'));
        expect(ids, contains('gemini-1.5-flash'));
        expect(ids, isNot(contains('text-bison-001')));

        // Prefix stripped.
        final pro = models.firstWhere((m) => m.id == 'gemini-1.5-pro');
        expect(pro.displayName, 'Gemini 1.5 Pro');
        expect(pro.contextWindow, 1000000);
        expect(pro.capabilities.supportsImageInput, isTrue);
        expect(pro.capabilities.supportsAudioInput, isTrue);
      });
    });
  });
}
