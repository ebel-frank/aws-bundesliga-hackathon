import 'fantasy_match_event_model.dart';

/// A football player available for selection in the Fantasy module.
/// Distinct from [PlayerModel] which represents an app user in Arena.
class FantasyFootballPlayer {
  final String id;
  final String name;
  final String position; // 'GK' | 'DEF' | 'MID' | 'FWD'
  final String team;
  final String teamBadge; // SVG asset path
  final int points;
  final List<FantasyMatchEvent> events;

  const FantasyFootballPlayer({
    required this.id,
    required this.name,
    required this.position,
    required this.team,
    this.teamBadge = '',
    this.points = 0,
    this.events = const [],
  });

  FantasyFootballPlayer copyWith({
    int? points,
    List<FantasyMatchEvent>? events,
  }) {
    return FantasyFootballPlayer(
      id: id,
      name: name,
      position: position,
      team: team,
      teamBadge: teamBadge,
      points: points ?? this.points,
      events: events ?? this.events,
    );
  }
}
