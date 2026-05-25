/// A match event that awards or deducts points for a fantasy player.
/// Scoring: Goal = +5, Assist = +3, Yellow card = -1, Red card = -2.
class FantasyMatchEvent {
  final String eventId;
  final String playerId;
  final String playerName;
  final String team;
  final String type; // 'goal' | 'assist' | 'yellow_card' | 'red_card'
  final int minute;
  final int points;

  const FantasyMatchEvent({
    required this.eventId,
    required this.playerId,
    required this.playerName,
    required this.team,
    required this.type,
    required this.minute,
    required this.points,
  });

  static int pointsForType(String type) {
    switch (type) {
      case 'goal':
        return 5;
      case 'assist':
        return 3;
      case 'yellow_card':
        return -1;
      case 'red_card':
        return -2;
      default:
        return 0;
    }
  }

  String get icon {
    switch (type) {
      case 'goal':
        return '⚽';
      case 'assist':
        return '🅰️';
      case 'yellow_card':
        return '🟨';
      case 'red_card':
        return '🟥';
      default:
        return '•';
    }
  }

  String get label {
    switch (type) {
      case 'goal':
        return 'Goal';
      case 'assist':
        return 'Assist';
      case 'yellow_card':
        return 'Yellow Card';
      case 'red_card':
        return 'Red Card';
      default:
        return type;
    }
  }

  String get pointsLabel => points > 0 ? '+$points' : '$points';

  bool get isPositive => points > 0;
}
