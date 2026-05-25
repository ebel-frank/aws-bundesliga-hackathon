/// Represents a parsed DFL match event.
class DflEvent {
  final String eventId;
  final String matchId;
  final String eventTime;
  final double xPosition;
  final double yPosition;
  final String eventType; // 'KickOff', 'Play', 'Goal', 'Card', etc.
  final String? team;
  final String? player;
  final String? recipient;
  final String? evaluation; // 'successfullyCompleted', 'unsuccessful'
  final String? playOrigin; // 'ownHalf', 'oppositionHalf'
  final String? distance; // 'short', 'medium', 'long'
  final String? height; // 'flat', 'high'
  final String? gameSection; // 'firstHalf', 'secondHalf'
  final String? subType; // 'Pass', 'Shot', 'Cross', etc.
  final Map<String, String> rawAttributes;

  const DflEvent({
    required this.eventId,
    required this.matchId,
    required this.eventTime,
    required this.xPosition,
    required this.yPosition,
    required this.eventType,
    this.team,
    this.player,
    this.recipient,
    this.evaluation,
    this.playOrigin,
    this.distance,
    this.height,
    this.gameSection,
    this.subType,
    this.rawAttributes = const {},
  });

  /// Human-readable summary of the event for toast display.
  String get summary {
    final playerShort = player?.split('-').last ?? '?';
    final recipientShort = recipient?.split('-').last ?? '';
    final teamShort = team?.split('-').last ?? '';

    switch (eventType) {
      case 'KickOff':
        return '⚽ Kick Off! ($gameSection)';
      case 'Play':
        final result = evaluation == 'successfullyCompleted' ? '✓' : '✗';
        final type = subType ?? 'Play';
        return '$result $type by $playerShort → $recipientShort ($distance, $height)';
      case 'Goal':
        return '🎉 GOAL! Scored by $playerShort (Team $teamShort)';
      case 'Card':
        return '🟨 Card for $playerShort';
      default:
        return '📋 $eventType (Player $playerShort)';
    }
  }

  @override
  String toString() => 'DflEvent($eventId: $summary)';
}
