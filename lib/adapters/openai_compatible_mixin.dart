import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../errors/ai_exception.dart';
import '../models/ai_content.dart';
import '../models/ai_message.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../models/ai_response_format.dart';
import '../models/ai_stream_chunk.dart';
import '../models/ai_tool.dart';

/// Shared logic for OpenAI-compatible API adapters (OpenAI, OpenRouter).
///
/// Provides request building, response parsing, SSE streaming, and
/// error handling for the OpenAI Chat Completions API format.
mixin OpenAICompatibleMixin {
  /// The provider ID for error reporting.
  String get providerId;

  // ── Request Building ──────────────────────────────────────────────

  /// Converts an [AIRequest] to the OpenAI API request body.
  Map<String, dynamic> buildOpenAIRequestBody(
    AIRequest request, {
    bool? streamOverride,
  }) {
    final body = <String, dynamic>{
      'model': request.model,
      'messages': request.messages.map(_convertMessage).toList(),
    };

    if (request.temperature != null) body['temperature'] = request.temperature;
    if (request.maxTokens != null) body['max_tokens'] = request.maxTokens;
    final shouldStream = streamOverride ?? request.stream;
    if (shouldStream) body['stream'] = true;
    if (request.stopSequences != null && request.stopSequences!.isNotEmpty) {
      body['stop'] = request.stopSequences;
    }

    // Tool definitions.
    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = request.tools!.map(_convertTool).toList();
    }
    if (request.toolChoice != null) {
      body['tool_choice'] = request.toolChoice!.value;
    }

    // Response format.
    if (request.responseFormat != null) {
      body['response_format'] = _convertResponseFormat(request.responseFormat!);
    }

    if (request.extra != null) body.addAll(request.extra!);

    return body;
  }

  Map<String, dynamic> _convertMessage(AIMessage message) {
    final role = switch (message.role) {
      AIRole.system => 'system',
      AIRole.user => 'user',
      AIRole.assistant => 'assistant',
      AIRole.tool => 'tool',
    };

    // Tool result message.
    if (message.role == AIRole.tool) {
      return {
        'role': 'tool',
        'tool_call_id': message.toolCallId ?? '',
        'content':
            message.content.isNotEmpty &&
                message.content.first.data is TextContent
            ? (message.content.first.data as TextContent).text
            : '',
      };
    }

    // Assistant message with tool calls.
    if (message.role == AIRole.assistant &&
        message.toolCalls != null &&
        message.toolCalls!.isNotEmpty) {
      final msg = <String, dynamic>{
        'role': role,
        'tool_calls': message.toolCalls!
            .map(
              (tc) => {
                'id': tc.id,
                'type': tc.type,
                'function': {
                  'name': tc.functionName,
                  'arguments': tc.arguments,
                },
              },
            )
            .toList(),
      };
      // Include content if present.
      if (message.content.isNotEmpty) {
        if (message.content.length == 1 &&
            message.content.first.data is TextContent) {
          msg['content'] = (message.content.first.data as TextContent).text;
        } else {
          msg['content'] = message.content.map(_convertContentBlock).toList();
        }
      }
      return msg;
    }

    // Optimization: text-only messages use the string shorthand.
    if (message.content.length == 1 &&
        message.content.first.data is TextContent) {
      return {
        'role': role,
        'content': (message.content.first.data as TextContent).text,
      };
    }

    // Multimodal: use the array content format.
    final contentParts = message.content.map(_convertContentBlock).toList();
    return {'role': role, 'content': contentParts};
  }

  Map<String, dynamic> _convertContentBlock(AIContentBlock block) {
    return switch (block.data) {
      TextContent(text: final text) => {'type': 'text', 'text': text},
      ImageUrlContent(url: final url, detail: final detail) => {
        'type': 'image_url',
        'image_url': {'url': url, if (detail != null) 'detail': detail},
      },
      ImageBytesContent(bytes: final bytes, mimeType: final mime) => {
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
      },
      AudioBytesContent(bytes: final bytes, mimeType: final mime) => {
        'type': 'input_audio',
        'input_audio': {
          'data': base64Encode(bytes),
          'format': _audioFormat(mime),
        },
      },
      // Video: encode as image_url with data URI (OpenAI does not have
      // a dedicated video part type yet — Gemini handles video natively).
      VideoUrlContent(url: final url) => {
        'type': 'image_url',
        'image_url': {'url': url},
      },
      VideoBytesContent(bytes: final bytes, mimeType: final mime) => {
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
      },
    };
  }

  /// Converts an [AIResponseFormat] to the OpenAI API format.
  Map<String, dynamic> _convertResponseFormat(AIResponseFormat format) {
    if (format.type == 'json_schema' && format.jsonSchema != null) {
      final schema = <String, dynamic>{
        'name': format.jsonSchema!.name,
        'schema': format.jsonSchema!.schema,
        'strict': format.jsonSchema!.strict,
      };
      if (format.jsonSchema!.description != null) {
        schema['description'] = format.jsonSchema!.description;
      }
      return {'type': 'json_schema', 'json_schema': schema};
    }
    return {'type': format.type};
  }

  /// Converts an [AITool] to the OpenAI API format.
  Map<String, dynamic> _convertTool(AITool tool) {
    final funcDef = <String, dynamic>{
      'name': tool.function.name,
      'description': tool.function.description,
      'parameters': tool.function.parameters,
    };
    if (tool.function.strict != null) {
      funcDef['strict'] = tool.function.strict;
    }
    return {'type': tool.type, 'function': funcDef};
  }

  String _audioFormat(String mimeType) {
    final parts = mimeType.split('/');
    return parts.length > 1 ? parts[1] : mimeType;
  }

  // ── Response Parsing ──────────────────────────────────────────────

  /// Parses a non-streaming response body into [AIResponse].
  AIResponse parseOpenAIResponse(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>;
    if (choices.isEmpty) {
      throw AIException(
        type: AIErrorType.unknown,
        message: 'Provider returned empty choices array',
        providerId: providerId,
        rawError: json,
      );
    }

    final firstChoice = choices[0] as Map<String, dynamic>;
    final message = firstChoice['message'] as Map<String, dynamic>;
    final usageMap = json['usage'] as Map<String, dynamic>?;

    // Parse tool calls from response.
    final toolCallsList = <AIToolCall>[];
    final rawToolCalls = message['tool_calls'] as List<dynamic>?;
    if (rawToolCalls != null) {
      for (final tc in rawToolCalls) {
        final tcMap = tc as Map<String, dynamic>;
        final funcMap = tcMap['function'] as Map<String, dynamic>;
        toolCallsList.add(
          AIToolCall(
            id: tcMap['id'] as String,
            type: tcMap['type'] as String? ?? 'function',
            functionName: funcMap['name'] as String,
            arguments: funcMap['arguments'] as String,
          ),
        );
      }
    }

    return AIResponse(
      text: (message['content'] as String?) ?? '',
      model: json['model'] as String?,
      finishReason: firstChoice['finish_reason'] as String?,
      toolCalls: toolCallsList,
      usage: usageMap != null
          ? AIUsage(
              promptTokens: usageMap['prompt_tokens'] as int?,
              completionTokens: usageMap['completion_tokens'] as int?,
              totalTokens: usageMap['total_tokens'] as int?,
            )
          : null,
      raw: json,
    );
  }

  // ── Streaming ─────────────────────────────────────────────────────

  /// Parses an SSE byte stream into [AIStreamChunk]s.
  Stream<AIStreamChunk> parseOpenAIStream(Stream<Uint8List> byteStream) async* {
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

          if (data == '[DONE]') {
            yield AIStreamChunk.done();
            return;
          }

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final choice = choices[0] as Map<String, dynamic>;
            final delta = choice['delta'] as Map<String, dynamic>? ?? {};
            final finishReason = choice['finish_reason'] as String?;
            final content = delta['content'] as String? ?? '';

            // Parse tool call deltas.
            final rawToolCallDeltas = delta['tool_calls'] as List<dynamic>?;
            List<AIToolCallDelta>? toolCallDeltas;
            if (rawToolCallDeltas != null) {
              toolCallDeltas = rawToolCallDeltas.map((tc) {
                final tcMap = tc as Map<String, dynamic>;
                final funcMap = tcMap['function'] as Map<String, dynamic>?;
                return AIToolCallDelta(
                  index: tcMap['index'] as int,
                  id: tcMap['id'] as String?,
                  functionName: funcMap?['name'] as String?,
                  argumentsDelta: funcMap?['arguments'] as String?,
                );
              }).toList();
            }

            if (finishReason != null) {
              yield AIStreamChunk(
                textDelta: content,
                isDone: true,
                finishReason: finishReason,
                model: json['model'] as String?,
                toolCallDeltas: toolCallDeltas,
                raw: json,
              );
            } else if (content.isNotEmpty || toolCallDeltas != null) {
              yield AIStreamChunk(
                textDelta: content,
                model: json['model'] as String?,
                toolCallDeltas: toolCallDeltas,
                raw: json,
              );
            }
          } on FormatException {
            continue;
          }
        }
      }
    }
  }

  // ── Error Handling ────────────────────────────────────────────────

  /// Converts a [DioException] into an [AIException].
  AIException handleDioError(DioException e) {
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
    } else if (rawBody is String) {
      errorMessage = rawBody;
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
}
