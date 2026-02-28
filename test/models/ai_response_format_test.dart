import 'package:ai_core/ai_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_dio_adapter.dart';

void main() {
  group('AIResponseFormat', () {
    test('text format', () {
      expect(AIResponseFormat.text.type, 'text');
      expect(AIResponseFormat.text.jsonSchema, isNull);
    });

    test('json format', () {
      expect(AIResponseFormat.json.type, 'json_object');
      expect(AIResponseFormat.json.jsonSchema, isNull);
    });

    test('jsonSchema format', () {
      final format = AIResponseFormat.jsonSchema(
        name: 'weather',
        schema: {
          'type': 'object',
          'properties': {
            'temp': {'type': 'number'},
          },
          'required': ['temp'],
        },
        description: 'Weather response',
      );

      expect(format.type, 'json_schema');
      expect(format.jsonSchema, isNotNull);
      expect(format.jsonSchema!.name, 'weather');
      expect(format.jsonSchema!.strict, isTrue);
      expect(format.jsonSchema!.description, 'Weather response');
    });
  });

  group('AIRequest responseFormat', () {
    test('stores responseFormat', () {
      final request = AIRequest(
        messages: [AIMessage.user('Give me JSON')],
        model: 'gpt-4o',
        responseFormat: AIResponseFormat.json,
      );

      expect(request.responseFormat, isNotNull);
      expect(request.responseFormat!.type, 'json_object');
    });

    test('copyWith preserves responseFormat', () {
      final request = AIRequest(
        messages: [AIMessage.user('test')],
        model: 'gpt-4o',
        responseFormat: AIResponseFormat.json,
      );

      final copy = request.copyWith(model: 'gpt-4o-mini');
      expect(copy.responseFormat!.type, 'json_object');
    });
  });

  group('OpenAI structured output serialization', () {
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

    tearDown(() => adapter.dispose());

    test('json_object format is serialized correctly', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'choices': [
              {
                'message': {'content': '{"result": 42}', 'role': 'assistant'},
                'finish_reason': 'stop',
              },
            ],
          },
        ),
      );

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Give me a number as JSON')],
          model: 'gpt-4o',
          responseFormat: AIResponseFormat.json,
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;
      final responseFormat = body['response_format'] as Map<String, dynamic>;
      expect(responseFormat['type'], 'json_object');
    });

    test('json_schema format is serialized with schema', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'choices': [
              {
                'message': {
                  'content': '{"temperature": 22}',
                  'role': 'assistant',
                },
                'finish_reason': 'stop',
              },
            ],
          },
        ),
      );

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Weather?')],
          model: 'gpt-4o',
          responseFormat: AIResponseFormat.jsonSchema(
            name: 'weather',
            schema: {
              'type': 'object',
              'properties': {
                'temperature': {'type': 'number'},
              },
              'required': ['temperature'],
            },
            description: 'Weather data',
          ),
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;
      final rf = body['response_format'] as Map<String, dynamic>;
      expect(rf['type'], 'json_schema');
      final schema = rf['json_schema'] as Map<String, dynamic>;
      expect(schema['name'], 'weather');
      expect(schema['strict'], isTrue);
      expect(schema['description'], 'Weather data');
      expect(schema['schema'], isA<Map<String, dynamic>>());
    });

    test('no response_format when not set', () async {
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

      await adapter.generate(
        AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;
      expect(body.containsKey('response_format'), isFalse);
    });
  });

  group('Gemini structured output serialization', () {
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

    tearDown(() => adapter.dispose());

    test('json_object sets responseMimeType', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"result": 42}'},
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
          messages: [AIMessage.user('Give JSON')],
          model: 'gemini-2.0-flash',
          responseFormat: AIResponseFormat.json,
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;
      final genConfig = body['generationConfig'] as Map<String, dynamic>;
      expect(genConfig['responseMimeType'], 'application/json');
      expect(genConfig.containsKey('responseSchema'), isFalse);
    });

    test('json_schema sets responseMimeType and responseSchema', () async {
      mockAdapter.enqueue(
        MockResponse(
          body: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"temperature": 22}'},
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          },
        ),
      );

      final schema = {
        'type': 'object',
        'properties': {
          'temperature': {'type': 'number'},
        },
        'required': ['temperature'],
      };

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Weather?')],
          model: 'gemini-2.0-flash',
          responseFormat: AIResponseFormat.jsonSchema(
            name: 'weather',
            schema: schema,
          ),
        ),
      );

      final captured = mockAdapter.capturedRequests.last;
      final body = captured.data as Map<String, dynamic>;
      final genConfig = body['generationConfig'] as Map<String, dynamic>;
      expect(genConfig['responseMimeType'], 'application/json');
      expect(genConfig['responseSchema'], schema);
    });
  });

  group('CapabilityValidator json_mode', () {
    const validator = CapabilityValidator();

    final jsonCapableModel = AIModel(
      id: 'gpt-4o',
      providerId: 'test',
      displayName: 'GPT-4o',
      capabilities: const AIModelCapabilities(supportsJsonMode: true),
    );

    final noJsonModel = AIModel(
      id: 'basic',
      providerId: 'test',
      displayName: 'Basic',
      capabilities: const AIModelCapabilities(supportsJsonMode: false),
    );

    test('json format passes for json-capable model', () {
      final request = AIRequest(
        messages: [AIMessage.user('JSON please')],
        model: 'gpt-4o',
        responseFormat: AIResponseFormat.json,
      );

      expect(
        () => validator.validate(request, jsonCapableModel),
        returnsNormally,
      );
    });

    test('json format fails for non-json model', () {
      final request = AIRequest(
        messages: [AIMessage.user('JSON please')],
        model: 'basic',
        responseFormat: AIResponseFormat.json,
      );

      expect(
        () => validator.validate(request, noJsonModel),
        throwsA(isA<AIUnsupportedInputException>()),
      );
    });

    test('text format passes for non-json model', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'basic',
        responseFormat: AIResponseFormat.text,
      );

      expect(() => validator.validate(request, noJsonModel), returnsNormally);
    });

    test('no responseFormat passes for non-json model', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'basic',
      );

      expect(() => validator.validate(request, noJsonModel), returnsNormally);
    });
  });
}
