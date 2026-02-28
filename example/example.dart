/// AI Core SDK — Complete usage example.
///
/// This example demonstrates the major features of the SDK.
/// Replace the API keys with your own before running.
// ignore_for_file: avoid_print
library;

import 'package:ai_core/ai_core.dart';

Future<void> main() async {
  // ──────────────────────────────────────────────────────────
  // 1. Setup: Register providers
  // ──────────────────────────────────────────────────────────

  final registry = AIProviderRegistry();

  registry.register(
    OpenAIAdapter(
      config: const AIProviderConfig(
        id: 'openai',
        providerType: AIProviderType.openAI,
        apiKey: 'sk-YOUR-KEY',
        isDefault: true,
      ),
      retryConfig: RetryConfig.conservative,
    ),
  );

  registry.register(
    GeminiAdapter(
      config: const AIProviderConfig(
        id: 'gemini',
        providerType: AIProviderType.gemini,
        apiKey: 'AIza-YOUR-KEY',
      ),
    ),
  );

  final client = AIClient(registry: registry);

  // ──────────────────────────────────────────────────────────
  // 2. Simple generation
  // ──────────────────────────────────────────────────────────

  print('=== Simple Generation ===');
  final response = await client.generate(
    AIRequest(
      model: 'gpt-4.1-nano',
      messages: [AIMessage.user('What is Dart in one sentence?')],
      maxTokens: 100,
    ),
  );
  print('Response: ${response.text}');
  print('Tokens: ${response.usage?.totalTokens}');

  // ──────────────────────────────────────────────────────────
  // 3. Streaming
  // ──────────────────────────────────────────────────────────

  print('\n=== Streaming ===');
  final stream = client.stream(
    AIRequest(
      model: 'gpt-4.1-nano',
      messages: [AIMessage.user('Count from 1 to 5')],
      maxTokens: 50,
    ),
  );

  await for (final chunk in stream) {
    if (!chunk.isDone) {
      // Print each token as it arrives
      // In a real app, you'd update a UI widget here.
      print(chunk.textDelta);
    }
  }
  print(''); // newline after stream

  // ──────────────────────────────────────────────────────────
  // 4. Tool / Function Calling
  // ──────────────────────────────────────────────────────────

  print('\n=== Tool Calling ===');
  final tools = [
    AITool.function(
      name: 'get_weather',
      description: 'Get the current weather for a city',
      parameters: {
        'type': 'object',
        'properties': {
          'city': {'type': 'string', 'description': 'The city name'},
        },
        'required': ['city'],
      },
    ),
  ];

  final toolResponse = await client.generate(
    AIRequest(
      model: 'gpt-4.1-nano',
      messages: [AIMessage.user('What is the weather in London?')],
      tools: tools,
      toolChoice: AIToolChoice.auto,
    ),
  );

  if (toolResponse.hasToolCalls) {
    for (final call in toolResponse.toolCalls) {
      print('Tool call: ${call.functionName}(${call.arguments})');
    }
  } else {
    print('Model responded with text: ${toolResponse.text}');
  }

  // ──────────────────────────────────────────────────────────
  // 5. Conversation Manager with tool loop
  // ──────────────────────────────────────────────────────────

  print('\n=== Conversation Manager ===');
  final manager = ConversationManager(
    client: client,
    model: 'gpt-4.1-nano',
    systemPrompt: 'You are a helpful weather assistant.',
    tools: tools,
    toolExecutor: (toolCall) async {
      // Simulate a weather API response
      return '{"temperature": 18, "condition": "cloudy", "humidity": 72}';
    },
  );

  final chatResponse = await manager.send('How is the weather in Paris?');
  print('Assistant: ${chatResponse.text}');
  print('Messages: ${manager.messages.length}');

  // ──────────────────────────────────────────────────────────
  // 6. Structured Output (JSON mode)
  // ──────────────────────────────────────────────────────────

  print('\n=== JSON Mode ===');
  final jsonResponse = await client.generate(
    AIRequest(
      model: 'gpt-4.1-nano',
      messages: [
        AIMessage.system('Respond only in JSON.'),
        AIMessage.user(
          'List 3 programming languages with their year of creation',
        ),
      ],
      responseFormat: AIResponseFormat.json,
      maxTokens: 200,
    ),
  );
  print('JSON: ${jsonResponse.text}');

  // ──────────────────────────────────────────────────────────
  // 7. Cost Tracking
  // ──────────────────────────────────────────────────────────

  print('\n=== Cost Tracking ===');
  final calculator = AICostCalculator();
  final tracker = AICostTracker();

  // Estimate cost from the first response
  if (response.usage != null) {
    final cost = calculator.estimate(
      model: response.model ?? 'gpt-4.1-nano',
      inputTokens: response.usage!.promptTokens ?? 0,
      outputTokens: response.usage!.completionTokens ?? 0,
    );
    if (cost != null) {
      tracker.record(cost);
      print(cost);
    }
  }

  print('Session total: \$${tracker.totalCost.toStringAsFixed(6)}');
  print('Calls tracked: ${tracker.callCount}');

  // ──────────────────────────────────────────────────────────
  // 8. Switch providers seamlessly
  // ──────────────────────────────────────────────────────────

  print('\n=== Provider Switching ===');
  final geminiResponse = await client.generate(
    AIRequest(
      model: 'gemini-2.5-flash',
      messages: [AIMessage.user('What is Flutter?')],
      maxTokens: 100,
    ),
    providerId: 'gemini', // Override default provider
  );
  print('Gemini says: ${geminiResponse.text}');

  // ──────────────────────────────────────────────────────────
  // 9. Embeddings
  // ──────────────────────────────────────────────────────────

  print('\n=== Embeddings ===');
  final embeddings = await client.embed(
    AIEmbeddingRequest(input: ['Hello world'], model: 'text-embedding-3-small'),
  );
  final vector = embeddings.firstVector;
  print('Embedding dimensions: ${vector.length}');
  print('First 5 values: ${vector.take(5).toList()}');

  print('\nDone!');
}
