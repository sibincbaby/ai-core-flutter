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

  /// OpenAI detail level (`'auto'`, `'high'`, `'low'`).
  final String? detail;

  /// Explicit MIME type (e.g. `'image/png'`). Used by Gemini; OpenAI infers
  /// the type from the URL.
  final String? mimeType;

  const ImageUrlContent(this.url, {this.detail, this.mimeType});

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

  /// Explicit MIME type (e.g. `'video/mp4'`). Used by Gemini; OpenAI infers
  /// the type from the URL.
  final String? mimeType;

  const VideoUrlContent(this.url, {this.mimeType});

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
  ///
  /// [detail] is used by OpenAI (`'auto'`, `'high'`, `'low'`).
  /// [mimeType] is used by Gemini (e.g. `'image/png'`); if omitted,
  /// the adapter falls back to `'image/jpeg'`.
  factory AIContentBlock.imageUrl(
    String url, {
    String? detail,
    String? mimeType,
  }) => AIContentBlock(ImageUrlContent(url, detail: detail, mimeType: mimeType));

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
  ///
  /// [mimeType] is used by Gemini (e.g. `'video/mp4'`); if omitted,
  /// the adapter falls back to `'video/mp4'`.
  factory AIContentBlock.videoUrl(String url, {String? mimeType}) =>
      AIContentBlock(VideoUrlContent(url, mimeType: mimeType));

  /// Create a video bytes content block.
  factory AIContentBlock.videoBytes(
    Uint8List bytes, {
    required String mimeType,
  }) => AIContentBlock(VideoBytesContent(bytes, mimeType: mimeType));
}
