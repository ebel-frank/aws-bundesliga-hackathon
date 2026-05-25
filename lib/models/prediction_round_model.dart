class PredictionRoundModel {
  final String roundId;
  final int roundNumber;
  final String questionText;
  final List<String> options;
  final int timeLimitSeconds;
  final String correctAnswer;
  final String category;

  const PredictionRoundModel({
    required this.roundId,
    required this.roundNumber,
    required this.questionText,
    required this.options,
    this.timeLimitSeconds = 15,
    required this.correctAnswer,
    required this.category,
  });

  factory PredictionRoundModel.fromJson(Map<String, dynamic> json) {
    return PredictionRoundModel(
      roundId: json['roundId'] as String,
      roundNumber: json['roundNumber'] as int,
      questionText: json['questionText'] as String,
      options: List<String>.from(json['options']),
      timeLimitSeconds: json['timeLimitSeconds'] as int? ?? 15,
      correctAnswer: json['correctAnswer'] as String,
      category: json['category'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'roundId': roundId,
    'roundNumber': roundNumber,
    'questionText': questionText,
    'options': options,
    'timeLimitSeconds': timeLimitSeconds,
    'correctAnswer': correctAnswer,
    'category': category,
  };
}
