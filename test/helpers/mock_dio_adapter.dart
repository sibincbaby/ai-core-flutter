import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A mock HTTP adapter for Dio that returns predetermined responses.
class MockDioAdapter implements HttpClientAdapter {
  final List<MockResponse> _responses = [];
  final List<RequestOptions> capturedRequests = [];

  void enqueue(MockResponse response) => _responses.add(response);

  void enqueueMany(List<MockResponse> responses) =>
      _responses.addAll(responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests.add(options);

    if (_responses.isEmpty) {
      throw DioException(
        requestOptions: options,
        message: 'No mock response enqueued',
        type: DioExceptionType.unknown,
      );
    }

    final mock = _responses.removeAt(0);

    if (mock.statusCode >= 400) {
      throw DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: mock.statusCode,
          data: mock.body,
        ),
        type: DioExceptionType.badResponse,
      );
    }

    if (mock.isStream) {
      return ResponseBody(
        mock.streamBody!,
        mock.statusCode,
        headers: {
          'content-type': ['text/event-stream'],
          ...mock.headers,
        },
      );
    }

    // Return ResponseBody with proper content-type for JSON decoding.
    final jsonString = jsonEncode(mock.body ?? {});
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonString));
    return ResponseBody(
      Stream.value(jsonBytes),
      mock.statusCode,
      headers: {
        'content-type': ['application/json; charset=utf-8'],
        ...mock.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MockResponse {
  final int statusCode;
  final Map<String, dynamic>? body;
  final Stream<Uint8List>? streamBody;
  final Map<String, List<String>> headers;
  final bool isStream;

  MockResponse({
    this.statusCode = 200,
    this.body,
    this.streamBody,
    this.headers = const {},
    this.isStream = false,
  });

  /// Create a mock SSE stream response from a list of SSE data strings.
  factory MockResponse.sse(List<String> events) {
    final sseData = events.map((e) => 'data: $e\n\n').join();
    final bytes = utf8.encode(sseData);
    return MockResponse(
      statusCode: 200,
      streamBody: Stream.value(Uint8List.fromList(bytes)),
      isStream: true,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );
  }
}
