import 'package:aves/model/semantic/profile.dart';
import 'package:aves/model/semantic/vector.dart';
import 'package:aves_model/aves_model.dart';
import 'package:test/test.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  test('recommended profile follows device resources', () {
    expect(SemanticPerformanceParams.recommendedProfile(totalRamBytes: 12 * gb, mediaPerformanceClass: 34), SemanticPerformanceProfile.high);
    expect(SemanticPerformanceParams.recommendedProfile(totalRamBytes: 12 * gb, mediaPerformanceClass: 0), SemanticPerformanceProfile.balanced);
    expect(SemanticPerformanceParams.recommendedProfile(totalRamBytes: 6 * gb, mediaPerformanceClass: 31), SemanticPerformanceProfile.balanced);
    expect(SemanticPerformanceParams.recommendedProfile(totalRamBytes: 4 * gb, mediaPerformanceClass: 31), SemanticPerformanceProfile.low);
    expect(SemanticPerformanceParams.recommendedProfile(totalRamBytes: 0, mediaPerformanceClass: 0), SemanticPerformanceProfile.low);
  });

  test('presets use supported vector dimensions', () {
    for (final profile in SemanticPerformanceProfile.values) {
      final params = SemanticPerformanceParams.forProfile(profile);
      if (profile == SemanticPerformanceProfile.custom) {
        expect(params, isNull);
      } else {
        expect(semanticVectorDimensions, contains(params!.vectorDimension));
        expect(SemanticPerformanceParams.thumbnailSizeOptions, contains(params.thumbnailSize));
        expect(SemanticPerformanceParams.maxItemsPerRunOptions, contains(params.maxItemsPerRun));
        expect(SemanticPerformanceParams.itemDelayMillisOptions, contains(params.itemDelayMillis));
      }
    }
  });
}
