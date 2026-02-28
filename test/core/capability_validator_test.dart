import 'dart:typed_data';

import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CapabilityValidator', () {
    const validator = CapabilityValidator();

    final textOnlyModel = AIModel(
      id: 'text-model',
      providerId: 'test',
      displayName: 'Text Only',
      capabilities: const AIModelCapabilities(
        supportsImageInput: false,
        supportsAudioInput: false,
      ),
    );

    final imageModel = AIModel(
      id: 'image-model',
      providerId: 'test',
      displayName: 'Image Model',
      capabilities: const AIModelCapabilities(
        supportsImageInput: true,
        supportsAudioInput: false,
      ),
    );

    final fullModel = AIModel(
      id: 'full-model',
      providerId: 'test',
      displayName: 'Full Model',
      capabilities: const AIModelCapabilities(
        supportsImageInput: true,
        supportsAudioInput: true,
      ),
    );

    final noStreamModel = AIModel(
      id: 'no-stream',
      providerId: 'test',
      displayName: 'No Stream',
      capabilities: const AIModelCapabilities(
        supportsStreaming: false,
      ),
    );

    test('text-only request passes for text-capable model', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'text-model',
      );

      expect(
        () => validator.validate(request, textOnlyModel),
        returnsNormally,
      );
    });

    test('image request throws for text-only model', () {
      final request = AIRequest(
        messages: [
          AIMessage(role: AIRole.user, content: [
            AIContentBlock.text('Describe this image'),
            AIContentBlock.imageUrl('https://example.com/img.png'),
          ]),
        ],
        model: 'text-model',
      );

      expect(
        () => validator.validate(request, textOnlyModel),
        throwsA(isA<AIUnsupportedInputException>().having(
          (e) => e.unsupportedTypes,
          'unsupportedTypes',
          contains('image'),
        )),
      );
    });

    test('image request passes for image-capable model', () {
      final request = AIRequest(
        messages: [
          AIMessage(role: AIRole.user, content: [
            AIContentBlock.text('Describe this'),
            AIContentBlock.imageUrl('https://example.com/img.png'),
          ]),
        ],
        model: 'image-model',
      );

      expect(
        () => validator.validate(request, imageModel),
        returnsNormally,
      );
    });

    test('audio request throws for image-only model', () {
      final request = AIRequest(
        messages: [
          AIMessage(role: AIRole.user, content: [
            AIContentBlock.audioBytes(
              Uint8List.fromList([1, 2, 3]),
              mimeType: 'audio/wav',
            ),
          ]),
        ],
        model: 'image-model',
      );

      expect(
        () => validator.validate(request, imageModel),
        throwsA(isA<AIUnsupportedInputException>().having(
          (e) => e.unsupportedTypes,
          'unsupportedTypes',
          contains('audio'),
        )),
      );
    });

    test('all content types pass for full model', () {
      final request = AIRequest(
        messages: [
          AIMessage(role: AIRole.user, content: [
            AIContentBlock.text('Describe'),
            AIContentBlock.imageBytes(
              Uint8List.fromList([1, 2]),
              mimeType: 'image/png',
            ),
            AIContentBlock.audioBytes(
              Uint8List.fromList([3, 4]),
              mimeType: 'audio/wav',
            ),
          ]),
        ],
        model: 'full-model',
      );

      expect(
        () => validator.validate(request, fullModel),
        returnsNormally,
      );
    });

    test('streaming request throws for non-streaming model', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'no-stream',
        stream: true,
      );

      expect(
        () => validator.validate(request, noStreamModel),
        throwsA(isA<AIUnsupportedInputException>().having(
          (e) => e.unsupportedTypes,
          'unsupportedTypes',
          contains('streaming'),
        )),
      );
    });

    test('multiple unsupported types are all reported', () {
      final request = AIRequest(
        messages: [
          AIMessage(role: AIRole.user, content: [
            AIContentBlock.imageUrl('https://example.com/img.png'),
            AIContentBlock.audioBytes(
              Uint8List.fromList([1]),
              mimeType: 'audio/wav',
            ),
          ]),
        ],
        model: 'text-model',
        stream: true,
      );

      try {
        validator.validate(request, AIModel(
          id: 'limited',
          providerId: 'test',
          displayName: 'Limited',
          capabilities: const AIModelCapabilities(
            supportsImageInput: false,
            supportsAudioInput: false,
            supportsStreaming: false,
          ),
        ));
        fail('Should have thrown');
      } on AIUnsupportedInputException catch (e) {
        expect(e.unsupportedTypes, containsAll(['image', 'audio', 'streaming']));
      }
    });
  });
}
