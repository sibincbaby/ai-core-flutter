/// Fingertiplabs AI Core SDK — Pure Dart entry point.
///
/// This barrel export includes everything **except** Flutter-specific code
/// (`FlutterSecureStorageBackend` from `secure_key_manager.dart`).
///
/// Use this import when:
/// - Building a pure Dart application (CLI, server, etc.)
/// - You want to provide your own [StorageBackend] implementation
/// - You don't need `flutter_secure_storage`
///
/// ```dart
/// import 'package:ai_core/ai_core_base.dart';
/// ```
///
/// For the full Flutter-inclusive API (adds [FlutterSecureStorageBackend]),
/// use `package:ai_core/ai_core.dart` instead.
library;

// Client & Registry
export 'ai_client.dart';
export 'ai_provider_registry.dart';
export 'conversation_manager.dart';

// Core contracts
export 'core/ai_provider_adapter.dart';
export 'core/capability_validator.dart';
export 'core/middleware.dart';
export 'core/retry_interceptor.dart';

// Models
export 'models/ai_content.dart';
export 'models/ai_cost.dart';
export 'models/ai_embedding.dart';
export 'models/ai_message.dart';
export 'models/ai_request.dart';
export 'models/ai_response.dart';
export 'models/ai_stream_chunk.dart';
export 'models/ai_model.dart';
export 'models/ai_provider_config.dart';
export 'models/ai_response_format.dart';
export 'models/ai_tool.dart';

// Errors
export 'errors/ai_exception.dart';

// Adapters (all are pure Dart — they only depend on Dio)
export 'adapters/openai_adapter.dart';
export 'adapters/gemini_adapter.dart';
export 'adapters/openrouter_adapter.dart';

// Storage (abstract interface only — no Flutter dependency)
export 'storage/storage_backend.dart';
