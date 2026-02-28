import 'dart:typed_data';

import 'package:ai_core/models/ai_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIContentBlock', () {
    test('text factory creates TextContent', () {
      final block = AIContentBlock.text('Hello');
      expect(block.type, AIContentType.text);
      expect(block.data, isA<TextContent>());
      expect((block.data as TextContent).text, 'Hello');
    });

    test('imageUrl factory creates ImageUrlContent', () {
      final block = AIContentBlock.imageUrl(
        'https://example.com/image.png',
        detail: 'high',
      );
      expect(block.type, AIContentType.imageUrl);
      expect(block.data, isA<ImageUrlContent>());
      final data = block.data as ImageUrlContent;
      expect(data.url, 'https://example.com/image.png');
      expect(data.detail, 'high');
    });

    test('imageBytes factory creates ImageBytesContent', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final block = AIContentBlock.imageBytes(bytes, mimeType: 'image/png');
      expect(block.type, AIContentType.imageBytes);
      expect(block.data, isA<ImageBytesContent>());
      final data = block.data as ImageBytesContent;
      expect(data.bytes, bytes);
      expect(data.mimeType, 'image/png');
    });

    test('audioBytes factory creates AudioBytesContent', () {
      final bytes = Uint8List.fromList([4, 5, 6]);
      final block = AIContentBlock.audioBytes(bytes, mimeType: 'audio/wav');
      expect(block.type, AIContentType.audioBytes);
      expect(block.data, isA<AudioBytesContent>());
      final data = block.data as AudioBytesContent;
      expect(data.bytes, bytes);
      expect(data.mimeType, 'audio/wav');
    });
  });

  group('AIContentData sealed class', () {
    test('exhaustive switch covers all types', () {
      final contents = <AIContentData>[
        const TextContent('hi'),
        const ImageUrlContent('https://example.com/img.jpg'),
        ImageBytesContent(Uint8List(0), mimeType: 'image/png'),
        AudioBytesContent(Uint8List(0), mimeType: 'audio/mp3'),
        const VideoUrlContent('https://example.com/vid.mp4'),
        VideoBytesContent(Uint8List(0), mimeType: 'video/mp4'),
      ];

      final types = <AIContentType>[];
      for (final data in contents) {
        switch (data) {
          case TextContent():
            types.add(AIContentType.text);
          case ImageUrlContent():
            types.add(AIContentType.imageUrl);
          case ImageBytesContent():
            types.add(AIContentType.imageBytes);
          case AudioBytesContent():
            types.add(AIContentType.audioBytes);
          case VideoUrlContent():
            types.add(AIContentType.videoUrl);
          case VideoBytesContent():
            types.add(AIContentType.videoBytes);
        }
      }

      expect(types, [
        AIContentType.text,
        AIContentType.imageUrl,
        AIContentType.imageBytes,
        AIContentType.audioBytes,
        AIContentType.videoUrl,
        AIContentType.videoBytes,
      ]);
    });
  });
}
