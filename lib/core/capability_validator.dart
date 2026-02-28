import '../errors/ai_exception.dart';
import '../models/ai_content.dart';
import '../models/ai_model.dart';
import '../models/ai_request.dart';

/// Validates that an [AIRequest] only contains content types
/// supported by the target model's capabilities.
class CapabilityValidator {
  const CapabilityValidator();

  /// Validates the request against the model capabilities.
  ///
  /// Throws [AIUnsupportedInputException] if any content block uses
  /// a type the model does not support.
  void validate(AIRequest request, AIModel model) {
    final unsupported = <String>{};
    final caps = model.capabilities;

    for (final message in request.messages) {
      for (final block in message.content) {
        switch (block.data) {
          case TextContent():
            if (!caps.supportsText) {
              unsupported.add('text');
            }
          case ImageUrlContent():
          case ImageBytesContent():
            if (!caps.supportsImageInput) {
              unsupported.add('image');
            }
          case AudioBytesContent():
            if (!caps.supportsAudioInput) {
              unsupported.add('audio');
            }
          case VideoUrlContent():
          case VideoBytesContent():
            if (!caps.supportsVideoInput) {
              unsupported.add('video');
            }
        }
      }
    }

    if (request.stream && !caps.supportsStreaming) {
      unsupported.add('streaming');
    }

    if (request.tools != null &&
        request.tools!.isNotEmpty &&
        !caps.supportsToolCalling) {
      unsupported.add('tool_calling');
    }

    if (request.responseFormat != null &&
        request.responseFormat!.type != 'text' &&
        !caps.supportsJsonMode) {
      unsupported.add('json_mode');
    }

    if (unsupported.isNotEmpty) {
      throw AIUnsupportedInputException(
        unsupportedTypes: unsupported,
        modelId: model.id,
        providerId: model.providerId,
      );
    }
  }
}
