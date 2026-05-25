import 'dart:ui';

class PlayerModel {
  final String userId;
  final String displayName;
  final Color avatarColor;
  final int totalXP;
  final int streak;
  final List<String> badges;
  final bool isHost;
  final bool isConnected;

  const PlayerModel({
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    this.totalXP = 0,
    this.streak = 0,
    this.badges = const [],
    this.isHost = false,
    this.isConnected = true,
  });

  String get initials => displayName.length >= 2
      ? displayName.substring(0, 2).toUpperCase()
      : displayName.toUpperCase();

  PlayerModel copyWith({
    int? totalXP,
    int? streak,
    List<String>? badges,
    bool? isConnected,
  }) {
    return PlayerModel(
      userId: userId,
      displayName: displayName,
      avatarColor: avatarColor,
      totalXP: totalXP ?? this.totalXP,
      streak: streak ?? this.streak,
      badges: badges ?? this.badges,
      isHost: isHost,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  factory PlayerModel.fromJson(Map<String, dynamic> json) {
    return PlayerModel(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      avatarColor: Color(json['avatarColor'] as int),
      totalXP: json['totalXP'] as int? ?? 0,
      streak: json['streak'] as int? ?? 0,
      badges: List<String>.from(json['badges'] ?? []),
      isHost: json['isHost'] as bool? ?? false,
      isConnected: json['isConnected'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'avatarColor': avatarColor.toARGB32(),
    'totalXP': totalXP,
    'streak': streak,
    'badges': badges,
    'isHost': isHost,
    'isConnected': isConnected,
  };
}
