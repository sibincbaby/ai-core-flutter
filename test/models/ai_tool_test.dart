import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AITool', () {
    test('function factory creates a tool with correct fields', () {
      final tool = AITool.function(
        name: 'get_weather',
        description: 'Get current weather',
        parameters: {
          'type': 'object',
          'properties': {
            'location': {'type': 'string', 'description': 'City name'},
          },
          'required': ['location'],
        },
      );

      expect(tool.type, 'function');
      expect(tool.function.name, 'get_weather');
      expect(tool.function.description, 'Get current weather');
      expect(tool.function.parameters['type'], 'object');
    });

    test('AIFunctionDefinition supports strict mode', () {
      const def = AIFunctionDefinition(
        name: 'calc',
        description: 'Calculate',
        parameters: {'type': 'object'},
        strict: true,
      );

      expect(def.strict, isTrue);
    });
  });

  group('AIToolCall', () {
    test('fields are correctly stored', () {
      const call = AIToolCall(
        id: 'call_123',
        functionName: 'get_weather',
        arguments: '{"location":"London"}',
      );

      expect(call.id, 'call_123');
      expect(call.type, 'function');
      expect(call.functionName, 'get_weather');
      expect(call.arguments, '{"location":"London"}');
    });
  });

  group('AIToolChoice', () {
    test('auto choice', () {
      expect(AIToolChoice.auto.value, 'auto');
    });

    test('none choice', () {
      expect(AIToolChoice.none.value, 'none');
    });

    test('required choice', () {
      expect(AIToolChoice.required.value, 'required');
    });

    test('function choice creates specific function spec', () {
      final choice = AIToolChoice.function('get_weather');
      final value = choice.value as Map<String, dynamic>;
      expect(value['type'], 'function');
      expect(
        (value['function'] as Map<String, dynamic>)['name'],
        'get_weather',
      );
    });
  });

  group('AIMessage tool support', () {
    test('toolCalls factory creates assistant message with tool calls', () {
      final msg = AIMessage.toolCalls([
        const AIToolCall(
          id: 'call_1',
          functionName: 'get_weather',
          arguments: '{"city":"Paris"}',
        ),
      ]);

      expect(msg.role, AIRole.assistant);
      expect(msg.toolCalls, isNotNull);
      expect(msg.toolCalls!.length, 1);
      expect(msg.toolCalls!.first.functionName, 'get_weather');
      expect(msg.content, isEmpty);
    });

    test('toolCalls factory with text content', () {
      final msg = AIMessage.toolCalls([
        const AIToolCall(
          id: 'call_1',
          functionName: 'search',
          arguments: '{"q":"test"}',
        ),
      ], text: 'Let me search for that.');

      expect(msg.role, AIRole.assistant);
      expect(msg.toolCalls!.length, 1);
      expect(msg.content.length, 1);
      expect(msg.content.first.data, isA<TextContent>());
    });

    test('toolResult factory creates tool response message', () {
      final msg = AIMessage.toolResult(
        toolCallId: 'call_1',
        result: '{"temp": 22}',
      );

      expect(msg.role, AIRole.tool);
      expect(msg.toolCallId, 'call_1');
      expect(msg.content.length, 1);
      expect((msg.content.first.data as TextContent).text, '{"temp": 22}');
    });
  });

  group('AIRequest tool support', () {
    test('tools and toolChoice are included in request', () {
      final tool = AITool.function(
        name: 'get_weather',
        description: 'Get weather',
        parameters: {'type': 'object'},
      );

      final request = AIRequest(
        messages: [AIMessage.user('What is the weather?')],
        model: 'gpt-4o',
        tools: [tool],
        toolChoice: AIToolChoice.auto,
      );

      expect(request.tools, isNotNull);
      expect(request.tools!.length, 1);
      expect(request.toolChoice, isNotNull);
    });

    test('copyWith preserves tools', () {
      final tool = AITool.function(
        name: 'search',
        description: 'Search',
        parameters: {'type': 'object'},
      );

      final request = AIRequest(
        messages: [AIMessage.user('Search')],
        model: 'gpt-4o',
        tools: [tool],
        toolChoice: AIToolChoice.required,
      );

      final copy = request.copyWith(model: 'gpt-4o-mini');

      expect(copy.model, 'gpt-4o-mini');
      expect(copy.tools, isNotNull);
      expect(copy.tools!.length, 1);
      expect(copy.toolChoice!.value, 'required');
    });
  });

  group('AIResponse tool support', () {
    test('hasToolCalls returns true when tool calls present', () {
      const response = AIResponse(
        text: '',
        finishReason: 'tool_calls',
        toolCalls: [
          AIToolCall(
            id: 'call_1',
            functionName: 'get_weather',
            arguments: '{"city":"NYC"}',
          ),
        ],
        raw: {},
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.length, 1);
    });

    test('hasToolCalls returns false when no tool calls', () {
      const response = AIResponse(text: 'Hello', finishReason: 'stop', raw: {});

      expect(response.hasToolCalls, isFalse);
      expect(response.toolCalls, isEmpty);
    });
  });

  group('AIStreamChunk tool support', () {
    test('tool call deltas are stored', () {
      const chunk = AIStreamChunk(
        textDelta: '',
        toolCallDeltas: [
          AIToolCallDelta(
            index: 0,
            id: 'call_1',
            functionName: 'get_weather',
            argumentsDelta: '{"ci',
          ),
        ],
      );

      expect(chunk.toolCallDeltas, isNotNull);
      expect(chunk.toolCallDeltas!.length, 1);
      expect(chunk.toolCallDeltas!.first.functionName, 'get_weather');
    });
  });

  group('CapabilityValidator tool support', () {
    const validator = CapabilityValidator();

    final toolCapableModel = AIModel(
      id: 'gpt-4o',
      providerId: 'test',
      displayName: 'GPT-4o',
      capabilities: const AIModelCapabilities(supportsToolCalling: true),
    );

    final noToolModel = AIModel(
      id: 'basic',
      providerId: 'test',
      displayName: 'Basic',
      capabilities: const AIModelCapabilities(supportsToolCalling: false),
    );

    test('request with tools passes for tool-capable model', () {
      final request = AIRequest(
        messages: [AIMessage.user('Weather?')],
        model: 'gpt-4o',
        tools: [
          AITool.function(
            name: 'get_weather',
            description: 'Get weather',
            parameters: {'type': 'object'},
          ),
        ],
      );

      expect(
        () => validator.validate(request, toolCapableModel),
        returnsNormally,
      );
    });

    test('request with tools fails for non-tool model', () {
      final request = AIRequest(
        messages: [AIMessage.user('Weather?')],
        model: 'basic',
        tools: [
          AITool.function(
            name: 'get_weather',
            description: 'Get weather',
            parameters: {'type': 'object'},
          ),
        ],
      );

      expect(
        () => validator.validate(request, noToolModel),
        throwsA(isA<AIUnsupportedInputException>()),
      );
    });

    test('request without tools passes for non-tool model', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'basic',
      );

      expect(() => validator.validate(request, noToolModel), returnsNormally);
    });
  });
}
