import 'dart:math';

import 'package:dio/dio.dart';

/// Configuration for retry behavior.
class RetryConfig {
  /// Maximum number of retry attempts (excluding the initial request).
  final int maxRetries;

  /// Initial delay before the first retry.
  final Duration initialDelay;

  /// Maximum delay cap (backoff won't exceed this).
  final Duration maxDelay;

  /// Backoff multiplier applied after each retry.
  final double backoffMultiplier;

  /// Whether to add random jitter to avoid thundering herd.
  final bool jitter;

  /// HTTP status codes that should trigger a retry.
  final Set<int> retryableStatusCodes;

  /// Whether to retry on connection/timeout errors.
  final bool retryOnTimeout;

  const RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitter = true,
    this.retryableStatusCodes = const {429, 500, 502, 503, 504},
    this.retryOnTimeout = true,
  });

  /// Conservative config: fewer retries, shorter delays.
  static const conservative = RetryConfig(
    maxRetries: 2,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 10),
  );

  /// Aggressive config: more retries, longer delays.
  static const aggressive = RetryConfig(
    maxRetries: 5,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 60),
  );
}

/// A Dio interceptor that retries failed requests with exponential backoff.
///
/// Automatically retries on:
/// - Rate limiting (429) — honors Retry-After header if present
/// - Server errors (5xx)
/// - Network/timeout errors (configurable)
///
/// Usage:
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(RetryInterceptor());
/// ```
class RetryInterceptor extends Interceptor {
  final RetryConfig config;
  final Dio _dio;
  final Random _random;

  /// Optional callback invoked before each retry attempt.
  /// Useful for logging or metrics.
  final void Function(int attempt, Duration delay, Object error)? onRetry;

  RetryInterceptor({
    required Dio dio,
    this.config = const RetryConfig(),
    this.onRetry,
    Random? random,
  }) : _dio = dio,
       _random = random ?? Random();

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    final attempts = _getAttemptCount(err.requestOptions);
    if (attempts >= config.maxRetries) {
      return handler.next(err);
    }

    final delay = _calculateDelay(attempts, err);

    onRetry?.call(attempts + 1, delay, err);

    await Future<void>.delayed(delay);

    // Increment attempt counter.
    err.requestOptions.extra['_retry_attempt'] = attempts + 1;

    try {
      final response = await _retry(err);
      handler.resolve(response);
    } on DioException catch (retryError) {
      // Let this new error go through the interceptor chain again,
      // which will catch it here for the next retry attempt.
      handler.reject(retryError);
    }
  }

  bool _shouldRetry(DioException err) {
    // Connection/timeout errors.
    if (_isTimeoutError(err)) {
      return config.retryOnTimeout;
    }

    // Cancelled requests should never be retried.
    if (err.type == DioExceptionType.cancel) {
      return false;
    }

    // HTTP status code check.
    final statusCode = err.response?.statusCode;
    if (statusCode != null) {
      return config.retryableStatusCodes.contains(statusCode);
    }

    return false;
  }

  bool _isTimeoutError(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError;
  }

  int _getAttemptCount(RequestOptions options) {
    return (options.extra['_retry_attempt'] as int?) ?? 0;
  }

  Duration _calculateDelay(int attempt, DioException err) {
    // Honor Retry-After header for 429 responses.
    final retryAfter = _parseRetryAfter(err);
    if (retryAfter != null) {
      return retryAfter;
    }

    // Exponential backoff.
    final baseDelay =
        config.initialDelay.inMilliseconds *
        pow(config.backoffMultiplier, attempt);
    var delayMs = min(baseDelay, config.maxDelay.inMilliseconds).toInt();

    // Add jitter (0% to 25% of delay).
    if (config.jitter) {
      final jitterMs = (_random.nextDouble() * delayMs * 0.25).toInt();
      delayMs += jitterMs;
    }

    return Duration(milliseconds: delayMs);
  }

  Duration? _parseRetryAfter(DioException err) {
    final headers = err.response?.headers;
    if (headers == null) return null;

    final retryAfterValues = headers['retry-after'];
    if (retryAfterValues == null || retryAfterValues.isEmpty) return null;

    final value = retryAfterValues.first;

    // Try parsing as seconds (integer).
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return Duration(seconds: seconds);
    }

    // Could be an HTTP date, but for simplicity we skip date parsing.
    return null;
  }

  Future<Response<dynamic>> _retry(DioException err) async {
    final requestOptions = err.requestOptions;

    // Re-use the original Dio instance so the same adapter / base config
    // is used.  The attempt counter in `extra` prevents infinite loops.
    return _dio.fetch<dynamic>(requestOptions);
  }
}
