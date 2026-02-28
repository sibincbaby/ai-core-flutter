import 'package:ai_core/models/ai_cost.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIModelPricing', () {
    test('stores input and output pricing', () {
      const p = AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0);
      expect(p.inputPerMillion, 2.0);
      expect(p.outputPerMillion, 8.0);
      expect(p.embeddingPerMillion, isNull);
      expect(p.cachedInputPerMillion, isNull);
    });

    test('stores optional embedding and cached pricing', () {
      const p = AIModelPricing(
        inputPerMillion: 1.0,
        outputPerMillion: 2.0,
        embeddingPerMillion: 0.5,
        cachedInputPerMillion: 0.3,
      );
      expect(p.embeddingPerMillion, 0.5);
      expect(p.cachedInputPerMillion, 0.3);
    });
  });

  group('AICostEstimate', () {
    test('toString formats correctly', () {
      const e = AICostEstimate(
        inputCost: 0.002,
        outputCost: 0.008,
        totalCost: 0.01,
        model: 'gpt-4.1',
        inputTokens: 1000,
        outputTokens: 1000,
        pricing: AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
      );
      final s = e.toString();
      expect(s, contains('0.01'));
      expect(s, contains('1000'));
    });
  });

  group('AICostCalculator', () {
    late AICostCalculator calculator;

    setUp(() {
      calculator = AICostCalculator();
    });

    test('has built-in pricing for known models', () {
      expect(calculator.knownModels, contains('gpt-4.1'));
      expect(calculator.knownModels, contains('gpt-4o'));
      expect(calculator.knownModels, contains('gemini-2.5-pro'));
      expect(calculator.knownModels, contains('gemini-2.0-flash'));
    });

    test('exact match returns correct pricing', () {
      final pricing = calculator.getPricing('gpt-4.1');
      expect(pricing, isNotNull);
      expect(pricing!.inputPerMillion, 2.0);
      expect(pricing.outputPerMillion, 8.0);
    });

    test('prefix match works for dated model IDs', () {
      final pricing = calculator.getPricing('gpt-4.1-2025-04-14');
      expect(pricing, isNotNull);
      expect(pricing!.inputPerMillion, 2.0);
    });

    test('longest prefix wins', () {
      // 'gpt-4.1-mini' should match 'gpt-4.1-mini' not 'gpt-4.1'
      final pricing = calculator.getPricing('gpt-4.1-mini');
      expect(pricing, isNotNull);
      expect(pricing!.inputPerMillion, 0.40);
    });

    test('unknown model returns null', () {
      expect(calculator.getPricing('unknown-model'), isNull);
    });

    test('family inference returns pricing for unknown gpt model', () {
      final pricing = calculator.getPricing('gpt-6-turbo');
      expect(pricing, isNotNull);
      // Should be median of known GPT family entries.
      expect(pricing!.inputPerMillion, greaterThan(0));
      expect(pricing.outputPerMillion, greaterThan(0));
    });

    test('family inference returns pricing for unknown gemini model', () {
      final pricing = calculator.getPricing('gemini-4-ultra');
      expect(pricing, isNotNull);
      expect(pricing!.inputPerMillion, greaterThan(0));
      expect(pricing.outputPerMillion, greaterThan(0));
    });

    test('family inference returns pricing for unknown o-series model', () {
      final pricing = calculator.getPricing('o5-pro');
      expect(pricing, isNotNull);
      expect(pricing!.inputPerMillion, greaterThan(0));
      expect(pricing.outputPerMillion, greaterThan(0));
    });

    test('family inference returns null for non-matching family', () {
      expect(calculator.getPricing('claude-4-opus'), isNull);
    });

    test('estimate calculates correct cost', () {
      final cost = calculator.estimate(
        model: 'gpt-4.1',
        inputTokens: 1000,
        outputTokens: 500,
      );
      expect(cost, isNotNull);
      // 1000 / 1M * 2.0 = 0.002
      expect(cost!.inputCost, closeTo(0.002, 1e-10));
      // 500 / 1M * 8.0 = 0.004
      expect(cost.outputCost, closeTo(0.004, 1e-10));
      expect(cost.totalCost, closeTo(0.006, 1e-10));
      expect(cost.model, 'gpt-4.1');
      expect(cost.inputTokens, 1000);
      expect(cost.outputTokens, 500);
    });

    test('estimate returns null for unknown model', () {
      final cost = calculator.estimate(
        model: 'unknown',
        inputTokens: 100,
        outputTokens: 50,
      );
      expect(cost, isNull);
    });

    test('estimateEmbedding calculates correctly', () {
      final cost = calculator.estimateEmbedding(
        model: 'text-embedding-3-small',
        tokens: 1000000,
      );
      expect(cost, isNotNull);
      expect(cost!.totalCost, closeTo(0.02, 1e-10));
      expect(cost.outputCost, 0);
    });

    test('estimateEmbedding returns null when no embedding pricing', () {
      // gpt-4.1 has no embeddingPerMillion
      final cost = calculator.estimateEmbedding(model: 'gpt-4.1', tokens: 1000);
      expect(cost, isNull);
    });

    test('custom pricing overrides built-in', () {
      final custom = AICostCalculator(
        customPricing: {
          'gpt-4.1': const AIModelPricing(
            inputPerMillion: 99.0,
            outputPerMillion: 99.0,
          ),
        },
      );
      final pricing = custom.getPricing('gpt-4.1');
      expect(pricing!.inputPerMillion, 99.0);
    });

    test('setPricing adds new model', () {
      calculator.setPricing(
        'my-model',
        const AIModelPricing(inputPerMillion: 1.0, outputPerMillion: 2.0),
      );
      expect(calculator.getPricing('my-model'), isNotNull);
    });

    test('removePricing removes model', () {
      calculator.setPricing(
        'temp-model',
        const AIModelPricing(inputPerMillion: 1.0, outputPerMillion: 2.0),
      );
      calculator.removePricing('temp-model');
      expect(calculator.getPricing('temp-model'), isNull);
    });

    test('gemini pricing is available', () {
      final cost = calculator.estimate(
        model: 'gemini-2.5-flash',
        inputTokens: 100000,
        outputTokens: 5000,
      );
      expect(cost, isNotNull);
      // 100000 / 1M * 0.30 = 0.030
      expect(cost!.inputCost, closeTo(0.030, 1e-10));
      // 5000 / 1M * 2.50 = 0.0125
      expect(cost.outputCost, closeTo(0.0125, 1e-10));
    });

    test('zero tokens produces zero cost', () {
      final cost = calculator.estimate(
        model: 'gpt-4.1',
        inputTokens: 0,
        outputTokens: 0,
      );
      expect(cost, isNotNull);
      expect(cost!.totalCost, 0.0);
    });

    test('large token counts produce correct cost', () {
      final cost = calculator.estimate(
        model: 'gpt-4.1',
        inputTokens: 1000000,
        outputTokens: 1000000,
      );
      expect(cost, isNotNull);
      expect(cost!.inputCost, closeTo(2.0, 1e-10));
      expect(cost.outputCost, closeTo(8.0, 1e-10));
      expect(cost.totalCost, closeTo(10.0, 1e-10));
    });
  });

  group('AICostTracker', () {
    late AICostTracker tracker;

    setUp(() {
      tracker = AICostTracker();
    });

    test('starts empty', () {
      expect(tracker.history, isEmpty);
      expect(tracker.totalCost, 0.0);
      expect(tracker.callCount, 0);
      expect(tracker.totalInputTokens, 0);
      expect(tracker.totalOutputTokens, 0);
    });

    test('records and accumulates costs', () {
      const e1 = AICostEstimate(
        inputCost: 0.002,
        outputCost: 0.004,
        totalCost: 0.006,
        model: 'gpt-4.1',
        inputTokens: 1000,
        outputTokens: 500,
        pricing: AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
      );
      const e2 = AICostEstimate(
        inputCost: 0.001,
        outputCost: 0.002,
        totalCost: 0.003,
        model: 'gpt-4.1-mini',
        inputTokens: 2500,
        outputTokens: 1250,
        pricing: AIModelPricing(inputPerMillion: 0.40, outputPerMillion: 1.60),
      );

      tracker.record(e1);
      tracker.record(e2);

      expect(tracker.callCount, 2);
      expect(tracker.totalCost, closeTo(0.009, 1e-10));
      expect(tracker.totalInputTokens, 3500);
      expect(tracker.totalOutputTokens, 1750);
    });

    test('costByModel groups correctly', () {
      const e1 = AICostEstimate(
        inputCost: 0.001,
        outputCost: 0.002,
        totalCost: 0.003,
        model: 'gpt-4.1',
        inputTokens: 500,
        outputTokens: 250,
        pricing: AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
      );
      const e2 = AICostEstimate(
        inputCost: 0.003,
        outputCost: 0.006,
        totalCost: 0.009,
        model: 'gpt-4.1',
        inputTokens: 1500,
        outputTokens: 750,
        pricing: AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
      );
      const e3 = AICostEstimate(
        inputCost: 0.001,
        outputCost: 0.001,
        totalCost: 0.002,
        model: 'gemini-2.5-flash',
        inputTokens: 10000,
        outputTokens: 1000,
        pricing: AIModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60),
      );

      tracker
        ..record(e1)
        ..record(e2)
        ..record(e3);

      final byModel = tracker.costByModel;
      expect(byModel['gpt-4.1'], closeTo(0.012, 1e-10));
      expect(byModel['gemini-2.5-flash'], closeTo(0.002, 1e-10));
    });

    test('clear resets everything', () {
      const e = AICostEstimate(
        inputCost: 0.01,
        outputCost: 0.01,
        totalCost: 0.02,
        model: 'gpt-4.1',
        inputTokens: 5000,
        outputTokens: 1250,
        pricing: AIModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
      );
      tracker.record(e);
      expect(tracker.callCount, 1);

      tracker.clear();
      expect(tracker.callCount, 0);
      expect(tracker.totalCost, 0.0);
      expect(tracker.history, isEmpty);
    });

    test('history is unmodifiable', () {
      expect(
        () => tracker.history.add(
          const AICostEstimate(
            inputCost: 0,
            outputCost: 0,
            totalCost: 0,
            model: 'x',
            inputTokens: 0,
            outputTokens: 0,
            pricing: AIModelPricing(inputPerMillion: 0, outputPerMillion: 0),
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
