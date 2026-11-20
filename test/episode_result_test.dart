import 'package:flutter_test/flutter_test.dart';
import 'package:dolboebometr/episode_result.dart';

void main() {
  test('unclear situation never receives a score', () {
    final result = EpisodeResult.fromJson({
      'status': 'unclear', 'score': 80, 'observation': 'Мало данных'
    });
    expect(result.score, isNull);
    expect(result.observed, isFalse);
  });
  test('demo is clearly labeled', () {
    expect(EpisodeResult.demoResult.demo, isTrue);
  });
}
