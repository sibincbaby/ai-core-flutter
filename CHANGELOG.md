## 0.1.2

### Updated
- **OpenRouter Adapter** — Updated `X-Title` header to canonical `X-OpenRouter-Title`; `fetchModels` now parses `supported_parameters` for tool calling and JSON mode; added `capabilitiesFor()` with cached lookups
- **OpenRouterOptions** — New typed helper class for OpenRouter-specific features: provider routing (`ProviderPreferences`), model fallbacks, plugins (`OpenRouterPlugin.web()`, `.responseHealing()`, `.fileParser()`), transforms, and user identification
- **README** — Added OpenRouter-specific features section with provider routing, model fallbacks, plugins, and auto-router examples

## 0.1.1

### Updated
- **Model Catalog (Feb 2026)** — Added OpenAI GPT-5 family (gpt-5.2, gpt-5.1, gpt-5, gpt-5-mini, gpt-5-nano), o3-pro; Added Gemini 3 family (gemini-3.1-pro-preview, gemini-3-flash-preview), gemini-2.5-flash-lite, gemini-embedding-001
- **Pricing Tables** — Updated to Feb 2026 pricing; fixed Gemini 2.5 Flash ($0.30/$2.50 including thinking tokens); added cached input pricing for GPT-5 and Gemini 3 models
- **Deprecations** — Marked o1-mini (removed), gemini-2.0-flash/lite, gemini-1.x as legacy; OpenAI fetchModels filter now catches gpt-5 prefix
- **README** — Updated supported model tables to reflect current landscape

## 0.1.0

### Added
- **Tool/Function Calling** — `AITool`, `AIToolCall`, `AIToolChoice` models; tool serialization in OpenAI, Gemini, and OpenRouter adapters
- **Structured Output** — `AIResponseFormat` with text, JSON, and JSON Schema modes
- **Retry & Resilience** — `RetryInterceptor` with exponential backoff, jitter, Retry-After header support, and `RetryConfig` presets (conservative, aggressive)
- **Middleware Pipeline** — `AIMiddleware` abstract class and `MiddlewarePipeline` for intercepting `generate` and `stream` calls
- **Conversation Manager** — `ConversationManager` with multi-turn history, automatic tool-call loops, and `ToolExecutor` callback
- **Embeddings API** — `AIEmbeddingRequest`/`AIEmbeddingResponse` models; `embed()` on `AIClient` and adapters (OpenAI, Gemini)
- **Cost/Pricing Tracking** — `AICostCalculator` with built-in pricing for OpenAI & Gemini models, `AICostTracker` for cumulative usage, custom pricing support
- **Video Content** — `VideoUrlContent`, `VideoBytesContent` sealed subclasses; Gemini adapter video support
- **Updated Model Catalog** — GPT-4.1 family, o3, o4-mini, Gemini 2.5 Pro/Flash with context windows and capability flags
- **Pure-Dart Core** — `ai_core_base.dart` barrel export for non-Flutter usage
- **Comprehensive README** — Full documentation with architecture diagrams, usage examples, and supported model tables

### Changed
- `AIModelCapabilities` — Added `supportsToolCalling`, `supportsJsonMode`, `supportsVideoInput`, `maxContextWindow`
- `AIMessage` — Added `AIRole.tool`, `toolCalls`, `toolCallId` fields and `toolCalls()`/`toolResult()` factories
- `AIRequest` — Added `tools`, `toolChoice`, `responseFormat` fields with `copyWith`
- `AIResponse` — Added `toolCalls` list and `hasToolCalls` getter
- `AIStreamChunk` — Added `toolCallDeltas` for incremental tool call streaming
- `AIProviderAdapter` — Added `embed()` method to the adapter contract
- `AIClient` — Added `embed()` delegation and middleware integration
- `ai_core.dart` — Re-exports via `ai_core_base.dart` for clean separation

## 0.0.1

* Initial release with OpenAI, Gemini, and OpenRouter adapters, streaming, multimodal input, capability validation, and secure key storage.
