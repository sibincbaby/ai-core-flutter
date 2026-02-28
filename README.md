# AI Core SDK

A **provider-agnostic** Flutter/Dart SDK for interacting with multiple LLM providers through a single, unified API. Switch between OpenAI, Google Gemini, and OpenRouter (or add your own) without changing application code.

## Features

- **Multi-provider support** — OpenAI, Google Gemini, OpenRouter out of the box
- **Tool/function calling** — Define tools, receive tool calls, feed results back
- **Structured output** — JSON mode and JSON Schema enforcement
- **Streaming** — Real-time token-by-token responses via `Stream<AIStreamChunk>`
- **Embeddings** — Generate text embeddings (OpenAI & Gemini)
- **Conversation manager** — Multi-turn chat with automatic history & tool-call loops
- **Middleware pipeline** — Intercept, transform, or log every request/response
- **Retry & resilience** — Exponential backoff with jitter, Retry-After support
- **Cost tracking** — Built-in pricing tables for popular models, cumulative tracking
- **Multimodal input** — Text, images (URL/base64), audio, and video content
- **Capability validation** — Automatically validates requests against model capabilities
- **Secure key storage** — API keys stored via `flutter_secure_storage`
- **Pure-Dart core** — All core functionality works without Flutter (`ai_core_base.dart`)

## Getting Started

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  ai_core:
    git:
      url: https://github.com/sibincbaby/ai-core-flutter.git
```

### Quick Start

```dart
import 'package:ai_core/ai_core.dart';

// 1. Register a provider
final registry = AIProviderRegistry();
registry.register(OpenAIAdapter(
  config: AIProviderConfig(
    id: 'openai',
    providerType: AIProviderType.openAI,
    apiKey: 'sk-...',
    isDefault: true,
  ),
));

// 2. Create a client
final client = AIClient(registry: registry);

// 3. Generate a response
final response = await client.generate(AIRequest(
  model: 'gpt-4.1',
  messages: [AIMessage.user('What is Flutter?')],
));

print(response.text);
print(response.usage?.totalTokens);
```

## Usage

### Providers

Register one or more providers. Each adapter normalizes the provider's native API into the unified AI Core interface.

```dart
// OpenAI
registry.register(OpenAIAdapter(
  config: AIProviderConfig(
    id: 'openai',
    providerType: AIProviderType.openAI,
    apiKey: 'sk-...',
    isDefault: true,
  ),
));

// Google Gemini
registry.register(GeminiAdapter(
  config: AIProviderConfig(
    id: 'gemini',
    providerType: AIProviderType.gemini,
    apiKey: 'AIza...',
  ),
));

// OpenRouter (access 200+ models)
registry.register(OpenRouterAdapter(
  config: AIProviderConfig(
    id: 'openrouter',
    providerType: AIProviderType.openRouter,
    apiKey: 'sk-or-...',
  ),
));
```

### Streaming

```dart
final stream = client.stream(AIRequest(
  model: 'gpt-4.1',
  messages: [AIMessage.user('Write a haiku about Dart')],
));

await for (final chunk in stream) {
  stdout.write(chunk.textDelta);
}
```

### Tool / Function Calling

```dart
final tools = [
  AITool.function(
    name: 'get_weather',
    description: 'Get current weather for a location',
    parameters: {
      'type': 'object',
      'properties': {
        'location': {'type': 'string', 'description': 'City name'},
      },
      'required': ['location'],
    },
  ),
];

final response = await client.generate(AIRequest(
  model: 'gpt-4.1',
  messages: [AIMessage.user('What is the weather in Tokyo?')],
  tools: tools,
  toolChoice: AIToolChoice.auto,
));

if (response.hasToolCalls) {
  for (final call in response.toolCalls) {
    print('Tool: ${call.functionName}, Args: ${call.arguments}');
  }
}
```

### Conversation Manager

Handles multi-turn chat with automatic history management and tool-call loops:

```dart
final manager = ConversationManager(
  client: client,
  systemPrompt: 'You are a helpful assistant.',
  tools: tools,
  toolExecutor: (toolCall) async {
    // Execute the tool and return the result as a string
    if (toolCall.functionName == 'get_weather') {
      return '{"temp": 22, "condition": "sunny"}';
    }
    return '{"error": "unknown tool"}';
  },
);

final response = await manager.send('What is the weather in Tokyo?');
print(response.text); // "The weather in Tokyo is 22°C and sunny."
print(manager.history.length); // Full conversation history
```

### Structured Output (JSON Mode)

```dart
final response = await client.generate(AIRequest(
  model: 'gpt-4.1',
  messages: [AIMessage.user('List 3 colors as JSON')],
  responseFormat: AIResponseFormat.json,
));

// With JSON Schema enforcement
final schema = AIResponseFormat.jsonSchema(
  name: 'colors',
  schema: {
    'type': 'object',
    'properties': {
      'colors': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['colors'],
  },
);

final structured = await client.generate(AIRequest(
  model: 'gpt-4.1',
  messages: [AIMessage.user('List 3 colors')],
  responseFormat: schema,
));
```

### Embeddings

```dart
final embeddings = await client.embed(AIEmbeddingRequest(
  input: ['Hello world', 'Goodbye world'],
  model: 'text-embedding-3-small',
));

print(embeddings.firstVector); // [0.012, -0.034, ...]
print(embeddings.totalTokens);
```

### Multimodal Content

```dart
// Image input
final response = await client.generate(AIRequest(
  model: 'gpt-4o',
  messages: [
    AIMessage.user('Describe this image', content: [
      AIContentBlock.text('What do you see?'),
      AIContentBlock.imageUrl('https://example.com/photo.jpg'),
    ]),
  ],
));

// Video input (Gemini)
final videoResponse = await client.generate(AIRequest(
  model: 'gemini-2.5-flash',
  messages: [
    AIMessage.user('Summarize this video', content: [
      AIContentBlock.text('What happens in this video?'),
      AIContentBlock.videoUrl(
        'https://example.com/video.mp4',
        mimeType: 'video/mp4',
      ),
    ]),
  ],
));
```

### Middleware Pipeline

Intercept requests and responses for logging, caching, rate limiting, etc.:

```dart
class LoggingMiddleware extends AIMiddleware {
  @override
  Future<AIResponse> onGenerate(
    AIRequest request,
    GenerateNext next,
  ) async {
    print('→ ${request.model}: ${request.messages.length} messages');
    final response = await next(request);
    print('← ${response.usage?.totalTokens} tokens');
    return response;
  }
}

final client = AIClient(
  registry: registry,
  middleware: MiddlewarePipeline(middlewares: [LoggingMiddleware()]),
);
```

### Retry & Resilience

```dart
// Per-adapter retry configuration
final adapter = OpenAIAdapter(
  config: config,
  retryConfig: RetryConfig(
    maxRetries: 3,
    initialDelay: Duration(seconds: 1),
    backoffMultiplier: 2.0,
    jitter: true,
    retryableStatusCodes: {429, 500, 502, 503},
  ),
);

// Or use presets
final aggressive = OpenAIAdapter(
  config: config,
  retryConfig: RetryConfig.aggressive,
);
```

### Cost Tracking

```dart
final calculator = AICostCalculator();
final tracker = AICostTracker();

final response = await client.generate(request);

if (response.usage != null && response.model != null) {
  final cost = calculator.estimate(
    model: response.model!,
    inputTokens: response.usage!.promptTokens ?? 0,
    outputTokens: response.usage!.completionTokens ?? 0,
  );
  if (cost != null) {
    tracker.record(cost);
    print(cost); // AICostEstimate($0.006 — 1000 in @ $2.0/M, 500 out @ $8.0/M)
  }
}

// Cumulative stats
print('Total cost: \$${tracker.totalCost}');
print('By model: ${tracker.costByModel}');

// Custom pricing
calculator.setPricing('my-fine-tune', AIModelPricing(
  inputPerMillion: 5.0,
  outputPerMillion: 15.0,
));
```

### Secure Key Storage

```dart
// Store keys securely (Flutter only)
final keyManager = SecureKeyManager.secure();
await keyManager.storeKey('openai', 'sk-...');

// Retrieve for provider config
final config = await keyManager.getConfig(
  providerId: 'openai',
  defaultModel: 'gpt-4.1',
);
```

### Pure-Dart Usage

For server-side Dart, CLIs, or non-Flutter projects, import the base library:

```dart
import 'package:ai_core/ai_core_base.dart';

// Everything works the same — just provide your own StorageBackend
// if you need key management.
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│                   AIClient                       │
│  ┌───────────┐  ┌────────────┐  ┌────────────┐  │
│  │ Middleware │→ │ Capability │→ │  Provider   │  │
│  │ Pipeline  │  │ Validator  │  │  Adapter    │  │
│  └───────────┘  └────────────┘  └──────┬─────┘  │
└────────────────────────────────────────┼─────────┘
                                         │
        ┌────────────────────────────────┼────────────┐
        │            implements AIProviderAdapter     │
        │                                             │
   ┌────┴────┐     ┌──────────┐     ┌─────────────┐  │
   │ OpenAI  │     │  Gemini  │     │ OpenRouter   │  │
   │ Adapter │     │ Adapter  │     │  Adapter     │  │
   └─────────┘     └──────────┘     └──────────────┘  │
        │                                             │
        └─────────────────────────────────────────────┘
```

### Key Design Decisions

- **`implements` over `extends`** — Adapters implement the abstract contract, ensuring every method is explicitly handled
- **Sealed `AIContentData`** — Exhaustive switch matching for content types (text, image, audio, video)
- **Mixin for code reuse** — `OpenAICompatibleMixin` shares parsing logic between OpenAI and OpenRouter
- **Retry at the adapter level** — Each adapter manages its own retry strategy via Dio interceptors
- **Middleware at the client level** — Cross-cutting concerns (logging, caching) wrap around all providers uniformly

## Supported Models

### OpenAI
| Model | Tool Calling | JSON Mode | Vision | Context Window |
|-------|:---:|:---:|:---:|---:|
| gpt-4.1 | ✓ | ✓ | ✓ | 1M |
| gpt-4.1-mini | ✓ | ✓ | ✓ | 1M |
| gpt-4.1-nano | ✓ | ✓ | ✓ | 1M |
| gpt-4o | ✓ | ✓ | ✓ | 128K |
| o3 | ✓ | ✓ | ✓ | 200K |
| o4-mini | ✓ | ✓ | ✓ | 200K |

### Google Gemini
| Model | Tool Calling | JSON Mode | Vision | Video | Context Window |
|-------|:---:|:---:|:---:|:---:|---:|
| gemini-2.5-pro | ✓ | ✓ | ✓ | ✓ | 1M |
| gemini-2.5-flash | ✓ | ✓ | ✓ | ✓ | 1M |
| gemini-2.0-flash | ✓ | ✓ | ✓ | ✓ | 1M |

### OpenRouter
Any model available on OpenRouter — capabilities are fetched dynamically via the API.

## Adding a Custom Adapter

```dart
class MyAdapter implements AIProviderAdapter {
  @override
  String get providerId => 'my-provider';

  @override
  Future<AIResponse> generate(AIRequest request) async {
    // Call your API, return normalized AIResponse
  }

  @override
  Stream<AIStreamChunk> stream(AIRequest request) async* {
    // Yield AIStreamChunk for each token
  }

  @override
  Future<List<AIModel>> fetchModels() async => [];

  @override
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) async {
    throw UnimplementedError('Embeddings not supported');
  }

  @override
  AIModelCapabilities capabilitiesFor(String modelId) =>
      const AIModelCapabilities();
}
```

## License

See [LICENSE](LICENSE) for details.
