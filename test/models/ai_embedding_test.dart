import 'package:ai_core/models/ai_embedding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIEmbeddingRequest', () {
    test('creates request with multiple inputs', () {
      const request = AIEmbeddingRequest(
        input: ['hello', 'world'],
        model: 'text-embedding-3-small',
      );
      expect(request.input, ['hello', 'world']);
      expect(request.model, 'text-embedding-3-small');
      expect(request.dimensions, isNull);
    });

    test('single factory creates with one input', () {
      final request = AIEmbeddingRequest.single(
        'hello',
        model: 'text-embedding-3-small',
        dimensions: 256,
      );
      expect(request.input, ['hello']);
      expect(request.model, 'text-embedding-3-small');
      expect(request.dimensions, 256);
    });
  });

  group('AIEmbeddingResponse', () {
    test('firstVector returns first embedding', () {
      const response = AIEmbeddingResponse(
        embeddings: [
          AIEmbedding(index: 0, embedding: [0.1, 0.2, 0.3]),
          AIEmbedding(index: 1, embedding: [0.4, 0.5, 0.6]),
        ],
        model: 'text-embedding-3-small',
        totalTokens: 10,
        raw: {},
      );
      expect(response.firstVector, [0.1, 0.2, 0.3]);
      expect(response.embeddings.length, 2);
      expect(response.totalTokens, 10);
    });
  });

  group('AIEmbedding', () {
    test('stores index and vector', () {
      const embedding = AIEmbedding(index: 0, embedding: [1.0, 2.0, 3.0]);
      expect(embedding.index, 0);
      expect(embedding.embedding, [1.0, 2.0, 3.0]);
    });
  });
}
