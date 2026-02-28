import 'dart:typed_data';

/// The type of content within an AI message block.
enum AIContentType {
  text,
  imageUrl,
  imageBytes,
  audioBytes,
  videoUrl,
  videoBytes,
}

/// Sealed content data hierarchy for exhaustive pattern matching.
sealed class AIContentData {
  const AIContentData();

  /// The content type derived from the concrete subclass.
  AIContentType get type;
}

/// Plain text content.
final class TextContent extends AIContentData {
  final String text;

  const TextContent(this.text);

  @override
  AIContentType get type => AIContentType.text;
}

/// Image referenced by URL.
final class ImageUrlContent extends AIContentData {
  final String url;
  final String? detail;

  const ImageUrlContent(this.url, {this.detail});

  @override
  AIContentType get type => AIContentType.imageUrl;
}

/// Image as raw bytes for inline/base64 usage.
final class ImageBytesContent extends AIContentData {
  final Uint8List bytes;
  final String mimeType;

  const ImageBytesContent(this.bytes, {required this.mimeType});

  @override
  AIContentType get type => AIContentType.imageBytes;
}

/// Audio as raw bytes for inline/base64 usage.
final class AudioBytesContent extends AIContentData {
  final Uint8List bytes;
  final String mimeType;

  const AudioBytesContent(this.bytes, {required this.mimeType});

  @override
  AIContentType get type => AIContentType.audioBytes;
}

/// Video referenced by URL.
final class VideoUrlContent extends AIContentData {
  final String url;

  const VideoUrlContent(this.url);

  @override
  AIContentType get type => AIContentType.videoUrl;
}

/// Video as raw bytes for inline/base64 usage.
final class VideoBytesContent extends AIContentData {
  final Uint8List bytes;
  final String mimeType;

  const VideoBytesContent(this.bytes, {required this.mimeType});

  @override
  AIContentType get type => AIContentType.videoBytes;
}

/// A single content block within an AI message.
class AIContentBlock {
  final AIContentData data;

  const AIContentBlock(this.data);

  /// The content type derived from the data variant.
  AIContentType get type => data.type;

  /// Create a text content block.
  factory AIContentBlock.text(String text) => AIContentBlock(TextContent(text));

  /// Create an image URL content block.
  factory AIContentBlock.imageUrl(String url, {String? detail}) =>
      AIContentBlock(ImageUrlContent(url, detail: detail));

  /// Create an image bytes content block.
  factory AIContentBlock.imageBytes(
    Uint8List bytes, {
    required String mimeType,
  }) => AIContentBlock(ImageBytesContent(bytes, mimeType: mimeType));

  /// Create an audio bytes content block.
  factory AIContentBlock.audioBytes(
    Uint8List bytes, {
    required String mimeType,
  }) => AIContentBlock(AudioBytesContent(bytes, mimeType: mimeType));

  /// Create a video URL content block.
  factory AIContentBlock.videoUrl(String url) =>
      AIContentBlock(VideoUrlContent(url));

  /// Create a video bytes content block.
  factory AIContentBlock.videoBytes(
    Uint8List bytes, {
    required String mimeType,
  }) => AIContentBlock(VideoBytesContent(bytes, mimeType: mimeType));
}
