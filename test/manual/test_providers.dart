// Manual provider test — run with:
//   flutter test test/manual/test_providers.dart
//
// Tests generate + stream for OpenAI, Gemini, and OpenRouter.
// Check console output for results.

import 'dart:io';

import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = _loadEnv();
  final openaiKey = env['OPENAI_API_KEY'] ?? '';
  final geminiKey = env['GEMINI_API_KEY'] ?? '';
  final openrouterKey = env['OPENROUTER_API_KEY'] ?? '';

  // ── OpenAI ────────────────────────────────────────────────────
  .('OpenAI', () {
    late AIClient client;

    setUp(() {
      if (openaiKey.isEmpty) return;
      client = AIClient();
      client.registry.register(OpenAIAdapter(
        config: AIProviderConfig(
          id: 'openai',
          providerType: AIProviderType.openAI,
          apiKey: openaiKey,
        ),
      ));
    });

    tearDown(() {
      if (openaiKey.isEmpty) return;
      client.dispose();
    });

    test('generate', skip: openaiKey.isEmpty ? 'no key' : null, () async {
      final resp = await client.generate(
        AIRequest(
          messages: [AIMessage.user('write about kerala in 200 words.')],
          model: 'gpt-4o-mini',
          maxTokens: 200,
        ),
        providerId: 'openai',
        validateCapabilities: false,
      );
      // ignore: avoid_print
      print('OpenAI generate response: "${resp.text}"');
      expect(resp.text, isNotEmpty);
    });

    test('stream', skip: openaiKey.isEmpty ? 'no key' : null, () async {
      final buffer = StringBuffer();
      var chunkCount = 0;
      await for (final chunk in client.stream(
        AIRequest(
          messages: [AIMessage.user('write about tamilnadu in 200 words.')],
          model: 'gpt-4o-mini',
          maxTokens: 300,
        ),
        providerId: 'openai',
        validateCapabilities: false,
      )) {
        buffer.write(chunk.textDelta);
        chunkCount++;
      }
      // ignore: avoid_print
      print('OpenAI stream ($chunkCount chunks): "$buffer"');
      expect(buffer.toString(), isNotEmpty);
      expect(chunkCount, greaterThan(0));
    });
  });

  // ── Gemini ────────────────────────────────────────────────────
  group('Gemini', () {
    late AIClient client;

    setUp(() {
      if (geminiKey.isEmpty) return;
      client = AIClient();
      client.registry.register(GeminiAdapter(
        config: AIProviderConfig(
          id: 'gemini',
          providerType: AIProviderType.gemini,
          apiKey: geminiKey,
        ),
      ));
    });

    tearDown(() {
      if (geminiKey.isEmpty) return;
      client.dispose();
    });

    test('generate', skip: geminiKey.isEmpty ? 'no key' : null, () async {
      final resp = await client.generate(
        AIRequest(
          messages: [AIMessage.user('Say "hello" and nothing else.')],
          model: 'gemini-2.0-flash',
          maxTokens: 20,
        ),
        providerId: 'gemini',
        validateCapabilities: false,
      );
      // ignore: avoid_print
      print('Gemini generate response: "${resp.text}"');
      expect(resp.text, isNotEmpty);
    });

    test('stream', skip: geminiKey.isEmpty ? 'no key' : null, () async {
      final buffer = StringBuffer();
      var chunkCount = 0;
      await for (final chunk in client.stream(
        AIRequest(
          messages: [AIMessage.user('Count from 1 to 3.')],
          model: 'gemini-2.0-flash',
          maxTokens: 30,
        ),
        providerId: 'gemini',
        validateCapabilities: false,
      )) {
        buffer.write(chunk.textDelta);
        chunkCount++;
      }
      // ignore: avoid_print
      print('Gemini stream ($chunkCount chunks): "$buffer"');
      expect(buffer.toString(), isNotEmpty);
      expect(chunkCount, greaterThan(0));
    });
  });

  // ── OpenRouter ────────────────────────────────────────────────
  group('OpenRouter', () {
    late AIClient client;

    setUp(() {
      if (openrouterKey.isEmpty) return;
      client = AIClient();
      client.registry.register(OpenRouterAdapter(
        config: AIProviderConfig(
          id: 'openrouter',
          providerType: AIProviderType.openRouter,
          apiKey: openrouterKey,
        ),
        appName: 'AI Core Test',
      ));
    });

    tearDown(() {
      if (openrouterKey.isEmpty) return;
      client.dispose();
    });

    test('generate', skip: openrouterKey.isEmpty ? 'no key' : null, () async {
      final resp = await client.generate(
        AIRequest(
          messages: [AIMessage.user('Say "hello" and nothing else.')],
          model: 'openai/gpt-4o-mini',
          maxTokens: 20,
        ),
        providerId: 'openrouter',
        validateCapabilities: false,
      );
      // ignore: avoid_print
      print('OpenRouter generate response: "${resp.text}"');
      expect(resp.text, isNotEmpty);
    });

    test('stream', skip: openrouterKey.isEmpty ? 'no key' : null, () async {
      final buffer = StringBuffer();
      var chunkCount = 0;
      await for (final chunk in client.stream(
        AIRequest(
          messages: [AIMessage.user('Count from 1 to 3.')],
          model: 'openai/gpt-4o-mini',
          maxTokens: 30,
        ),
        providerId: 'openrouter',
        validateCapabilities: false,
      )) {
        buffer.write(chunk.textDelta);
        chunkCount++;
      }
      // ignore: avoid_print
      print('OpenRouter stream ($chunkCount chunks): "$buffer"');
      expect(buffer.toString(), isNotEmpty);
      expect(chunkCount, greaterThan(0));
    });
  });
}

Map<String, String> _loadEnv() {
  final envFile = File('.env');
  if (!envFile.existsSync()) return {};
  final env = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx > 0) {
      env[trimmed.substring(0, idx)] = trimmed.substring(idx + 1);
    }
  }
  return env;
}
