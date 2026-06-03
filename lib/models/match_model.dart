/// Represents a football match that users can predict on.
class MatchModel {
  final String matchId;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamBadge; // SVG asset path
  final String awayTeamBadge; // SVG asset path
  final String league;
  final String matchTime; // e.g., "21:00"
  final String matchDate; // e.g., "Today", "Tomorrow", "Jun 15"
  final String status; // 'upcoming' | 'live' | 'finished'
  final int roomCount; // number of active rooms for this match

  const MatchModel({
    required this.matchId,
    required this.homeTeam,
    required this.awayTeam,
    this.homeTeamBadge = '',
    this.awayTeamBadge = '',
    this.league = '',
    this.matchTime = '',
    this.matchDate = '',
    this.status = 'upcoming',
    this.roomCount = 0,
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    return MatchModel(
      matchId: json['matchId'] as String,
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      homeTeamBadge: json['homeTeamBadge'] as String? ?? '',
      awayTeamBadge: json['awayTeamBadge'] as String? ?? '',
      league: json['league'] as String? ?? '',
      matchTime: json['matchTime'] as String? ?? '',
      matchDate: json['matchDate'] as String? ?? '',
      status: json['status'] as String? ?? 'upcoming',
      roomCount: json['roomCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'homeTeamBadge': homeTeamBadge,
    'awayTeamBadge': awayTeamBadge,
    'league': league,
    'matchTime': matchTime,
    'matchDate': matchDate,
    'status': status,
    'roomCount': roomCount,
  };

  MatchModel copyWith({int? roomCount, String? status}) {
    return MatchModel(
      matchId: matchId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      homeTeamBadge: homeTeamBadge,
      awayTeamBadge: awayTeamBadge,
      league: league,
      matchTime: matchTime,
      matchDate: matchDate,
      status: status ?? this.status,
      roomCount: roomCount ?? this.roomCount,
    );
  }
}
