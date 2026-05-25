class PlayerPickModel {
  final String userId;
  final String pick;
  final bool hasLocked;
  final int secondsTaken;
  final int pointsAwarded;
  final bool isCorrect;

  const PlayerPickModel({
    required this.userId,
    this.pick = '',
    this.hasLocked = false,
    this.secondsTaken = 0,
    this.pointsAwarded = 0,
    this.isCorrect = false,
  });

  PlayerPickModel copyWith({
    String? pick,
    bool? hasLocked,
    int? secondsTaken,
    int? pointsAwarded,
    bool? isCorrect,
  }) {
    return PlayerPickModel(
      userId: userId,
      pick: pick ?? this.pick,
      hasLocked: hasLocked ?? this.hasLocked,
      secondsTaken: secondsTaken ?? this.secondsTaken,
      pointsAwarded: pointsAwarded ?? this.pointsAwarded,
      isCorrect: isCorrect ?? this.isCorrect,
    );
  }

  factory PlayerPickModel.fromJson(Map<String, dynamic> json) {
    return PlayerPickModel(
      userId: json['userId'] as String,
      pick: json['pick'] as String? ?? '',
      hasLocked: json['hasLocked'] as bool? ?? false,
      secondsTaken: json['secondsTaken'] as int? ?? 0,
      pointsAwarded: json['pointsAwarded'] as int? ?? 0,
      isCorrect: json['isCorrect'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'pick': pick,
    'hasLocked': hasLocked,
    'secondsTaken': secondsTaken,
    'pointsAwarded': pointsAwarded,
    'isCorrect': isCorrect,
  };
}
