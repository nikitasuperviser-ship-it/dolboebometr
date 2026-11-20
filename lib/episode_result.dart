class EpisodeResult {
  const EpisodeResult({
    required this.observed,
    required this.score,
    required this.observation,
    required this.comment,
    this.demo = false,
  });
  final bool observed;
  final int? score;
  final String observation;
  final String comment;
  final bool demo;

  factory EpisodeResult.fromJson(Map<String, dynamic> json) {
    final observed = json['status'] == 'observed';
    final raw = json['score'];
    return EpisodeResult(
      observed: observed,
      score: observed && raw is num ? raw.round().clamp(0, 100).toInt() : null,
      observation: json['observation'] is String
          ? json['observation'] as String : 'Недостаточно данных.',
      comment: json['quip'] is String ? json['quip'] as String : '',
    );
  }

  static const demoResult = EpisodeResult(
    observed: true,
    score: 87,
    observation: 'Вымышленная ситуация: человек трижды нажал уже подсвеченную кнопку лифта.',
    comment: 'Похоже, лифт решил не торопиться, несмотря на все уговоры.',
    demo: true,
  );
}
