import 'package:ai_core/ai_client.dart';
import 'package:ai_core/ai_provider_registry.dart';
import 'package:ai_core/conversation_manager.dart';
import 'package:ai_core/core/ai_provider_adapter.dart';
import 'package:ai_core/models/ai_content.dart';
import 'package:ai_core/models/ai_embedding.dart';
import 'package:ai_core/models/ai_message.dart';
import 'package:ai_core/models/ai_model.dart';
import 'package:ai_core/models/ai_provider_config.dart';
import 'package:ai_core/models/ai_request.dart';
import 'package:ai_core/models/ai_response.dart';
import 'package:ai_core/models/ai_stream_chunk.dart';
import 'package:ai_core/models/ai_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MockAdapter mockAdapter;
  late AIClient client;

  setUp(() {
    mockAdapter = _MockAdapter();
    final registry = AIProviderRegistry();
    registry.register(mockAdapter);
    registry.setDefault('mock');
    client = AIClient(registry: registry);
  });

  group('ConversationManager', () {
    test('basic single-turn conversation', () async {
      mockAdapter.enqueue(_resp('Hello! How can I help?'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
      );

      final response = await conversation.send('Hi');
      expect(response.text, 'Hello! How can I help?');
      expect(conversation.messageCount, 2); // user + assistant
    });

    test('multi-turn conversation maintains history', () async {
      mockAdapter.enqueue(_resp('Hello!'));
      mockAdapter.enqueue(_resp('You said "Hi" and then "How are you?"'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
      );

      await conversation.send('Hi');
      final response = await conversation.send('How are you?');

      expect(response.text, 'You said "Hi" and then "How are you?"');
      expect(conversation.messageCount, 4); // user+assistant+user+assistant

      // Verify the second request included all history
      final lastRequest = mockAdapter.capturedRequests.last;
      expect(lastRequest.messages.length, 3); // user + assistant + user
    });

    test('system prompt is included', () async {
      mockAdapter.enqueue(_resp('I am helpful.'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
        systemPrompt: 'You are a helpful assistant.',
      );

      await conversation.send('Who are you?');

      final request = mockAdapter.capturedRequests.first;
      expect(request.messages.first.role, AIRole.system);
      expect(conversation.messageCount, 3); // system + user + assistant
    });

    test('clear removes all messages', () async {
      mockAdapter.enqueue(_resp('Hello!'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
        systemPrompt: 'System prompt',
      );

      await conversation.send('Hi');
      expect(conversation.messageCount, 3);

      conversation.clear();
      expect(conversation.messageCount, 0);
    });

    test('reset restores system prompt', () async {
      mockAdapter.enqueue(_resp('Hello!'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
        systemPrompt: 'Original prompt',
      );

      await conversation.send('Hi');
      expect(conversation.messageCount, 3);

      conversation.reset(systemPrompt: 'New prompt');
      expect(conversation.messageCount, 1);
      expect(conversation.messages.first.role, AIRole.system);
    });

    test('regenerate removes last assistant and re-generates', () async {
      mockAdapter.enqueue(_resp('First answer'));
      mockAdapter.enqueue(_resp('Second answer'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
      );

      await conversation.send('Question?');
      final data = conversation.messages.last.content.first.data as TextContent;
      expect(data.text, 'First answer');

      final response = await conversation.regenerate();
      expect(response.text, 'Second answer');
      expect(conversation.messageCount, 2); // user + new assistant
    });

    test('addMessage injects context without generating', () {
      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
      );

      conversation.addMessage(AIMessage.user('prior context'));
      conversation.addMessage(AIMessage.assistant('noted'));

      expect(conversation.messageCount, 2);
    });

    test('addMessages injects multiple messages', () {
      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
      );

      conversation.addMessages([
        AIMessage.user('hello'),
        AIMessage.assistant('hi'),
        AIMessage.user('bye'),
      ]);

      expect(conversation.messageCount, 3);
    });

    test('messages list is unmodifiable', () {
      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
      );

      expect(
        () => conversation.messages.add(AIMessage.user('hack')),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('tool calling loop: single round', () async {
      // First response: model calls a tool
      mockAdapter.enqueue(
        _toolCallResp([
          AIToolCall(
            id: 'call_1',
            functionName: 'get_weather',
            arguments: '{"city": "London"}',
          ),
        ]),
      );
      // Second response: model gives text after seeing tool result
      mockAdapter.enqueue(_resp('The weather in London is sunny.'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
        tools: [
          AITool(
            function: AIFunctionDefinition(
              name: 'get_weather',
              description: 'Get weather',
              parameters: const {},
            ),
          ),
        ],
        toolExecutor: (toolCall) async {
          if (toolCall.functionName == 'get_weather') {
            return '{"weather": "sunny", "temp": 22}';
          }
          return 'unknown tool';
        },
      );

      final response = await conversation.send('What is the weather?');
      expect(response.text, 'The weather in London is sunny.');

      // History: user + assistant(toolCalls) + tool(result) + assistant(text)
      expect(conversation.messageCount, 4);
      expect(conversation.messages[1].toolCalls, isNotNull);
      expect(conversation.messages[2].role, AIRole.tool);
    });

    test('tool calling loop: multiple rounds', () async {
      // Round 1: model calls tool A
      mockAdapter.enqueue(
        _toolCallResp([
          AIToolCall(
            id: 'call_1',
            functionName: 'search',
            arguments: '{"q": "Dart"}',
          ),
        ]),
      );
      // Round 2: model calls tool B
      mockAdapter.enqueue(
        _toolCallResp([
          AIToolCall(
            id: 'call_2',
            functionName: 'summarize',
            arguments: '{"text": "Dart is a language"}',
          ),
        ]),
      );
      // Round 3: final text response
      mockAdapter.enqueue(_resp('Dart is a great language.'));

      var toolCallCount = 0;
      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
        tools: [
          AITool(
            function: AIFunctionDefinition(
              name: 'search',
              description: 'Search',
              parameters: const {},
            ),
          ),
          AITool(
            function: AIFunctionDefinition(
              name: 'summarize',
              description: 'Summarize',
              parameters: const {},
            ),
          ),
        ],
        toolExecutor: (toolCall) async {
          toolCallCount++;
          return 'result $toolCallCount';
        },
      );

      final response = await conversation.send('Tell me about Dart');
      expect(response.text, 'Dart is a great language.');
      expect(toolCallCount, 2);
    });

    test('maxToolRounds prevents infinite loop', () async {
      // Model always responds with tool calls — should be capped
      for (var i = 0; i < 3; i++) {
        mockAdapter.enqueue(
          _toolCallResp([
            AIToolCall(id: 'call_$i', functionName: 'noop', arguments: '{}'),
          ]),
        );
      }
      // After max rounds, the last forced call (without tools) returns text
      mockAdapter.enqueue(_resp('Forced stop after max rounds'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
        maxToolRounds: 3,
        tools: [
          AITool(
            function: AIFunctionDefinition(
              name: 'noop',
              description: 'No-op',
              parameters: const {},
            ),
          ),
        ],
        toolExecutor: (toolCall) async => 'ok',
      );

      final response = await conversation.send('Loop me');
      expect(response.text, 'Forced stop after max rounds');
    });

    test(
      'tool calls without executor adds to history without looping',
      () async {
        mockAdapter.enqueue(
          _toolCallResp([
            AIToolCall(
              id: 'call_1',
              functionName: 'get_weather',
              arguments: '{}',
            ),
          ]),
        );

        final conversation = ConversationManager(
          client: client,
          model: 'test-model',
          tools: [
            AITool(
              function: AIFunctionDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: const {},
              ),
            ),
          ],
          // No toolExecutor
        );

        final response = await conversation.send('Weather?');
        expect(response.hasToolCalls, true);
        // Should have user + assistant(toolCalls) — no loop
        expect(conversation.messageCount, 2);
      },
    );

    test('temperature and maxTokens are passed through', () async {
      mockAdapter.enqueue(_resp('ok'));

      final conversation = ConversationManager(
        client: client,
        model: 'test-model',
        temperature: 0.5,
        maxTokens: 200,
      );

      await conversation.send('test');

      final request = mockAdapter.capturedRequests.first;
      expect(request.temperature, 0.5);
      expect(request.maxTokens, 200);
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────────

AIResponse _resp(String text) {
  return AIResponse(text: text, model: 'test-model', raw: const {});
}

AIResponse _toolCallResp(List<AIToolCall> toolCalls) {
  return AIResponse(
    text: '',
    model: 'test-model',
    finishReason: 'tool_calls',
    toolCalls: toolCalls,
    raw: const {},
  );
}

/// A minimal mock adapter that returns queued responses.
class _MockAdapter implements AIProviderAdapter {
  final List<AIResponse> _responses = [];
  final List<AIRequest> capturedRequests = [];

  void enqueue(AIResponse response) => _responses.add(response);

  @override
  AIProviderConfig get config => const AIProviderConfig(
    id: 'mock',
    providerType: AIProviderType.openAI,
    apiKey: 'mock-key',
  );

  @override
  String get providerId => 'mock';

  @override
  Future<AIResponse> generate(AIRequest request) async {
    capturedRequests.add(request);
    if (_responses.isEmpty) {
      throw StateError('No mock responses queued');
    }
    return _responses.removeAt(0);
  }

  @override
  Stream<AIStreamChunk> stream(AIRequest request) {
    throw UnimplementedError('Streaming not used in these tests');
  }

  @override
  Future<List<AIModel>> fetchModels() async => [];

  @override
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
