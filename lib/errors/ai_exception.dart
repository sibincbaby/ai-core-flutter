/// Categorization of AI SDK errors.
enum AIErrorType {
  /// 401 / invalid API key.
  unauthorized,

  /// 429 / rate limit exceeded.
  rateLimited,

  /// Model does not exist or is not accessible.
  invalidModel,

  /// Request content type not supported by the model.
  unsupportedInput,

  /// Network connectivity or timeout error.
  network,

  /// Provider returned a server error (5xx).
  serverError,

  /// Request was cancelled.
  cancelled,

  /// Catch-all for unmapped errors.
  unknown,
}

/// Base exception for all AI SDK errors.
class AIException implements Exception {
  /// The error category.
  final AIErrorType type;

  /// Human-readable error message.
  final String message;

  /// The HTTP status code, if applicable.
  final int? statusCode;

  /// The provider that produced this error, if applicable.
  final String? providerId;

  /// The underlying cause, if any.
  final Object? cause;

  /// Raw error body from the provider.
  final Map<String, dynamic>? rawError;

  const AIException({
    required this.type,
    required this.message,
    this.statusCode,
    this.providerId,
    this.cause,
    this.rawError,
  });

  @override
  String toString() =>
      'AIException(${type.name}): $message'
      '${statusCode != null ? ' [HTTP $statusCode]' : ''}'
      '${providerId != null ? ' [provider: $providerId]' : ''}';

  /// Create from an HTTP status code and body.
  factory AIException.fromHttpStatus({
    required int statusCode,
    required String body,
    String? providerId,
    Map<String, dynamic>? rawError,
  }) {
    final type = switch (statusCode) {
      401 || 403 => AIErrorType.unauthorized,
      429 => AIErrorType.rateLimited,
      404 => AIErrorType.invalidModel,
      >= 500 && < 600 => AIErrorType.serverError,
      _ => AIErrorType.unknown,
    };
    return AIException(
      type: type,
      message: body,
      statusCode: statusCode,
      providerId: providerId,
      rawError: rawError,
    );
  }
}

/// Thrown when a request contains content types the target model does not support.
class AIUnsupportedInputException extends AIException {
  /// The content types that are not supported.
  final Set<String> unsupportedTypes;

  /// The model that was targeted.
  final String modelId;

  AIUnsupportedInputException({
    required this.unsupportedTypes,
    required this.modelId,
    super.providerId,
  }) : super(
          type: AIErrorType.unsupportedInput,
          message:
              'Model "$modelId" does not support input types: '
              '${unsupportedTypes.join(', ')}',
        );
}
