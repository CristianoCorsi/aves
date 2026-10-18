import 'dart:typed_data';

import 'package:aves/model/semantic/auto_tagger.dart';
import 'package:aves/model/semantic/rows.dart';
import 'package:aves/model/semantic/vector.dart';
import 'package:test/test.dart';

Float32List _vector(List<double> values) => normalizeVector(values);

void main() {
  const dog = SemanticLabel(prompt: 'dog', tag: 'cane');
  const cat = SemanticLabel(prompt: 'cat', tag: 'gatto');
  const puppy = SemanticLabel(prompt: 'puppy', tag: 'cane');
  final labelVectors = [
    SemanticLabelVector(dog, _vector([1, 0, 0])),
    SemanticLabelVector(cat, _vector([0, 1, 0])),
    SemanticLabelVector(puppy, _vector([.9, .1, 0])),
  ];

  test('tags above threshold, by decreasing score, merged by tag name', () {
    final image = prepareVector([.8, .6, 0], 3);
    final tags = SemanticAutoTagger.tagsFor(image, labelVectors, threshold: .5, maxCount: 5);
    expect(tags.map((v) => v.$1), ['cane', 'gatto']);
    // best score among labels with the same tag name
    expect(tags.first.$2, closeTo(.86, .02));

    expect(SemanticAutoTagger.tagsFor(image, labelVectors, threshold: .7, maxCount: 5).map((v) => v.$1), ['cane']);
    expect(SemanticAutoTagger.tagsFor(image, labelVectors, threshold: 0, maxCount: 1).map((v) => v.$1), ['cane']);
  });

  test('failure markers are not tagged', () {
    final rows = {
      SemanticEmbeddingRow(id: 1, modelId: 'm', vector: prepareVector([0, 1, 0], 3), dateModifiedMillis: 0),
      SemanticEmbeddingRow.failure(id: 2, modelId: 'm', dateModifiedMillis: 0),
    };
    final tagRows = SemanticAutoTagger.tagRows(rows, labelVectors, threshold: .5, maxCount: 3);
    expect(tagRows.map((v) => (v.id, v.tag)), [(1, 'gatto')]);
  });

  test('custom labels are trimmed and deduplicated by prompt', () {
    expect(SemanticAutoTagger.customLabels([' boat ', '', 'boat']).map((v) => v.prompt).toSet(), {'boat'});
  });

  test('label vectors are cached', () async {
    final cache = <SemanticLabelRow>[];
    var embedCount = 0;
    Future<List<SemanticLabelVector>> run() => SemanticAutoTagger.labelVectors(
      labels: [dog, cat],
      modelId: 'm',
      dimension: 2,
      loadCache: () async => List.of(cache),
      saveCache: (rows) async => cache.addAll(rows),
      embedTexts: (texts) async {
        embedCount += texts.length;
        return texts.map((text) => _vector(text.endsWith('dog') ? [1, 0, 0] : [0, 1, 0])).toList();
      },
    );

    final first = await run();
    expect(first.length, 2);
    expect(first.first.vector.length, 2);
    expect(embedCount, 2);

    await run();
    expect(embedCount, 2);
  });
}
