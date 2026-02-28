import 'dart:convert';

import 'package:ai_core/ai_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_dio_adapter.dart';

void main() {
  group('OpenAI tool calling', () {
    late Dio dio;
    late MockDioAdapter mockAdapter;
    late OpenAIAdapter adapter;

    setUp(() {
      dio = Dio();
      mockAdapter = MockDioAdapter();
      dio.httpClientAdapter = mockAdapter;
      adapter = OpenAIAdapter(
        config: const AIProviderConfig(
          id: 'openai',
          providerType: AIProviderType.openAI,
          apiKey: 'test-key',
          isDefault: true,
        ),
        dio: dio,
      );
    });

    tearDown(() {
      adapter.dispose();
    });

    test('request body includes tools and tool_choice', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'choices': [
              {
                'message': {'content': 'Hello', 'role': 'assistant'},
                'finish_reason': 'stop',
              },
            ],
          },
        ),
      );

      final tool = AITool.function(
        name: 'get_weather',
        description: 'Get weather for a city',
        parameters: {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city'],
        },
      );

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('What is the weather in London?')],
          model: 'gpt-4o',
          tools: [tool],
          toolChoice: AIToolChoice.auto,
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;

      expect(body['tools'], isNotNull);
      expect(body['tools'], isList);
      final tools = body['tools'] as List<dynamic>;
      expect(tools.length, 1);
      final toolMap = tools[0] as Map<String, dynamic>;
      expect(toolMap['type'], 'function');
      expect(
        (toolMap['function'] as Map<String, dynamic>)['name'],
        'get_weather',
      );
      expect(body['tool_choice'], 'auto');
    });

    test('response parses tool calls', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'choices': [
              {
                'message': {
                  'content': null,
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'id': 'call_abc123',
                      'type': 'function',
                      'function': {
                        'name': 'get_weather',
                        'arguments': '{"city":"London"}',
                      },
                    },
                  ],
                },
                'finish_reason': 'tool_calls',
              },
            ],
            'model': 'gpt-4o',
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
          messages: [AIMessage.user('Weather in London?')],
          model: 'gpt-4o',
          tools: [
            AITool.function(
              name: 'get_weather',
              description: 'Get weather',
              parameters: {'type': 'object'},
            ),
          ],
        ),
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.length, 1);
      expect(response.toolCalls.first.id, 'call_abc123');
      expect(response.toolCalls.first.functionName, 'get_weather');
      expect(response.toolCalls.first.arguments, '{"city":"London"}');
      expect(response.finishReason, 'tool_calls');
    });

    test('tool result message is serialized correctly', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'choices': [
              {
                'message': {'content': 'It is sunny', 'role': 'assistant'},
                'finish_reason': 'stop',
              },
            ],
          },
        ),
      );

      await adapter.generate(
        AIRequest(
          messages: [
            AIMessage.user('Weather in London?'),
            AIMessage.toolCalls([
              const AIToolCall(
                id: 'call_abc123',
                functionName: 'get_weather',
                arguments: '{"city":"London"}',
              ),
            ]),
            AIMessage.toolResult(
              toolCallId: 'call_abc123',
              result: '{"temp": 22, "condition": "sunny"}',
            ),
          ],
          model: 'gpt-4o',
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;

      // Second message should be assistant with tool_calls.
      final assistantMsg = messages[1] as Map<String, dynamic>;
      expect(assistantMsg['role'], 'assistant');
      expect(assistantMsg['tool_calls'], isNotNull);

      // Third message should be tool result.
      final toolMsg = messages[2] as Map<String, dynamic>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['tool_call_id'], 'call_abc123');
      expect(toolMsg['content'], '{"temp": 22, "condition": "sunny"}');
    });

    test('streaming with tool call deltas', () async {
      final events = [
        jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_abc123',
                    'type': 'function',
                    'function': {'name': 'get_weather', 'arguments': ''},
                  },
                ],
              },
              'finish_reason': null,
            },
          ],
          'model': 'gpt-4o',
        }),
        jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '{"city":'},
                  },
                ],
              },
              'finish_reason': null,
            },
          ],
          'model': 'gpt-4o',
        }),
        jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '"London"}'},
                  },
                ],
              },
              'finish_reason': null,
            },
          ],
          'model': 'gpt-4o',
        }),
        jsonEncode({
          'choices': [
            {'delta': {}, 'finish_reason': 'tool_calls'},
          ],
          'model': 'gpt-4o',
        }),
        '[DONE]',
      ];

      mockAdapter.enqueue(MockResponse.sse(events));

      final chunks = await adapter
          .stream(
            AIRequest(
              messages: [AIMessage.user('Weather?')],
              model: 'gpt-4o',
              tools: [
                AITool.function(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: {'type': 'object'},
                ),
              ],
            ),
          )
          .toList();

      // First chunk should have tool call delta with id and name.
      final firstToolChunk = chunks
          .where((c) => c.toolCallDeltas != null)
          .first;
      expect(firstToolChunk.toolCallDeltas!.first.id, 'call_abc123');
      expect(firstToolChunk.toolCallDeltas!.first.functionName, 'get_weather');

      // Should have a done chunk.
      final doneChunks = chunks.where((c) => c.isDone);
      expect(doneChunks, isNotEmpty);
    });
  });

  group('Gemini tool calling', () {
    late Dio dio;
    late MockDioAdapter mockAdapter;
    late GeminiAdapter adapter;

    setUp(() {
      dio = Dio();
      mockAdapter = MockDioAdapter();
      dio.httpClientAdapter = mockAdapter;
      adapter = GeminiAdapter(
        config: const AIProviderConfig(
          id: 'gemini',
          providerType: AIProviderType.gemini,
          apiKey: 'test-key',
          isDefault: true,
        ),
        dio: dio,
      );
    });

    tearDown(() {
      adapter.dispose();
    });

    test('request body includes Gemini tool declarations', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'OK'},
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          },
        ),
      );

      final tool = AITool.function(
        name: 'get_weather',
        description: 'Get weather',
        parameters: {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
        },
      );

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Weather in London?')],
          model: 'gemini-2.0-flash',
          tools: [tool],
          toolChoice: AIToolChoice.auto,
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;

      expect(body['tools'], isNotNull);
      final tools = body['tools'] as List<dynamic>;
      final declarations =
          (tools[0] as Map<String, dynamic>)['functionDeclarations']
              as List<dynamic>;
      expect(declarations.length, 1);
      expect((declarations[0] as Map<String, dynamic>)['name'], 'get_weather');

      // Tool config for auto mode.
      final toolConfig = body['toolConfig'] as Map<String, dynamic>;
      final funcConfig =
          toolConfig['functionCallingConfig'] as Map<String, dynamic>;
      expect(funcConfig['mode'], 'AUTO');
    });

    test('response parses Gemini function calls', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'functionCall': {
                        'name': 'get_weather',
                        'args': {'city': 'London'},
                      },
                    },
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          },
        ),
      );

      final response = await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Weather?')],
          model: 'gemini-2.0-flash',
          tools: [
            AITool.function(
              name: 'get_weather',
              description: 'Get weather',
              parameters: {'type': 'object'},
            ),
          ],
        ),
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.length, 1);
      expect(response.toolCalls.first.functionName, 'get_weather');

      final args =
          jsonDecode(response.toolCalls.first.arguments)
              as Map<String, dynamic>;
      expect(args['city'], 'London');
    });

    test('tool result message uses Gemini functionResponse format', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'London is sunny at 22°C.'},
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          },
        ),
      );

      await adapter.generate(
        AIRequest(
          messages: [
            AIMessage.user('Weather in London?'),
            AIMessage.toolCalls([
              const AIToolCall(
                id: 'get_weather',
                functionName: 'get_weather',
                arguments: '{"city":"London"}',
              ),
            ]),
            AIMessage.toolResult(
              toolCallId: 'get_weather',
              result: '{"temp": 22}',
            ),
          ],
          model: 'gemini-2.0-flash',
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;
      final contents = body['contents'] as List<dynamic>;

      // Third message should be function response.
      final toolResponse = contents[2] as Map<String, dynamic>;
      expect(toolResponse['role'], 'function');
      final parts = toolResponse['parts'] as List<dynamic>;
      final funcResponse =
          (parts[0] as Map<String, dynamic>)['functionResponse']
              as Map<String, dynamic>;
      expect(funcResponse['name'], 'get_weather');
      expect(funcResponse['response'], isA<Map<String, dynamic>>());
    });
  });

  group('OpenRouter tool calling', () {
    late Dio dio;
    late MockDioAdapter mockAdapter;
    late OpenRouterAdapter adapter;

    setUp(() {
      dio = Dio();
      mockAdapter = MockDioAdapter();
      dio.httpClientAdapter = mockAdapter;
      adapter = OpenRouterAdapter(
        config: const AIProviderConfig(
          id: 'openrouter',
          providerType: AIProviderType.openRouter,
          apiKey: 'test-key',
          isDefault: true,
        ),
        dio: dio,
      );
    });

    tearDown(() {
      adapter.dispose();
    });

    test('tool calls work via OpenAI-compatible format', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'choices': [
              {
                'message': {
                  'content': null,
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'id': 'call_xyz',
                      'type': 'function',
                      'function': {
                        'name': 'search',
                        'arguments': '{"query":"test"}',
                      },
                    },
                  ],
                },
                'finish_reason': 'tool_calls',
              },
            ],
          },
        ),
      );

      final response = await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Search for test')],
          model: 'openai/gpt-4o',
          tools: [
            AITool.function(
              name: 'search',
              description: 'Search',
              parameters: {'type': 'object'},
            ),
          ],
        ),
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.first.functionName, 'search');
    });
  });
}
