import 'dart:ui';

/// A user's fantasy team entry for a specific match.
/// Tracks which 11 players they selected and their accumulated points.
class FantasyEntry {
  final String userId;
  final String displayName;
  final Color avatarColor;
  final List<String> selectedPlayerIds; // exactly 11 player IDs
  final int totalPoints;

  const FantasyEntry({
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.selectedPlayerIds,
    this.totalPoints = 0,
  });

  FantasyEntry copyWith({
    List<String>? selectedPlayerIds,
    int? totalPoints,
  }) {
    return FantasyEntry(
      userId: userId,
      displayName: displayName,
      avatarColor: avatarColor,
      selectedPlayerIds: selectedPlayerIds ?? this.selectedPlayerIds,
      totalPoints: totalPoints ?? this.totalPoints,
    );
  }

  String get initials => displayName.length >= 2
      ? displayName.substring(0, 2).toUpperCase()
      : displayName.toUpperCase();
}
