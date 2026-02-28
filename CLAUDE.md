# AI Core Flutter — Development Guidelines

> Persistent instructions for AI assistants working on this project.
> Read this BEFORE making any changes.

## Golden Rule

**Always research the latest official API documentation BEFORE implementing or updating any provider adapter, model catalog, or pricing table.** Never rely on memory or assumptions about API schemas, model names, headers, or pricing — these change frequently. Fetch the docs, verify, then implement.

---

## 1. Pre-Implementation Research Checklist

Before touching any adapter, model catalog, or provider-specific code:

### 1.1 Fetch Latest API Docs

| Provider | Documentation URLs to fetch | What to verify |
|----------|---------------------------|----------------|
| **OpenAI** | `https://platform.openai.com/docs/api-reference/chat` | Request/response schema, headers, model list, supported parameters, pricing |
| **OpenAI Models** | `https://platform.openai.com/docs/models` | Model IDs, context windows, capabilities, deprecation notices |
| **OpenAI Pricing** | `https://openai.com/api/pricing/` | Input/output/cached token prices per model |
| **Google Gemini** | `https://ai.google.dev/gemini-api/docs` | API format, model list, capabilities, content types |
| **Gemini Models** | `https://ai.google.dev/gemini-api/docs/models` | Model IDs, context windows, supported features |
| **Gemini Pricing** | `https://ai.google.dev/pricing` | Token pricing per model tier |
| **OpenRouter** | `https://openrouter.ai/docs/api-reference/overview` | Request schema, headers, provider routing, plugins |
| **OpenRouter Models** | `https://openrouter.ai/docs/api-reference/models` | Model listing API, capability fields, supported_parameters |
| **OpenRouter Features** | `https://openrouter.ai/docs/guides/routing/provider-selection` | Provider preferences, model fallbacks, data policies |

### 1.2 What to Check in Docs

- [ ] **Request schema** — New fields added? Fields renamed or deprecated?
- [ ] **Response schema** — New fields in usage, choices, or metadata?
- [ ] **Headers** — Required/optional headers changed? (e.g. `X-Title` → `X-OpenRouter-Title`)
- [ ] **Model IDs** — New models? Renamed models? Deprecated models?
- [ ] **Capabilities** — New capability flags? (e.g. `supported_parameters` in OpenRouter)
- [ ] **Pricing** — Price changes? New pricing tiers? Cached input pricing?
- [ ] **Authentication** — Any changes to auth flow or key format?
- [ ] **Error codes** — New error types or status codes?
- [ ] **Breaking changes** — API version bumps, sunset notices

### 1.3 Research Log

After fetching docs, briefly note what was checked and what changed. This avoids re-researching the same docs in the same session.

---

## 2. Project Architecture

### 2.1 Core Patterns

- **`implements` not `extends`** — All adapters use `implements AIProviderAdapter`. Every abstract method must be explicitly implemented in every adapter AND test mock.
- **Sealed `AIContentData`** — Content types are a sealed class. Adding a new subclass requires exhaustive switch updates everywhere.
- **`OpenAICompatibleMixin`** — Shared request/response logic for OpenAI + OpenRouter.  Gemini has its own format.
- **`request.extra`** — Provider-specific fields (OpenRouter options, etc.) are passed via the `extra: Map<String, dynamic>` field on `AIRequest`.
- **Static consts, not factories** — `AIToolChoice.auto`, `AIResponseFormat.json`, `RetryConfig.conservative` are `static const`.
- **3-tier capability resolution** — `_resolveCapabilities` in OpenAI/Gemini adapters: exact match → longest-prefix match → family inference. Unknown future models automatically get reasonable defaults.
- **Exclusion-based fetchModels** — OpenAI `fetchModels` uses an exclusion filter (blocks embeddings, DALL-E, TTS, etc.) so new model families are included by default.
- **Family pricing inference** — `AICostCalculator.getPricing` falls back to median pricing from the same model family for unknown models (e.g. `gpt-6-turbo` gets median of all `gpt-*` pricing).
- **Multi-key pools (explicit, no rotation)** — `AIKeyPool` holds labeled keys per provider. Keys are resolved via `request.keyTag` or `pool.defaultLabel`. **No automatic rotation** — the user controls which key is used. Each adapter calls `_resolveKeyOptions()` to override the Authorization header and `_recordKeyUsage()` to track tokens per key.

### 2.2 Key Files

| Purpose | File |
|---------|------|
| Abstract adapter contract | `lib/core/ai_provider_adapter.dart` |
| Key pool (multi-key) | `lib/core/ai_key_pool.dart` |
| OpenAI adapter | `lib/adapters/openai_adapter.dart` |
| Gemini adapter | `lib/adapters/gemini_adapter.dart` |
| OpenRouter adapter | `lib/adapters/openrouter_adapter.dart` |
| Shared OpenAI/OR logic | `lib/adapters/openai_compatible_mixin.dart` |
| OpenRouter typed options | `lib/models/openrouter_options.dart` |
| Request model | `lib/models/ai_request.dart` |
| Response model | `lib/models/ai_response.dart` |
| Content types (sealed) | `lib/models/ai_content.dart` |
| Cost/pricing | `lib/models/ai_cost.dart` |
| Model capabilities | `lib/models/ai_model.dart` |
| Provider config | `lib/models/ai_provider_config.dart` |
| Barrel export (pure Dart) | `lib/ai_core_base.dart` |
| Barrel export (Flutter) | `lib/ai_core.dart` |

### 2.3 Config Gotchas

- `AIProviderConfig` uses `id` + `providerType` (NOT `providerId` / `defaultModel`)
- `ConversationManager` requires `model` parameter; history via `.messages` not `.history`
- `register()` takes a single adapter argument

---

## 3. Implementation Standards

### 3.1 Adding/Updating a Provider Adapter

1. **Fetch latest docs** (see Section 1)
2. Read the existing adapter code fully before editing
3. Maintain `implements AIProviderAdapter` — never switch to `extends`
4. Use `OpenAICompatibleMixin` for OpenAI-compatible APIs
5. Provider-specific features go via `extra` field + typed options class
6. Update tests — every adapter change needs corresponding test updates
7. Update README model tables and feature sections
8. Update CHANGELOG.md
9. Run `dart analyze lib/` — must show **0 issues**
10. Run `flutter test` — all tests must pass

### 3.2 Updating Model Catalogs

1. **Fetch latest model listings from official docs** (mandatory)
2. Update `knownModels` map in the adapter with:
   - Correct model IDs (exact strings used in API calls)
   - Accurate context windows
   - Correct capability flags
3. Update pricing in `lib/models/ai_cost.dart`
4. Update README model tables
5. Mark deprecated models clearly (keep them but note in comments)
6. Test that pricing assertions still hold

**Note:** Thanks to the 3-tier resolution system, you do NOT need to update code for every new model release. The system automatically handles:
- **Dated variants** (e.g. `gpt-4o-2025-08-06`) → prefix matches `gpt-4o`
- **Unknown models in known families** (e.g. `gpt-6-turbo`) → family inference gives vision+tools+JSON
- **Pricing for unknown models** (e.g. `gemini-4-ultra`) → median family pricing

You only need to update `knownModels` and pricing when you want **accurate** capabilities/pricing for specific models.

### 3.3 Code Quality

- Analysis: `strict-casts`, `strict-inference`, `strict-raw-types` are ALL enabled
- `avoid_dynamic_calls` lint is active — no untyped dynamic access
- Run `dart analyze lib/` before committing — zero warnings/errors
- Run `flutter test` before committing — all tests pass
- No `// ignore:` comments without documented justification

### 3.4 Testing

- Mock HTTP with `MockDioAdapter` (see `test/helpers/mock_dio_adapter.dart`)
- Test both success and error paths
- Test streaming with SSE mock events
- Test capability parsing from API responses
- Integration tests are in `test/integration/` (require real API keys in `.env`)

---

## 4. Commit & Release Workflow

### 4.1 Commit Messages

Use conventional commits:
```
feat: short description
fix: short description
docs: short description
refactor: short description
```

Include a body listing specific changes.

### 4.2 Versioning

- Bump version in `pubspec.yaml`
- Add entry to `CHANGELOG.md` at the top
- Follow semver: `0.x.y` during pre-1.0 development

### 4.3 Git Remote

- Remote: `git@github-personal:sibincbaby/ai-core-flutter.git`
- Branch: `main`

---

## 5. Common Mistakes to Avoid

| Mistake | Correct Approach |
|---------|-----------------|
| Implementing from memory without checking docs | Always fetch and read the latest API docs first |
| Using outdated model names/IDs | Verify model IDs against the official model listing page |
| Assuming header names haven't changed | Check the exact header names in current API reference |
| Not parsing new API response fields | Read the full response schema for new fields |
| Using `extends` instead of `implements` | All adapters use `implements AIProviderAdapter` |
| Adding `@override` for non-abstract methods | Only use `@override` for methods defined in the abstract class |
| Forgetting to export new files | Add to `ai_core_base.dart` (and `ai_core.dart` if Flutter-specific) |
| Not updating the README | Every feature change needs README updates |
| Skipping `dart analyze` | Must run before every commit |
| Hardcoding capabilities | Parse from API response where possible (e.g. OpenRouter `supported_parameters`) |
| Adding inclusion filters for new model families | Use exclusion filters — new families are included by default |
| Returning empty capabilities for unknown models | Use family inference — `gpt-*`, `o\d*`, `gemini-*` get sensible defaults |

---

## 6. Provider-Specific Notes

### 6.1 OpenAI

- Base URL: `https://api.openai.com`
- Endpoint: `/v1/chat/completions`
- Models API: `/v1/models`
- Auth: `Authorization: Bearer sk-...`
- `knownModels` map contains hardcoded capabilities (OpenAI doesn't expose `supported_parameters` in their model list)
- `fetchModels` uses **exclusion filter** — blocks embeddings/DALL-E/TTS/whisper/legacy, includes everything else by default
- `_resolveCapabilities` uses 3-tier lookup: exact → prefix → family inference (any `gpt-*`/`o\d*` → vision+tools+JSON)

### 6.2 Google Gemini

- Base URL: `https://generativelanguage.googleapis.com`
- Endpoint: `/v1beta/models/{model}:generateContent`
- Streaming: `/v1beta/models/{model}:streamGenerateContent?alt=sse`
- Auth: `?key=AIza...` query parameter
- Has native video support (unlike OpenAI)
- `_resolveCapabilities` uses 3-tier lookup: exact → prefix → family inference (any `gemini-*` → full multimodal+tools+JSON)
- Supports `cachedContent` for long context caching

### 6.3 OpenRouter

- Base URL: `https://openrouter.ai/api`
- Endpoint: `/v1/chat/completions` (OpenAI-compatible)
- Auth: `Authorization: Bearer sk-or-...`
- Headers: `HTTP-Referer` (site URL), `X-OpenRouter-Title` (app name)
- Capabilities fetched dynamically via `/v1/models` API — parse `supported_parameters`, `architecture.input_modalities`
- Provider-specific features via `OpenRouterOptions` → `request.extra`
- Supports: provider routing, model fallbacks, plugins (web, response-healing, file-parser), auto-router (`openrouter/auto`), prompt transforms

---

## 7. Session Startup Protocol

When starting a new development session on this project:

1. **Read this file** (CLAUDE.md) — you're doing this now
2. **Read CHANGELOG.md** — understand recent changes and current version
3. **Check for pending issues** — `dart analyze lib/` and `flutter test`
4. **If touching provider code** — fetch latest API docs per Section 1
5. **If touching model catalogs** — verify model IDs and pricing are current
6. **Plan before implementing** — use todo lists for multi-step work

---

*Last updated: 2026-02-28 (v0.1.4)*
