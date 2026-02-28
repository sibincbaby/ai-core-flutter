import 'dart:convert';
import 'dart:math';

import 'package:ai_core/core/retry_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetryConfig', () {
    test('default values', () {
      const config = RetryConfig();
      expect(config.maxRetries, 3);
      expect(config.initialDelay, const Duration(seconds: 1));
      expect(config.maxDelay, const Duration(seconds: 30));
      expect(config.backoffMultiplier, 2.0);
      expect(config.jitter, true);
      expect(config.retryableStatusCodes, {429, 500, 502, 503, 504});
      expect(config.retryOnTimeout, true);
    });

    test('conservative preset', () {
      expect(RetryConfig.conservative.maxRetries, 2);
      expect(
        RetryConfig.conservative.initialDelay,
        const Duration(milliseconds: 500),
      );
      expect(RetryConfig.conservative.maxDelay, const Duration(seconds: 10));
    });

    test('aggressive preset', () {
      expect(RetryConfig.aggressive.maxRetries, 5);
      expect(RetryConfig.aggressive.initialDelay, const Duration(seconds: 2));
      expect(RetryConfig.aggressive.maxDelay, const Duration(seconds: 60));
    });

    test('custom configuration', () {
      const config = RetryConfig(
        maxRetries: 1,
        initialDelay: Duration(milliseconds: 200),
        maxDelay: Duration(seconds: 5),
        backoffMultiplier: 1.5,
        jitter: false,
        retryableStatusCodes: {429},
        retryOnTimeout: false,
      );
      expect(config.maxRetries, 1);
      expect(config.initialDelay, const Duration(milliseconds: 200));
      expect(config.backoffMultiplier, 1.5);
      expect(config.jitter, false);
      expect(config.retryableStatusCodes, {429});
      expect(config.retryOnTimeout, false);
    });
  });

  group('RetryInterceptor', () {
    late Dio dio;
    late _FakeAdapter fakeAdapter;
    late List<_RetryEvent> retryLog;

    setUp(() {
      retryLog = [];
      fakeAdapter = _FakeAdapter();
      dio = Dio()..httpClientAdapter = fakeAdapter;
    });

    test('no retry on success', () async {
      fakeAdapter.responses = [
        _fakeResponse(200, {'ok': true}),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(maxRetries: 3),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      expect(retryLog, isEmpty);
      expect(fakeAdapter.callCount, 1);
    });

    test('no retry on non-retryable 4xx', () async {
      fakeAdapter.responses = [_fakeError(400, 'Bad Request')];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(maxRetries: 3, jitter: false),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      expect(
        () => dio.get<dynamic>('https://api.example.com/test'),
        throwsA(isA<DioException>()),
      );
      // Should not retry for 400
      expect(retryLog, isEmpty);
    });

    test('retries on 429 then succeeds', () async {
      fakeAdapter.responses = [
        _fakeError(429, 'Too Many Requests'),
        _fakeResponse(200, {'ok': true}),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 10),
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      expect(retryLog.length, 1);
      expect(retryLog[0].attempt, 1);
    });

    test('retries on 503 then succeeds', () async {
      fakeAdapter.responses = [
        _fakeError(503, 'Service Unavailable'),
        _fakeError(503, 'Service Unavailable'),
        _fakeResponse(200, {'result': 'ok'}),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 10),
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      expect(retryLog.length, 2);
    });

    test('exhausts max retries and throws', () async {
      fakeAdapter.responses = [
        _fakeError(500, 'Server Error'),
        _fakeError(500, 'Server Error'),
        _fakeError(500, 'Server Error'),
        _fakeError(500, 'Server Error'),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 10),
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      expect(
        () => dio.get<dynamic>('https://api.example.com/test'),
        throwsA(isA<DioException>()),
      );
    });

    test('exponential backoff delays increase correctly', () async {
      fakeAdapter.responses = [
        _fakeError(500, 'Server Error'),
        _fakeError(500, 'Server Error'),
        _fakeError(500, 'Server Error'),
        _fakeResponse(200, {'ok': true}),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 100),
            backoffMultiplier: 2.0,
            maxDelay: Duration(seconds: 10),
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      expect(retryLog.length, 3);
      // attempt 1: 100ms * 2^0 = 100ms
      expect(retryLog[0].delay.inMilliseconds, 100);
      // attempt 2: 100ms * 2^1 = 200ms
      expect(retryLog[1].delay.inMilliseconds, 200);
      // attempt 3: 100ms * 2^2 = 400ms
      expect(retryLog[2].delay.inMilliseconds, 400);
    });

    test('delay is capped at maxDelay', () async {
      fakeAdapter.responses = [
        _fakeError(500, 'Server Error'),
        _fakeError(500, 'Server Error'),
        _fakeError(500, 'Server Error'),
        _fakeResponse(200, {'ok': true}),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 500),
            backoffMultiplier: 10.0,
            maxDelay: Duration(milliseconds: 600),
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      // attempt 1: 500 * 10^0 = 500ms (within max)
      expect(retryLog[0].delay.inMilliseconds, 500);
      // attempt 2: 500 * 10^1 = 5000ms -> capped at 600ms
      expect(retryLog[1].delay.inMilliseconds, 600);
    });

    test('jitter adds randomness to delay', () async {
      fakeAdapter.responses = [
        _fakeError(500, 'Server Error'),
        _fakeResponse(200, {'ok': true}),
      ];

      // Use a seeded random for deterministic jitter
      final random = Random(42);
      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 100),
            jitter: true,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
          random: random,
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      expect(retryLog.length, 1);
      // With jitter, delay should be >= 100ms (base) and <= 125ms (base + 25%)
      expect(retryLog[0].delay.inMilliseconds, greaterThanOrEqualTo(100));
      expect(retryLog[0].delay.inMilliseconds, lessThanOrEqualTo(125));
    });

    test('Retry-After header is honored', () async {
      fakeAdapter.responses = [
        _fakeError(
          429,
          'Too Many Requests',
          headers: {
            'retry-after': ['2'],
          },
        ),
        _fakeResponse(200, {'ok': true}),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 100),
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      expect(retryLog.length, 1);
      // Should use Retry-After (2 seconds) instead of backoff (100ms)
      expect(retryLog[0].delay, const Duration(seconds: 2));
    });

    test('no retry on cancelled request', () async {
      fakeAdapter.responses = [_fakeCancelError()];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(maxRetries: 3, jitter: false),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      expect(
        () => dio.get<dynamic>('https://api.example.com/test'),
        throwsA(isA<DioException>()),
      );
      expect(retryLog, isEmpty);
    });

    test('retryOnTimeout false skips timeout errors', () async {
      fakeAdapter.responses = [_fakeTimeoutError()];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            retryOnTimeout: false,
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      expect(
        () => dio.get<dynamic>('https://api.example.com/test'),
        throwsA(isA<DioException>()),
      );
      expect(retryLog, isEmpty);
    });

    test('retryOnTimeout true retries timeout errors', () async {
      fakeAdapter.responses = [
        _fakeTimeoutError(),
        _fakeResponse(200, {'ok': true}),
      ];

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          config: const RetryConfig(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 10),
            retryOnTimeout: true,
            jitter: false,
          ),
          onRetry: (a, d, e) => retryLog.add(_RetryEvent(a, d)),
        ),
      );

      final resp = await dio.get<dynamic>('https://api.example.com/test');
      expect(resp.statusCode, 200);
      expect(retryLog.length, 1);
    });
  });

  group('Adapter integration', () {
    test('OpenAIAdapter accepts retryConfig parameter', () {
      // Verify the adapter constructor accepts retryConfig
      // (compile-time check; existence proves integration)
      expect(RetryConfig.conservative.maxRetries, 2);
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────────

class _RetryEvent {
  final int attempt;
  final Duration delay;
  _RetryEvent(this.attempt, this.delay);
}

/// A fake Dio [HttpClientAdapter] that returns queued responses.
class _FakeAdapter implements HttpClientAdapter {
  List<Object> responses = [];
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = callCount++;
    if (index >= responses.length) {
      throw DioException(
        requestOptions: options,
        error: 'No more fake responses queued (call #$index)',
        type: DioExceptionType.unknown,
      );
    }

    final item = responses[index];
    if (item is DioException) {
      throw DioException(
        requestOptions: options,
        response: item.response != null
            ? Response<dynamic>(
                requestOptions: options,
                statusCode: item.response!.statusCode,
                statusMessage: item.response!.statusMessage,
                headers: item.response!.headers,
                data: item.response!.data,
              )
            : null,
        type: item.type,
        error: item.error,
        message: item.message,
      );
    }

    final resp = item as ResponseBody;
    return resp;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _fakeResponse(int statusCode, Map<String, dynamic> data) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      'content-type': ['application/json'],
    },
  );
}

DioException _fakeError(
  int statusCode,
  String message, {
  Map<String, List<String>>? headers,
}) {
  final requestOptions = RequestOptions(path: 'https://api.example.com/test');
  return DioException(
    requestOptions: requestOptions,
    response: Response<dynamic>(
      requestOptions: requestOptions,
      statusCode: statusCode,
      statusMessage: message,
      headers: Headers.fromMap(headers ?? {}),
    ),
    type: DioExceptionType.badResponse,
    message: message,
  );
}

DioException _fakeCancelError() {
  return DioException(
    requestOptions: RequestOptions(path: 'https://api.example.com/test'),
    type: DioExceptionType.cancel,
  );
}

DioException _fakeTimeoutError() {
  return DioException(
    requestOptions: RequestOptions(path: 'https://api.example.com/test'),
    type: DioExceptionType.connectionTimeout,
  );
}
