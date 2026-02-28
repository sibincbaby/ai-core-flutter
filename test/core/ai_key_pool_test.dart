import 'package:ai_core/ai_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIKeyEntry', () {
    test('stores key and label', () {
      const entry = AIKeyEntry('sk-abc', label: 'premium');
      expect(entry.key, 'sk-abc');
      expect(entry.label, 'premium');
    });
  });

  group('AIKeyUsage', () {
    test('starts at zero', () {
      final usage = AIKeyUsage(label: 'free');
      expect(usage.label, 'free');
      expect(usage.callCount, 0);
      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 0);
      expect(usage.totalTokens, 0);
    });

    test('totalTokens sums input and output', () {
      final usage = AIKeyUsage(label: 'test');
      usage.inputTokens = 100;
      usage.outputTokens = 50;
      expect(usage.totalTokens, 150);
    });

    test('toString shows readable summary', () {
      final usage = AIKeyUsage(label: 'prod');
      usage.callCount = 3;
      usage.inputTokens = 200;
      usage.outputTokens = 100;
      expect(
        usage.toString(),
        'AIKeyUsage(prod: 3 calls, 200 in + 100 out = 300 tokens)',
      );
    });
  });

  group('AIKeyPool', () {
    late AIKeyPool pool;

    setUp(() {
      pool = AIKeyPool(
        entries: [
          const AIKeyEntry('sk-free', label: 'free'),
          const AIKeyEntry('sk-premium', label: 'premium'),
          const AIKeyEntry('sk-test', label: 'test'),
        ],
        defaultLabel: 'free',
      );
    });

    group('construction', () {
      test('uses first entry as default when defaultLabel omitted', () {
        final p = AIKeyPool(
          entries: [
            const AIKeyEntry('sk-a', label: 'a'),
            const AIKeyEntry('sk-b', label: 'b'),
          ],
        );
        expect(p.defaultLabel, 'a');
        expect(p.resolve(), 'sk-a');
      });

      test('uses explicit defaultLabel when provided', () {
        expect(pool.defaultLabel, 'free');
        expect(pool.resolve(), 'sk-free');
      });

      test('reports correct length and labels', () {
        expect(pool.length, 3);
        expect(pool.labels, containsAll(['free', 'premium', 'test']));
      });
    });

    group('resolve', () {
      test('returns default key when no label given', () {
        expect(pool.resolve(), 'sk-free');
      });

      test('returns correct key for existing label', () {
        expect(pool.resolve(label: 'premium'), 'sk-premium');
        expect(pool.resolve(label: 'test'), 'sk-test');
        expect(pool.resolve(label: 'free'), 'sk-free');
      });

      test('falls back to default for unknown label', () {
        expect(pool.resolve(label: 'nonexistent'), 'sk-free');
      });
    });

    group('defaultLabel setter', () {
      test('changes the default key', () {
        pool.defaultLabel = 'premium';
        expect(pool.defaultLabel, 'premium');
        expect(pool.resolve(), 'sk-premium');
      });

      test('throws ArgumentError for unknown label', () {
        expect(() => pool.defaultLabel = 'nonexistent', throwsArgumentError);
      });
    });

    group('usage tracking', () {
      test('records call count and tokens', () {
        pool.recordUsage('free', inputTokens: 100, outputTokens: 50);
        final usage = pool.usageFor('free')!;
        expect(usage.callCount, 1);
        expect(usage.inputTokens, 100);
        expect(usage.outputTokens, 50);
        expect(usage.totalTokens, 150);
      });

      test('accumulates across multiple calls', () {
        pool.recordUsage('premium', inputTokens: 200, outputTokens: 100);
        pool.recordUsage('premium', inputTokens: 300, outputTokens: 200);
        pool.recordUsage('premium', inputTokens: 50, outputTokens: 25);

        final usage = pool.usageFor('premium')!;
        expect(usage.callCount, 3);
        expect(usage.inputTokens, 550);
        expect(usage.outputTokens, 325);
        expect(usage.totalTokens, 875);
      });

      test('tracks keys independently', () {
        pool.recordUsage('free', inputTokens: 100, outputTokens: 50);
        pool.recordUsage('premium', inputTokens: 500, outputTokens: 200);

        expect(pool.usageFor('free')!.callCount, 1);
        expect(pool.usageFor('free')!.totalTokens, 150);
        expect(pool.usageFor('premium')!.callCount, 1);
        expect(pool.usageFor('premium')!.totalTokens, 700);
        expect(pool.usageFor('test')!.callCount, 0);
      });

      test('ignores unknown label silently', () {
        pool.recordUsage('nonexistent', inputTokens: 100, outputTokens: 50);
        // No exception, no effect
        expect(pool.usageFor('nonexistent'), isNull);
      });

      test('usage map is unmodifiable', () {
        final usageMap = pool.usage;
        expect(
          () => (usageMap as Map)['new'] = AIKeyUsage(label: 'new'),
          throwsUnsupportedError,
        );
      });
    });

    group('resetUsage', () {
      test('clears all counters', () {
        pool.recordUsage('free', inputTokens: 100, outputTokens: 50);
        pool.recordUsage('premium', inputTokens: 200, outputTokens: 100);
        pool.resetUsage();

        for (final label in pool.labels) {
          final u = pool.usageFor(label)!;
          expect(u.callCount, 0);
          expect(u.inputTokens, 0);
          expect(u.outputTokens, 0);
        }
      });
    });
  });

  group('AIKeyPool integration with AIProviderConfig', () {
    test('config accepts optional keyPool', () {
      final pool = AIKeyPool(
        entries: [
          const AIKeyEntry('sk-default', label: 'default'),
          const AIKeyEntry('sk-backup', label: 'backup'),
        ],
      );
      final config = AIProviderConfig(
        id: 'test',
        providerType: AIProviderType.openAI,
        apiKey: 'sk-default',
        keyPool: pool,
      );
      expect(config.keyPool, isNotNull);
      expect(config.keyPool!.resolve(), 'sk-default');
      expect(config.keyPool!.resolve(label: 'backup'), 'sk-backup');
    });

    test('config without keyPool has null pool', () {
      const config = AIProviderConfig(
        id: 'test',
        providerType: AIProviderType.openAI,
        apiKey: 'sk-test',
      );
      expect(config.keyPool, isNull);
    });
  });

  group('AIRequest keyTag', () {
    test('request carries keyTag', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'gpt-4o',
        keyTag: 'premium',
      );
      expect(request.keyTag, 'premium');
    });

    test('keyTag defaults to null', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'gpt-4o',
      );
      expect(request.keyTag, isNull);
    });

    test('copyWith preserves keyTag', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'gpt-4o',
        keyTag: 'free',
      );
      final copy = request.copyWith(model: 'gpt-5');
      expect(copy.keyTag, 'free');
      expect(copy.model, 'gpt-5');
    });

    test('copyWith overrides keyTag', () {
      final request = AIRequest(
        messages: [AIMessage.user('Hello')],
        model: 'gpt-4o',
        keyTag: 'free',
      );
      final copy = request.copyWith(keyTag: 'premium');
      expect(copy.keyTag, 'premium');
    });
  });
}
