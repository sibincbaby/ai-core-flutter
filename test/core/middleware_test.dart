import 'package:ai_core/core/middleware.dart';
import 'package:ai_core/models/ai_message.dart';
import 'package:ai_core/models/ai_request.dart';
import 'package:ai_core/models/ai_response.dart';
import 'package:ai_core/models/ai_stream_chunk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIMiddleware', () {
    test('default onGenerate passes through unchanged', () async {
      final middleware = _PassthroughMiddleware();
      final request = _testRequest();
      final response = _testResponse();

      final result = await middleware.onGenerate(
        request,
        (_) async => response,
      );
      expect(result, same(response));
    });

    test('default onStream passes through unchanged', () async {
      final middleware = _PassthroughMiddleware();
      final request = _testRequest();
      final chunks = [_testChunk('hello'), _testChunk('world', done: true)];

      final stream = middleware.onStream(
        request,
        (_) => Stream.fromIterable(chunks),
      );
      final collected = await stream.toList();
      expect(collected, chunks);
    });
  });

  group('MiddlewarePipeline', () {
    test('empty pipeline passes generate through', () async {
      final pipeline = MiddlewarePipeline();
      final response = _testResponse();

      final handler = pipeline.wrapGenerate((_) async => response);
      final result = await handler(_testRequest());
      expect(result, same(response));
    });

    test('empty pipeline passes stream through', () async {
      final pipeline = MiddlewarePipeline();
      final chunks = [_testChunk('hi')];

      final handler = pipeline.wrapStream((_) => Stream.fromIterable(chunks));
      final collected = await handler(_testRequest()).toList();
      expect(collected, chunks);
    });

    test('middleware can modify request before forwarding', () async {
      final pipeline = MiddlewarePipeline();
      pipeline.add(_MaxTokensMiddleware(100));

      String? capturedModel;
      int? capturedMaxTokens;

      final handler = pipeline.wrapGenerate((req) async {
        capturedModel = req.model;
        capturedMaxTokens = req.maxTokens;
        return _testResponse();
      });

      await handler(_testRequest());
      expect(capturedModel, 'test-model');
      expect(capturedMaxTokens, 100);
    });

    test('middleware can modify response after receiving', () async {
      final pipeline = MiddlewarePipeline();
      pipeline.add(_ResponseTagMiddleware('[tagged]'));

      final handler = pipeline.wrapGenerate(
        (_) async => _testResponse(text: 'hello'),
      );
      final result = await handler(_testRequest());
      expect(result.text, '[tagged] hello');
    });

    test('middleware execution order: first added is outermost', () async {
      final pipeline = MiddlewarePipeline();
      final log = <String>[];

      pipeline.add(_LoggingMiddleware('A', log));
      pipeline.add(_LoggingMiddleware('B', log));

      final handler = pipeline.wrapGenerate((_) async {
        log.add('handler');
        return _testResponse();
      });

      await handler(_testRequest());
      // A wraps B wraps handler:
      // A.before -> B.before -> handler -> B.after -> A.after
      expect(log, ['A:before', 'B:before', 'handler', 'B:after', 'A:after']);
    });

    test('middleware can short-circuit without calling next', () async {
      final pipeline = MiddlewarePipeline();
      final cachedResponse = _testResponse(text: 'cached');
      pipeline.add(_CachingMiddleware(cachedResponse));

      var handlerCalled = false;
      final handler = pipeline.wrapGenerate((_) async {
        handlerCalled = true;
        return _testResponse(text: 'fresh');
      });

      final result = await handler(_testRequest());
      expect(result.text, 'cached');
      expect(handlerCalled, false);
    });

    test('middleware can transform stream chunks', () async {
      final pipeline = MiddlewarePipeline();
      pipeline.add(_UpperCaseStreamMiddleware());

      final handler = pipeline.wrapStream(
        (_) => Stream.fromIterable([
          _testChunk('hello'),
          _testChunk('world', done: true),
        ]),
      );

      final collected = await handler(_testRequest()).toList();
      expect(collected[0].textDelta, 'HELLO');
      expect(collected[1].textDelta, 'WORLD');
    });

    test('add/remove/clear operations', () {
      final pipeline = MiddlewarePipeline();
      final m1 = _PassthroughMiddleware();
      final m2 = _PassthroughMiddleware();

      pipeline.add(m1);
      pipeline.add(m2);
      expect(pipeline.middlewares.length, 2);

      pipeline.remove(m1);
      expect(pipeline.middlewares.length, 1);
      expect(pipeline.middlewares.first, same(m2));

      pipeline.clear();
      expect(pipeline.middlewares, isEmpty);
    });

    test('addAll adds multiple middlewares', () {
      final pipeline = MiddlewarePipeline();
      final m1 = _PassthroughMiddleware();
      final m2 = _PassthroughMiddleware();

      pipeline.addAll([m1, m2]);
      expect(pipeline.middlewares.length, 2);
    });

    test('removeWhere removes matching middlewares', () {
      final pipeline = MiddlewarePipeline();
      pipeline.add(_PassthroughMiddleware());
      pipeline.add(_MaxTokensMiddleware(100));
      pipeline.add(_PassthroughMiddleware());

      pipeline.removeWhere((m) => m is _PassthroughMiddleware);
      expect(pipeline.middlewares.length, 1);
      expect(pipeline.middlewares.first, isA<_MaxTokensMiddleware>());
    });

    test('middleware list is unmodifiable', () {
      final pipeline = MiddlewarePipeline();
      pipeline.add(_PassthroughMiddleware());

      expect(
        () => pipeline.middlewares.add(_PassthroughMiddleware()),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('middleware can handle errors from next', () async {
      final pipeline = MiddlewarePipeline();
      pipeline.add(_ErrorHandlingMiddleware());

      final handler = pipeline.wrapGenerate((_) async {
        throw Exception('API error');
      });

      // The error-handling middleware catches and returns a fallback
      final result = await handler(_testRequest());
      expect(result.text, 'Error: Exception: API error');
    });
  });
}

// ── Test Helpers ──────────────────────────────────────────────────────

AIRequest _testRequest({String model = 'test-model'}) {
  return AIRequest(messages: [AIMessage.user('test prompt')], model: model);
}

AIResponse _testResponse({String text = 'response'}) {
  return AIResponse(
    text: text,
    model: 'test-model',
    usage: null,
    finishReason: 'stop',
    raw: const {},
  );
}

AIStreamChunk _testChunk(String text, {bool done = false}) {
  return AIStreamChunk(textDelta: text, isDone: done);
}

// ── Test Middlewares ──────────────────────────────────────────────────

class _PassthroughMiddleware extends AIMiddleware {}

class _MaxTokensMiddleware extends AIMiddleware {
  final int maxTokens;
  _MaxTokensMiddleware(this.maxTokens);

  @override
  Future<AIResponse> onGenerate(AIRequest request, GenerateNext next) {
    return next(request.copyWith(maxTokens: maxTokens));
  }
}

class _ResponseTagMiddleware extends AIMiddleware {
  final String tag;
  _ResponseTagMiddleware(this.tag);

  @override
  Future<AIResponse> onGenerate(AIRequest request, GenerateNext next) async {
    final response = await next(request);
    return AIResponse(
      text: '$tag ${response.text}',
      model: response.model,
      usage: response.usage,
      finishReason: response.finishReason,
      raw: response.raw,
    );
  }
}

class _LoggingMiddleware extends AIMiddleware {
  final String name;
  final List<String> log;
  _LoggingMiddleware(this.name, this.log);

  @override
  Future<AIResponse> onGenerate(AIRequest request, GenerateNext next) async {
    log.add('$name:before');
    final response = await next(request);
    log.add('$name:after');
    return response;
  }
}

class _CachingMiddleware extends AIMiddleware {
  final AIResponse cachedResponse;
  _CachingMiddleware(this.cachedResponse);

  @override
  Future<AIResponse> onGenerate(AIRequest request, GenerateNext next) async {
    return cachedResponse;
  }
}

class _UpperCaseStreamMiddleware extends AIMiddleware {
  @override
  Stream<AIStreamChunk> onStream(AIRequest request, StreamNext next) {
    return next(request).map(
      (chunk) => AIStreamChunk(
        textDelta: chunk.textDelta.toUpperCase(),
        isDone: chunk.isDone,
      ),
    );
  }
}

class _ErrorHandlingMiddleware extends AIMiddleware {
  @override
  Future<AIResponse> onGenerate(AIRequest request, GenerateNext next) async {
    try {
      return await next(request);
    } catch (e) {
      return AIResponse(
        text: 'Error: $e',
        model: request.model,
        usage: null,
        finishReason: 'error',
        raw: const {},
      );
    }
  }
}
