## 0.1.5

### Improved
- **`AIMessage.user`** — Now accepts optional `content:` parameter for multimodal messages
- **`AIContentBlock.videoUrl`** — Accepts optional `mimeType:` (Gemini uses it instead of hardcoding `video/mp4`)
- **`AIContentBlock.imageUrl`** — Accepts optional `mimeType:` (Gemini uses it instead of hardcoding `image/jpeg`)
- **`MiddlewarePipeline`** — Constructor now accepts optional initial `middlewares` list
- **`ConversationManager`** — Added `keyTag` and `extra` fields, passed through to every request in the conversation
- **Pricing** — Added `o3-pro` pricing ($150/$600 per M tokens)

### Fixed
- Broken syntax in `test/manual/test_providers.dart`
- Unused and unnecessary imports in tests and adapter files

## 0.1.4

### Added
- **Multi-Key Management** — `AIKeyPool` allows multiple labeled API keys per provider with explicit selection and per-key usage tracking
  - `AIKeyEntry(key, label:)` — labeled key entry
  - `AIKeyPool(entries:, defaultLabel:)` — key store with `resolve()`, `recordUsage()`, `usageFor()`, `resetUsage()`
  - `AIProviderConfig.keyPool` — optional key pool attachment
  - `AIRequest.keyTag` — explicit key selection per request
  - All three adapters (OpenAI, Gemini, OpenRouter) resolve keys from pool and track usage automatically
  - **No automatic rotation** — keys are selected explicitly via `keyTag` or the manually-set `defaultLabel`

## 0.1.3

### Improved
- **3-tier capability resolution** — OpenAI and Gemini adapters now resolve capabilities via: exact match → longest-prefix match → family inference. Unknown future models (e.g. `gpt-6-turbo`, `o5-pro`, `gemini-4-ultra`) automatically get reasonable defaults without code changes.
- **Exclusion-based fetchModels** — OpenAI `fetchModels` switched from inclusion filter to exclusion filter, so new model families are included by default rather than silently dropped.
- **Family pricing inference** — `AICostCalculator.getPricing` now falls back to median pricing from the same model family for completely unknown models.
- **CLAUDE.md** — Documented new patterns (3-tier resolution, exclusion filters, family inference) in development guidelines.

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
