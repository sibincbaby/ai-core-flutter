/// Fingertiplabs AI Core SDK — Full Flutter entry point.
///
/// Re-exports everything from [ai_core_base.dart] (pure Dart) plus
/// Flutter-specific utilities like [FlutterSecureStorageBackend].
///
/// ```dart
/// import 'package:ai_core/ai_core.dart'; // Flutter projects
/// ```
///
/// For pure Dart usage (CLI, server-side, no Flutter dependency), use:
/// ```dart
/// import 'package:ai_core/ai_core_base.dart';
/// ```
library;

// Everything from the pure-Dart core
export 'ai_core_base.dart';

// Flutter-specific storage implementation
export 'storage/secure_key_manager.dart';
