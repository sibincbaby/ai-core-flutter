import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/ai_provider_adapter.dart';
import '../core/retry_interceptor.dart';
import '../errors/ai_exception.dart';
import '../models/ai_content.dart';
import '../models/ai_embedding.dart';
import '../models/ai_message.dart';
import '../models/ai_model.dart';
import '../models/ai_provider_config.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../models/ai_stream_chunk.dart';
import '../models/ai_tool.dart';

/// Google Gemini API adapter.
class GeminiAdapter implements AIProviderAdapter {
  @override
  final AIProviderConfig config;

  final Dio _dio;

  /// Optional retry configuration for automatic retry with backoff.
  final RetryConfig? retryConfig;

  /// Known Gemini models with their capabilities (fallback registry).
  static const Map<String, AIModelCapabilities> knownModels = {
    // ── Gemini 3 family (2025–2026) ──────────────────────────
    'gemini-3.1-pro-preview': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gemini-3-flash-preview': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),

    // ── Gemini 2.5 family ────────────────────────────────────
    'gemini-2.5-pro': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gemini-2.5-flash': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gemini-2.5-flash-lite': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),

    // ── Legacy / deprecated ──────────────────────────────────
    'gemini-2.0-flash': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gemini-2.0-flash-lite': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gemini-1.5-pro': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 2097152,
    ),
    'gemini-1.5-flash': AIModelCapabilities(
      supportsImageInput: true,
      supportsAudioInput: true,
      supportsVideoInput: true,
      supportsToolCalling: true,
      supportsJsonMode: true,
      maxContextWindow: 1048576,
    ),
    'gemini-1.0-pro': AIModelCapabilities(maxContextWindow: 32768),
  };

  GeminiAdapter({required this.config, Dio? dio, this.retryConfig})
    : _dio = dio ?? Dio() {
    _configureDio();
  }

  void _configureDio() {
    _dio.options.baseUrl = config.effectiveBaseUrl;
    _dio.options.headers = {
      'x-goog-api-key': config.apiKey,
      'Content-Type': 'application/json',
      ...?config.extraHeaders,
    };
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);

    if (retryConfig != null) {
      _dio.interceptors.add(RetryInterceptor(dio: _dio, config: retryConfig!));
    }
  }

  @override
  String get providerId => config.id;

  /// Resolves the API key header for a request.
  ///
  /// If a [AIKeyPool] is configured, selects the key matching [keyTag]
  /// (or the default key). Otherwise uses [config.apiKey].
  Options _resolveKeyOptions(String? keyTag, {ResponseType? responseType}) {
    final pool = config.keyPool;
    if (pool != null) {
      final key = pool.resolve(label: keyTag);
      return Options(
        headers: {'x-goog-api-key': key},
        responseType: responseType,
      );
    }
    if (responseType != null) {
      return Options(responseType: responseType);
    }
    return Options();
  }

  /// Records token usage against the key pool entry (if configured).
  void _recordKeyUsage(String? keyTag, AIResponse response) {
    final pool = config.keyPool;
    if (pool == null) return;
    final label = keyTag ?? pool.defaultLabel;
    pool.recordUsage(
      label,
      inputTokens: response.usage?.promptTokens ?? 0,
      outputTokens: response.usage?.completionTokens ?? 0,
    );
  }

  // ── Request Building ──────────────────────────────────────────────

  Map<String, dynamic> _buildRequestBody(AIRequest request) {
    final body = <String, dynamic>{};

    // Separate system messages from content messages.
    final systemMessages = <AIMessage>[];
    final contentMessages = <AIMessage>[];

    for (final msg in request.messages) {
      if (msg.role == AIRole.system) {
        systemMessages.add(msg);
      } else {
        contentMessages.add(msg);
      }
    }

    // System instruction (Gemini-specific placement).
    if (systemMessages.isNotEmpty) {
      final systemParts = <Map<String, dynamic>>[];
      for (final msg in systemMessages) {
        for (final block in msg.content) {
          if (block.data is TextContent) {
            systemParts.add({'text': (block.data as TextContent).text});
          }
        }
      }
      body['systemInstruction'] = {'parts': systemParts};
    }

    // Content messages.
    body['contents'] = contentMessages.map(_convertMessage).toList();

    // Generation config.
    final genConfig = <String, dynamic>{};
    if (request.temperature != null) {
      genConfig['temperature'] = request.temperature;
    }
    if (request.maxTokens != null) {
      genConfig['maxOutputTokens'] = request.maxTokens;
    }
    if (request.stopSequences != null && request.stopSequences!.isNotEmpty) {
      genConfig['stopSequences'] = request.stopSequences;
    }
    // Response format.
    if (request.responseFormat != null) {
      final fmt = request.responseFormat!;
      if (fmt.type == 'json_object') {
        genConfig['responseMimeType'] = 'application/json';
      } else if (fmt.type == 'json_schema' && fmt.jsonSchema != null) {
        genConfig['responseMimeType'] = 'application/json';
        genConfig['responseSchema'] = fmt.jsonSchema!.schema;
      }
    }
    if (genConfig.isNotEmpty) {
      body['generationConfig'] = genConfig;
    }

    // Tool definitions.
    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': request.tools!
              .map(
                (t) => {
                  'name': t.function.name,
                  'description': t.function.description,
                  'parameters': t.function.parameters,
                },
              )
              .toList(),
        },
      ];

      // Tool choice mapping.
      if (request.toolChoice != null) {
        final choice = request.toolChoice!.value;
        if (choice == 'auto') {
          body['toolConfig'] = {
            'functionCallingConfig': {'mode': 'AUTO'},
          };
        } else if (choice == 'none') {
          body['toolConfig'] = {
            'functionCallingConfig': {'mode': 'NONE'},
          };
        } else if (choice == 'required') {
          body['toolConfig'] = {
            'functionCallingConfig': {'mode': 'ANY'},
          };
        } else if (choice is Map<String, dynamic>) {
          final funcName =
              (choice['function'] as Map<String, dynamic>?)?['name'];
          if (funcName != null) {
            body['toolConfig'] = {
              'functionCallingConfig': {
                'mode': 'ANY',
                'allowedFunctionNames': [funcName],
              },
            };
          }
        }
      }
    }

    if (request.extra != null) body.addAll(request.extra!);

    return body;
  }

  Map<String, dynamic> _convertMessage(AIMessage message) {
    final role = switch (message.role) {
      AIRole.user => 'user',
      AIRole.assistant => 'model',
      AIRole.system => 'user', // Should not reach here; systems are extracted.
      AIRole.tool => 'user', // Gemini uses 'user' role for function responses.
    };

    // Tool result message → functionResponse part.
    if (message.role == AIRole.tool) {
      final resultText =
          message.content.isNotEmpty &&
              message.content.first.data is TextContent
          ? (message.content.first.data as TextContent).text
          : '';
      Map<String, dynamic> response;
      try {
        response = jsonDecode(resultText) as Map<String, dynamic>;
      } catch (_) {
        response = {'result': resultText};
      }
      return {
        'role': 'function',
        'parts': [
          {
            'functionResponse': {
              'name': message.toolCallId ?? '',
              'response': response,
            },
          },
        ],
      };
    }

    // Assistant message with tool calls → functionCall parts.
    if (message.role == AIRole.assistant &&
        message.toolCalls != null &&
        message.toolCalls!.isNotEmpty) {
      final parts = <Map<String, dynamic>>[];
      // Include text content if present.
      for (final block in message.content) {
        parts.add(_convertContentBlock(block));
      }
      // Add function call parts.
      for (final tc in message.toolCalls!) {
        Map<String, dynamic> args;
        try {
          args = jsonDecode(tc.arguments) as Map<String, dynamic>;
        } catch (_) {
          args = {};
        }
        parts.add({
          'functionCall': {'name': tc.functionName, 'args': args},
        });
      }
      return {'role': role, 'parts': parts};
    }

    final parts = message.content.map(_convertContentBlock).toList();
    return {'role': role, 'parts': parts};
  }

  Map<String, dynamic> _convertContentBlock(AIContentBlock block) {
    return switch (block.data) {
      TextContent(text: final text) => {'text': text},
      ImageUrlContent(url: final url, mimeType: final mime) => {
        'fileData': {
          'mimeType': mime ?? 'image/jpeg',
          'fileUri': url,
        },
      },
      ImageBytesContent(bytes: final bytes, mimeType: final mime) => {
        'inlineData': {'mimeType': mime, 'data': base64Encode(bytes)},
      },
      AudioBytesContent(bytes: final bytes, mimeType: final mime) => {
        'inlineData': {'mimeType': mime, 'data': base64Encode(bytes)},
      },
      VideoUrlContent(url: final url, mimeType: final mime) => {
        'fileData': {
          'mimeType': mime ?? 'video/mp4',
          'fileUri': url,
        },
      },
      VideoBytesContent(bytes: final bytes, mimeType: final mime) => {
        'inlineData': {'mimeType': mime, 'data': base64Encode(bytes)},
      },
    };
  }

  // ── Response Parsing ──────────────────────────────────────────────

  AIResponse _parseResponse(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      final promptFeedback = json['promptFeedback'] as Map<String, dynamic>?;
      if (promptFeedback != null) {
        final blockReason = promptFeedback['blockReason'] as String?;
        throw AIException(
          type: AIErrorType.unknown,
          message: 'Prompt blocked by Gemini safety filter: $blockReason',
          providerId: providerId,
          rawError: json,
        );
      }
      throw AIException(
        type: AIErrorType.unknown,
        message: 'Gemini returned empty candidates array',
        providerId: providerId,
        rawError: json,
      );
    }

    final candidate = candidates[0] as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? [];

    final textBuffer = StringBuffer();
    final toolCalls = <AIToolCall>[];
    for (final part in parts) {
      final partMap = part as Map<String, dynamic>;
      if (partMap.containsKey('text')) {
        textBuffer.write(partMap['text'] as String);
      }
      if (partMap.containsKey('functionCall')) {
        final fc = partMap['functionCall'] as Map<String, dynamic>;
        toolCalls.add(
          AIToolCall(
            id: fc['name'] as String, // Gemini uses function name as ID.
            functionName: fc['name'] as String,
            arguments: jsonEncode(fc['args'] ?? {}),
          ),
        );
      }
    }

    final usageMetadata = json['usageMetadata'] as Map<String, dynamic>?;
    final finishReason = candidate['finishReason'] as String?;
    final normalizedFinishReason = switch (finishReason) {
      'STOP' => 'stop',
      'MAX_TOKENS' => 'length',
      'SAFETY' => 'content_filter',
      'RECITATION' => 'content_filter',
      _ => finishReason?.toLowerCase(),
    };

    return AIResponse(
      text: textBuffer.toString(),
      model: null,
      finishReason: normalizedFinishReason,
      toolCalls: toolCalls,
      usage: usageMetadata != null
          ? AIUsage(
              promptTokens: usageMetadata['promptTokenCount'] as int?,
              completionTokens: usageMetadata['candidatesTokenCount'] as int?,
              totalTokens: usageMetadata['totalTokenCount'] as int?,
            )
          : null,
      raw: json,
    );
  }

  // ── Error Handling ────────────────────────────────────────────────

  AIException _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return AIException(
        type: AIErrorType.network,
        message: 'Network error: ${e.message}',
        providerId: providerId,
        cause: e,
      );
    }

    if (e.type == DioExceptionType.cancel) {
      return AIException(
        type: AIErrorType.cancelled,
        message: 'Request cancelled',
        providerId: providerId,
        cause: e,
      );
    }

    final statusCode = e.response?.statusCode;
    final rawBody = e.response?.data;
    Map<String, dynamic>? errorMap;
    var errorMessage = e.message ?? 'Unknown error';

    if (rawBody is Map<String, dynamic>) {
      errorMap = rawBody;
      final errorObj = rawBody['error'];
      if (errorObj is Map<String, dynamic>) {
        errorMessage = errorObj['message'] as String? ?? errorMessage;
      }
    }

    if (statusCode != null) {
      return AIException.fromHttpStatus(
        statusCode: statusCode,
        body: errorMessage,
        providerId: providerId,
        rawError: errorMap,
      );
    }

    return AIException(
      type: AIErrorType.unknown,
      message: errorMessage,
      providerId: providerId,
      cause: e,
      rawError: errorMap,
    );
  }

  // ── Public API ────────────────────────────────────────────────────

  @override
  Future<AIResponse> generate(AIRequest request) async {
    try {
      final body = _buildRequestBody(request);
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1beta/models/${request.model}:generateContent',
        data: body,
        options: _resolveKeyOptions(request.keyTag),
      );
      final aiResponse = _parseResponse(response.data!);
      _recordKeyUsage(request.keyTag, aiResponse);
      return aiResponse;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Stream<AIStreamChunk> stream(AIRequest request) async* {
    try {
      final body = _buildRequestBody(request);
      final response = await _dio.post<ResponseBody>(
        '/v1beta/models/${request.model}:streamGenerateContent',
        data: body,
        queryParameters: {'alt': 'sse'},
        options: _resolveKeyOptions(
          request.keyTag,
          responseType: ResponseType.stream,
        ),
      );

      final byteStream = response.data!.stream;
      var buffer = '';

      await for (final bytes in byteStream) {
        buffer += utf8.decode(bytes);

        while (buffer.contains('\n')) {
          final newlineIndex = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);

          if (line.isEmpty) continue;

          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data.isEmpty) continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final candidates = json['candidates'] as List<dynamic>?;
              if (candidates == null || candidates.isEmpty) continue;

              final candidate = candidates[0] as Map<String, dynamic>;
              final content = candidate['content'] as Map<String, dynamic>?;
              final parts = content?['parts'] as List<dynamic>? ?? [];
              final finishReason = candidate['finishReason'] as String?;

              final textBuffer = StringBuffer();
              final toolCallDeltas = <AIToolCallDelta>[];
              var toolCallIndex = 0;
              for (final part in parts) {
                final partMap = part as Map<String, dynamic>;
                if (partMap.containsKey('text')) {
                  textBuffer.write(partMap['text'] as String);
                }
                if (partMap.containsKey('functionCall')) {
                  final fc = partMap['functionCall'] as Map<String, dynamic>;
                  toolCallDeltas.add(
                    AIToolCallDelta(
                      index: toolCallIndex++,
                      id: fc['name'] as String?,
                      functionName: fc['name'] as String?,
                      argumentsDelta: jsonEncode(fc['args'] ?? {}),
                    ),
                  );
                }
              }

              final isDone = finishReason != null && finishReason == 'STOP';

              yield AIStreamChunk(
                textDelta: textBuffer.toString(),
                isDone: isDone,
                finishReason: isDone ? 'stop' : null,
                toolCallDeltas: toolCallDeltas.isNotEmpty
                    ? toolCallDeltas
                    : null,
                raw: json,
              );

              if (isDone) return;
            } on FormatException {
              continue;
            }
          }
        }
      }

      // Stream ended without explicit STOP.
      yield AIStreamChunk.done();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<AIEmbeddingResponse> embed(AIEmbeddingRequest request) async {
    try {
      // Gemini batch embedding: POST /v1beta/models/{model}:batchEmbedContents
      final requests = request.input.map((text) {
        final req = <String, dynamic>{
          'model': 'models/${request.model}',
          'content': {
            'parts': [
              {'text': text},
            ],
          },
        };
        if (request.dimensions != null) {
          req['outputDimensionality'] = request.dimensions;
        }
        return req;
      }).toList();

      final response = await _dio.post<Map<String, dynamic>>(
        '/v1beta/models/${request.model}:batchEmbedContents',
        data: {'requests': requests},
        options: _resolveKeyOptions(null),
      );

      final data = response.data!;
      final embeddingsList = data['embeddings'] as List<dynamic>;
      final embeddings = <AIEmbedding>[];

      for (var i = 0; i < embeddingsList.length; i++) {
        final item = embeddingsList[i] as Map<String, dynamic>;
        final values = (item['values'] as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList();
        embeddings.add(AIEmbedding(index: i, embedding: values));
      }

      return AIEmbeddingResponse(
        embeddings: embeddings,
        model: request.model,
        raw: data,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<List<AIModel>> fetchModels() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1beta/models');
      final models = response.data!['models'] as List<dynamic>;

      return models
          .where((m) {
            final name = (m as Map<String, dynamic>)['name'] as String;
            return name.contains('gemini');
          })
          .map((m) {
            final modelMap = m as Map<String, dynamic>;
            final fullName = modelMap['name'] as String;
            final id = fullName.replaceFirst('models/', '');
            final displayName = modelMap['displayName'] as String? ?? id;

            final capabilities = _resolveCapabilities(id);

            return AIModel(
              id: id,
              providerId: providerId,
              displayName: displayName,
              capabilities: capabilities,
              contextWindow: modelMap['inputTokenLimit'] as int?,
            );
          })
          .toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Resolves capabilities for a model ID using the known models registry.
  ///
  /// Lookup order:
  /// 1. Exact match in [knownModels].
  /// 2. Prefix match (longest prefix wins).
  /// 3. Family inference — unknown future models inherit sensible defaults
  ///    (e.g. `gemini-4-ultra` inherits modern Gemini family capabilities).
  /// 4. Bare minimum fallback: text + image.
  AIModelCapabilities _resolveCapabilities(String modelId) {
    if (knownModels.containsKey(modelId)) {
      return knownModels[modelId]!;
    }
    // Prefix match — longest key first for specificity.
    final sortedKeys = knownModels.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      if (modelId.startsWith(key)) {
        return knownModels[key]!;
      }
    }
    // Family inference: all modern Gemini models support multimodal + tools.
    if (modelId.startsWith('gemini-')) {
      return const AIModelCapabilities(
        supportsImageInput: true,
        supportsAudioInput: true,
        supportsVideoInput: true,
        supportsToolCalling: true,
        supportsJsonMode: true,
      );
    }
    return const AIModelCapabilities(supportsImageInput: true);
  }

  @override
  void dispose() {
    _dio.close();
  }
}
