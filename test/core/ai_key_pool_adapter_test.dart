import 'package:ai_core/ai_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_dio_adapter.dart';

/// Standard successful chat completion response body.
Map<String, dynamic> _chatResponse({
  String model = 'gpt-4o',
  String content = 'Hello!',
  int promptTokens = 10,
  int completionTokens = 5,
}) => {
  'id': 'chatcmpl-test',
  'object': 'chat.completion',
  'model': model,
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': 'stop',
    },
  ],
  'usage': {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': promptTokens + completionTokens,
  },
};

void main() {
  group('Key pool integration with OpenAIAdapter', () {
    late Dio dio;
    late MockDioAdapter mockDio;
    late AIKeyPool pool;
    late OpenAIAdapter adapter;

    setUp(() {
      dio = Dio();
      mockDio = MockDioAdapter();
      dio.httpClientAdapter = mockDio;

      pool = AIKeyPool(
        entries: [
          const AIKeyEntry('sk-free-key', label: 'free'),
          const AIKeyEntry('sk-premium-key', label: 'premium'),
        ],
        defaultLabel: 'free',
      );

      adapter = OpenAIAdapter(
        config: AIProviderConfig(
          id: 'test-openai',
          providerType: AIProviderType.openAI,
          apiKey: 'sk-fallback', // base key when no pool
          keyPool: pool,
        ),
        dio: dio,
      );
    });

    tearDown(() => adapter.dispose());

    test('uses default key when no keyTag specified', () async {
      mockDio.enqueue(MockResponse(body: _chatResponse()));

      await adapter.generate(
        AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
      );

      final captured = mockDio.capturedRequests.last;
      expect(captured.headers['Authorization'], 'Bearer sk-free-key');
    });

    test('uses specified keyTag', () async {
      mockDio.enqueue(MockResponse(body: _chatResponse()));

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Hi')],
          model: 'gpt-4o',
          keyTag: 'premium',
        ),
      );

      final captured = mockDio.capturedRequests.last;
      expect(captured.headers['Authorization'], 'Bearer sk-premium-key');
    });

    test('falls back to default for unknown keyTag', () async {
      mockDio.enqueue(MockResponse(body: _chatResponse()));

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Hi')],
          model: 'gpt-4o',
          keyTag: 'nonexistent',
        ),
      );

      final captured = mockDio.capturedRequests.last;
      expect(captured.headers['Authorization'], 'Bearer sk-free-key');
    });

    test('records usage after generate', () async {
      mockDio.enqueue(
        MockResponse(
          body: _chatResponse(promptTokens: 100, completionTokens: 50),
        ),
      );

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Hi')],
          model: 'gpt-4o',
          keyTag: 'premium',
        ),
      );

      final usage = pool.usageFor('premium')!;
      expect(usage.callCount, 1);
      expect(usage.inputTokens, 100);
      expect(usage.outputTokens, 50);

      // Free key should remain untouched
      expect(pool.usageFor('free')!.callCount, 0);
    });

    test('records usage to default when no keyTag', () async {
      mockDio.enqueue(
        MockResponse(
          body: _chatResponse(promptTokens: 200, completionTokens: 80),
        ),
      );

      await adapter.generate(
        AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
      );

      final usage = pool.usageFor('free')!;
      expect(usage.callCount, 1);
      expect(usage.inputTokens, 200);
      expect(usage.outputTokens, 80);
    });

    test('accumulates usage across multiple calls', () async {
      mockDio.enqueue(
        MockResponse(
          body: _chatResponse(promptTokens: 50, completionTokens: 25),
        ),
      );
      mockDio.enqueue(
        MockResponse(
          body: _chatResponse(promptTokens: 100, completionTokens: 50),
        ),
      );

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Hi')],
          model: 'gpt-4o',
          keyTag: 'free',
        ),
      );
      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Hi again')],
          model: 'gpt-4o',
          keyTag: 'free',
        ),
      );

      final usage = pool.usageFor('free')!;
      expect(usage.callCount, 2);
      expect(usage.inputTokens, 150);
      expect(usage.outputTokens, 75);
    });

    test('resetUsage clears accumulated data', () async {
      mockDio.enqueue(
        MockResponse(
          body: _chatResponse(promptTokens: 100, completionTokens: 50),
        ),
      );

      await adapter.generate(
        AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
      );

      pool.resetUsage();
      expect(pool.usageFor('free')!.callCount, 0);
      expect(pool.usageFor('free')!.totalTokens, 0);
    });
  });

  group('Key pool integration without pool configured', () {
    late Dio dio;
    late MockDioAdapter mockDio;
    late OpenAIAdapter adapter;

    setUp(() {
      dio = Dio();
      mockDio = MockDioAdapter();
      dio.httpClientAdapter = mockDio;

      adapter = OpenAIAdapter(
        config: const AIProviderConfig(
          id: 'test-openai',
          providerType: AIProviderType.openAI,
          apiKey: 'sk-single',
        ),
        dio: dio,
      );
    });

    tearDown(() => adapter.dispose());

    test('uses base apiKey when no pool configured', () async {
      mockDio.enqueue(MockResponse(body: _chatResponse()));

      await adapter.generate(
        AIRequest(messages: [AIMessage.user('Hi')], model: 'gpt-4o'),
      );

      final captured = mockDio.capturedRequests.last;
      // Should use the standard Authorization header set by Dio base options
      expect(captured.headers['Authorization'], 'Bearer sk-single');
    });

    test('keyTag is ignored when no pool configured', () async {
      mockDio.enqueue(MockResponse(body: _chatResponse()));

      await adapter.generate(
        AIRequest(
          messages: [AIMessage.user('Hi')],
          model: 'gpt-4o',
          keyTag: 'premium',
        ),
      );

      // Should still work fine, using base key
      final captured = mockDio.capturedRequests.last;
      expect(captured.headers['Authorization'], 'Bearer sk-single');
    });
  });
}
