import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../models/ai_stream_chunk.dart';

/// Signature for the next handler in the middleware chain.
typedef GenerateNext = Future<AIResponse> Function(AIRequest request);

/// Signature for the next streaming handler in the middleware chain.
typedef StreamNext = Stream<AIStreamChunk> Function(AIRequest request);

/// Abstract middleware that can intercept generate and stream calls.
///
/// Middleware forms a chain: each middleware can inspect/modify the request
/// before forwarding it, and inspect/modify the response after receiving it.
///
/// ```dart
/// class LoggingMiddleware extends AIMiddleware {
///   @override
///   Future<AIResponse> onGenerate(AIRequest request, GenerateNext next) async {
///     print('→ ${request.model}');
///     final response = await next(request);
///     print('← ${response.usage?.totalTokens} tokens');
///     return response;
///   }
/// }
/// ```
abstract class AIMiddleware {
  /// Intercept a non-streaming generation call.
  ///
  /// Call `next(request)` to continue the chain. You may modify the request
  /// before passing it, or the response after receiving it.
  Future<AIResponse> onGenerate(AIRequest request, GenerateNext next) {
    return next(request);
  }

  /// Intercept a streaming generation call.
  ///
  /// Call `next(request)` to continue the chain. You may transform the
  /// returned stream.
  Stream<AIStreamChunk> onStream(AIRequest request, StreamNext next) {
    return next(request);
  }
}

/// A pipeline that chains multiple [AIMiddleware] instances.
///
/// Middleware is applied in order: the first middleware added is the outermost
/// wrapper (first to receive requests, last to see responses).
class MiddlewarePipeline {
  final List<AIMiddleware> _middlewares = [];

  /// The middleware list (read-only view).
  List<AIMiddleware> get middlewares => List.unmodifiable(_middlewares);

  /// Add a middleware to the end of the pipeline.
  void add(AIMiddleware middleware) {
    _middlewares.add(middleware);
  }

  /// Add multiple middlewares to the end of the pipeline.
  void addAll(Iterable<AIMiddleware> middlewares) {
    _middlewares.addAll(middlewares);
  }

  /// Remove a middleware from the pipeline.
  bool remove(AIMiddleware middleware) {
    return _middlewares.remove(middleware);
  }

  /// Remove all middlewares of a specific type.
  void removeWhere(bool Function(AIMiddleware) test) {
    _middlewares.removeWhere(test);
  }

  /// Clear all middlewares.
  void clear() {
    _middlewares.clear();
  }

  /// Wrap a generate function with the middleware chain.
  GenerateNext wrapGenerate(GenerateNext innerHandler) {
    var handler = innerHandler;
    // Build chain from inside out (last middleware wraps closest to handler).
    for (var i = _middlewares.length - 1; i >= 0; i--) {
      final middleware = _middlewares[i];
      final next = handler;
      handler = (request) => middleware.onGenerate(request, next);
    }
    return handler;
  }

  /// Wrap a stream function with the middleware chain.
  StreamNext wrapStream(StreamNext innerHandler) {
    var handler = innerHandler;
    for (var i = _middlewares.length - 1; i >= 0; i--) {
      final middleware = _middlewares[i];
      final next = handler;
      handler = (request) => middleware.onStream(request, next);
    }
    return handler;
  }
}
